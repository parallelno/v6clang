# Plan: O54 — Optimal Stack Adjustment Strategy (prologue/epilogue baseline)

Reference: [O54_optimal_stack_adjustment.md](future_plans/O54_optimal_stack_adjustment.md)

## 1. Problem

### Current behavior

`V6ClangFrameLowering::emitPrologue()` and `emitEpilogue()` always adjust SP
through the same fixed 5-byte / 32-cycle sequence regardless of how
small the frame is:

```asm
; SP -= N (prologue)              ; SP += N (epilogue)
LXI  H, -N      ; 3B / 12cc       LXI  H, N       ; 3B / 12cc
DAD  SP         ; 1B / 12cc       DAD  SP         ; 1B / 12cc
SPHL            ; 1B /  8cc       SPHL            ; 1B /  8cc
; total 5B / 32cc                 ; total 5B / 32cc
```

Even when the frame is just 2 or 4 bytes — a single `i8` or `i16`
spill — emitPrologue/emitEpilogue still emit the full LXI+DAD+SPHL
pair on entry and exit.

### Desired behavior

For small **even** adjustments, decrement SP via `PUSH rp` and
increment SP via `POP rp`. Each `PUSH`/`POP` of any GR16All pair
shifts SP by 2 in 1 byte. The pushed value is irrelevant for a
prologue (we are only allocating space) and the popped value is
discarded for an epilogue (provided the destination register is dead
at that point).

```asm
; SP -= 4 (prologue)              ; SP += 4 (epilogue)
PUSH PSW        ; 1B / 16cc       POP  PSW        ; 1B / 12cc
PUSH PSW        ; 1B / 16cc       POP  PSW        ; 1B / 12cc
; total 2B / 32cc                 ; total 2B / 24cc
```

### Root cause

`emitPrologue/emitEpilogue` were written for the general case (any
non-zero stack size) and never refined. The cost analysis below shows
that `POP rp × n/2` strictly dominates `LXI+DAD+SPHL` on bytes for
n ∈ {2, 4, 6} and on cycles for n ∈ {2, 4}. `PUSH rp × n/2` strictly
dominates on bytes for n ∈ {2, 4, 6} and on cycles for n = 2 (ties at
n = 4). At n ≥ 8 the LXI sequence wins on cycles.

When no GR16All pair is dead at the adjustment point, the fallback is
not the LXI sequence but `DCX SP` / `INX SP × n` (1B / 8cc each, no
clobber of any register). This wins on both axes against
`LXI+DAD+SPHL` for n ∈ {2, 4} and ties on bytes (loses on cycles) at
n = 6. Verified in [V6ClangInstrInfo.td](../llvm/lib/Target/V6Clang/V6ClangInstrInfo.td):
`INX rp` / `DCX rp` accept `GR16AllPair`, and `GR16All` includes
`SP`, so `INX SP` (encoding 0x33) and `DCX SP` (0x3B) are legal
emissions today.

The decision is the same one jacobly0's Z80 backend makes in
`Z80FrameLowering::getOptimalStackAdjustmentMethod()`.

## 2. Strategy

### Approach: factored helper `emitSPAdjustment()` driven by O11 cost mode

Introduce two private helpers in `V6ClangFrameLowering`:

1. `chooseDeadPair(MBB, MBBI, IsPrologue) -> Register` — pick a
   GR16All pair whose halves are dead at the adjustment point. Always
   prefer `PSW` (A + flags) when its components are dead, falling
   back to `BC`, `DE`, `HL` as candidates. Returns `V6CLANG::NoRegister`
   when none qualifies (e.g. all GR16 pairs are live-in arg regs).
   - **Prologue**: at the very start of the entry MBB, `PSW` is dead
     unless the function uses the `i8` / flags ABI for an argument.
     A is dead unless A is in the entry MBB live-ins; FLAGS is always
     dead. `BC` is dead unless the function uses BC for arg-3 (or as
     the FP, gated separately). `DE`/`HL` similarly governed by
     live-ins.
   - **Epilogue**: at the RET, `PSW` is dead unless A is the i8
     return register **and** is read by the RET. `HL` is dead unless
     it carries an i16 return; `DE` is dead unless it carries the
     i32 high half. `BC` is always dead at exit (callee-clobbered).

2. `emitSPAdjustment(MBB, MBBI, Amount, DL, IsPrologue, Mode)` —
   emit one of three sequences according to the cost decision below:
   * **PUSH/POP × n/2** when `chooseDeadPair` returns a usable pair
     and the cost beats LXI under `Mode`.
   * **DCX/INX SP × n** when no dead pair is available but n ∈ {2, 4}.
   * **LXI+DAD+SPHL** otherwise (n = 6 in non-Size mode, n ≥ 8, odd).

   Mode is obtained via `getV6ClangOptMode(MF)` (O11).

### Cost decision (3-tier strategy)

Reference: `LXI+DAD+SPHL` = 5B / 32cc (clobbers HL+FLAGS).
`PUSH rp` = 1B / 16cc (no clobber if rp source is dead).
`POP rp`  = 1B / 12cc (clobbers rp).
`DCX SP` / `INX SP` = 1B / 8cc each (clobbers nothing).

| `\|N\|` | PUSH/POP × n/2 (if dead pair) | DCX/INX SP × n (no clobber) | LXI+DAD+SPHL | Verdict |
|-------|-------------------------------|------------------------------|--------------|---------|
| 2 pro | 1B / 16cc                     | 2B / 16cc                    | 5B / 32cc    | PUSH if dead pair, else DCX×2 |
| 4 pro | 2B / 32cc                     | 4B / 32cc                    | 5B / 32cc    | PUSH if dead pair, else DCX×4 |
| 6 pro | 3B / 48cc                     | 6B / 48cc                    | 5B / 32cc    | PUSH (size-only); else LXI |
| 2 epi | 1B / 12cc                     | 2B / 16cc                    | 5B / 32cc    | POP if dead pair, else INX×2 |
| 4 epi | 2B / 24cc                     | 4B / 32cc                    | 5B / 32cc    | POP if dead pair, else INX×4 |
| 6 epi | 3B / 36cc                     | 6B / 48cc                    | 5B / 32cc    | POP (size-only); else LXI |
| odd, ≥8 | —                           | —                            | —            | LXI+DAD+SPHL |

`Mode == V6ClangOptMode::Size` enables the n=6 PUSH/POP case; `Speed`
and `Balanced` reject it.

The `DCX/INX SP × n` path is enabled for **n ∈ {2, 4} only** in all
modes — at n = 6 it ties LXI on bytes and loses on cycles, so the
LXI path is preferred there.

The DCX/INX SP fallback is a strict improvement over LXI for n ∈ {2, 4}:
* `DCX SP` / `INX SP` is 1B / 8cc.
* It clobbers **nothing** — neither HL nor any GR16 pair, neither A
  nor flags. This eliminates the `HLIsLiveIn` / `NeedHLSave` save-
  /restore dance that the existing emitter performs around the LXI
  sequence for the small-frame case.

### Why this works

* `PUSH rp` is documented (V6ClangInstructionTimings.md) as 1B / 16cc and
  modifies only SP and `[SP-1..SP-2]`. The *source register pair* is
  read but unmodified, so a dead source means the value lost to RAM
  is irrelevant.
* `POP rp` is 1B / 12cc and modifies SP and the destination pair.
  When all halves of the destination are dead, the loaded garbage is
  immediately killed.
* `PSW` is the preferred pick because both A and the flags are
  typically dead at function boundaries (A is dead at entry except
  when used as arg-1, dead at exit except when carrying an i8
  return; FLAGS is always dead at function boundaries). When `PSW`
  is unavailable, fall back to a free GR16 pair.
* `DCX SP` / `INX SP` is 1B / 8cc, encoded with RP=3 in the standard
  `00_RP_1011` / `00_RP_0011` slots. The instruction has
  `Constraints = "$rp = $src"` (tied operand) and reads/writes only
  SP — no other register, no flags. This is the universal-fallback
  path: it is correct regardless of register pressure and beats LXI
  on both bytes and cycles for n ∈ {2, 4}.
* `chooseDeadPair` consults `MachineBasicBlock::isLiveIn` (prologue)
  and the operands of the terminating `RET` instruction (epilogue) —
  both are already used by the existing emitter for the same liveness
  questions (see `HLIsLiveIn`, `DEIsLiveIn`, `HLUsedByRet`,
  `DEUsedByRet`).

### Summary of changes

* `V6ClangFrameLowering.cpp`
  * Add private helpers `chooseDeadPair()` and `emitSPAdjustment()`.
  * `emitSPAdjustment` implements the 3-tier decision: PUSH/POP →
    DCX/INX SP → LXI+DAD+SPHL.
  * Replace **every** direct `LXI/DAD/SPHL` emission triplet in
    `emitPrologue` / `emitEpilogue` with `emitSPAdjustment(...)`.
  * Compute opt mode once at function top via `getV6ClangOptMode(MF)`.
  * Include `V6ClangInstrCost.h`.
* `V6ClangFrameLowering.h`
  * Forward-declare new helpers (private members).
* New lit test `frame-lowering-pop-push.ll` covering −2 / −4 / −6 /
  −8 prologues and +2 / +4 / +6 / +8 epilogues, an `optsize` case
  for −6 / +6, and a high-pressure case where no dead pair is
  available (forces the DCX/INX SP fallback).
* Existing `frame-lowering.ll` updated: `one_local` (1B → padded to 2B
  by alignment? — actually V6CLANG frame is 1-byte aligned, so 1B stays
  1B → odd → unchanged LXI sequence) and `array_local` (4B → POP/PUSH
  pair). The CHECK lines for the 4-byte case will switch to
  `PUSH PSW; PUSH PSW` / `POP PSW; POP PSW`.
* `tests/features/47/` — feature test case.
* `design/future_plans/O54_optimal_stack_adjustment.md` — mark `[x]`
  in the README table after completion.
* `design/future_plans/README.md` — update the four O54-family rows.

## 3. Implementation Steps

### Step 3.1 — Read reference documents [x]

Read in this order before touching code:
* `design/future_plans/O54_optimal_stack_adjustment.md` (this plan's
  source).
* `docs/V6ClangInstructionTimings.md` — verify PUSH/POP/LXI/DAD/SPHL
  costs.
* `docs/V6ClangBuildGuide.md` — build & mirror sync commands.
* `llvm/lib/Target/V6Clang/V6ClangFrameLowering.cpp` (current state) and
  `V6ClangFrameLowering.h`.
* `llvm/lib/Target/V6Clang/V6ClangInstrCost.h` (O11 mode + costs).

> **Implementation Notes**:

### Step 3.2 — Add helpers to V6ClangFrameLowering [x]

In `llvm-project/llvm/lib/Target/V6Clang/V6ClangFrameLowering.{h,cpp}`:

```cpp
// V6ClangFrameLowering.h (private section)
private:
  /// Pick a GR16All pair whose halves are dead at MBBI for use as
  /// PUSH/POP filler. Returns V6CLANG::PSW when A+FLAGS are dead,
  /// otherwise BC/DE/HL/NoRegister in that fallback order.
  Register chooseDeadPair(const MachineBasicBlock &MBB,
                          MachineBasicBlock::iterator MBBI,
                          bool IsPrologue) const;

  /// Emit an SP adjustment of `Amount` bytes (signed: negative = SP
  /// decrement / allocate; positive = SP increment / deallocate) at
  /// MBBI. Chooses between PUSH/POP × |Amount|/2 and LXI+DAD+SPHL
  /// based on the dual cost model (O11).
  void emitSPAdjustment(MachineBasicBlock &MBB,
                        MachineBasicBlock::iterator MBBI,
                        int64_t Amount, const DebugLoc &DL,
                        bool IsPrologue, V6ClangOptMode Mode) const;
```

`chooseDeadPair` for **prologues** consults `MBB.isLiveIn(...)` for
each of `A`, `B`/`C`, `D`/`E`, `H`/`L`. For **epilogues** it
consults the terminating RET's operands (mirrors the existing
`HLUsedByRet` / `DEUsedByRet` logic). PSW is "free" iff A is not
live (FLAGS is never explicitly tracked as live across a return).

`emitSPAdjustment` body:
1. If `Amount == 0`: return.
2. `unsigned AbsN = std::abs(Amount)`; `bool IsAlloc = Amount < 0`.
3. Compute `bool PushPopEligible`:
   * `(AbsN % 2) == 0 && AbsN >= 2` is a precondition.
   * `AbsN ∈ {2, 4}` → eligible.
   * `AbsN == 6 && Mode == V6ClangOptMode::Size` → eligible.
   * else → not eligible.
4. If `PushPopEligible`:
   `Register Pair = chooseDeadPair(MBB, MBBI, IsAlloc);`
   If `Pair != V6CLANG::NoRegister`, emit `AbsN / 2` × PUSH/POP and
   return:
   * Prologue: `BuildMI(...PUSH...).addReg(Pair)` (read-only).
   * Epilogue: `BuildMI(...POP..., Pair)` with
     `RegState::Define | RegState::Dead` on the def operand.
5. **DCX/INX SP fallback** — applies when PUSH/POP wasn't eligible
   *or* no dead pair was available. If `AbsN ∈ {2, 4}` (any mode):
   * Emit `AbsN` × `BuildMI(...DCX/INX..., V6CLANG::SP).addReg(V6CLANG::SP)`.
     Prologue uses `V6CLANG::DCX`; epilogue uses `V6CLANG::INX`. The tied
     `$rp = $src` operand is satisfied by passing SP as both def and
     use.
   * Return.
6. **LXI path** — n = 6 in non-Size mode, n ≥ 8, or odd. Emit the
   existing `LXI H, ±N; DAD SP; SPHL` triplet.

> **Design Notes**:
> * The `Dead` flag on `POP rp` is essential — it tells later passes
>   (verifier, liveness) that the popped value is intentionally
>   discarded.
> * PSW is encoded as RP=3 in PUSH/POP and accepted by the existing
>   emitter even though it is not in `GR16All` (special-cased — see
>   `tryParseRegister` notes in repo memory).
> * `INX SP` / `DCX SP` use the same `GR16AllPair` operand class as
>   `INX HL` etc.; SP is in `GR16All`, so no new TableGen change is
>   required.

> **Implementation Notes**:

### Step 3.3 — Replace LXI/DAD/SPHL sites in emitPrologue [x]

There are three LXI+DAD+SPHL sites in `emitPrologue` to replace:
1. The `Case 1` (HL+DE both live-in) site that uses `OrigStackSize`.
2. The default site that uses `StackSize`.
The third "set up frame pointer" sequence (LXI 0; DAD SP; MOV B,H;
MOV C,L) is **not** an SP adjustment — leave it untouched.

Each replacement passes `Amount = -OrigStackSize` (resp. `-StackSize`)
to `emitSPAdjustment` with `IsPrologue=true`.

> **Implementation Notes**:

### Step 3.4 — Replace LXI/DAD/SPHL sites in emitEpilogue [x]

One SP-adjustment site at the end of the default (no-FP) path uses
`+StackSize`. Replace with `emitSPAdjustment(... +StackSize, ... IsPrologue=false ...)`.

The frame-pointer epilogue (`MOV H,B; MOV L,C; SPHL; POP BC`) is **not**
an LXI-based SP adjustment — leave untouched.

> **Implementation Notes**:

### Step 3.5 — Wire opt mode through emitPrologue/emitEpilogue [x]

At the top of each, compute `V6ClangOptMode Mode = getV6ClangOptMode(MF);`
once and pass it to every `emitSPAdjustment` call.

> **Implementation Notes**:

### Step 3.6 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

Diagnose & fix any compile errors, rebuild.

> **Implementation Notes**:

### Step 3.7 — Lit test: new `frame-lowering-pop-push.ll` [x]

Create `llvm-project/llvm/test/CodeGen/V6Clang/frame-lowering-pop-push.ll`
with these functions (each with `-v6clang-disable-alloca-promote
-v6clang-disable-static-stack-alloc` so the stack frame is exercised):

* `frame2`: 2-byte alloca → expect `PUSH PSW` / `POP PSW`.
* `frame4`: 4-byte alloca → expect 2× PUSH PSW / 2× POP PSW.
* `frame6_speed` (default attrs): 6-byte alloca → expect LXI+DAD+SPHL.
* `frame6_size` (`optsize` attribute): 6-byte alloca → expect 3× PUSH PSW / 3× POP PSW.
* `frame8`: 8-byte alloca → expect LXI+DAD+SPHL.
* `frame_oddsize_5`: 5-byte alloca → expect LXI+DAD+SPHL.
* `frame4_no_dead_pair`: 4-byte alloca in a function whose entry
  MBB has every GR16 pair (and PSW) live-in — e.g. takes 3 i16 args
  (HL, DE, BC) that are all used after the alloca, plus an i8 in A.
  Expected: 4× `DCX SP` in the prologue and 4× `INX SP` in the
  epilogue (no PUSH/POP, no LXI).

Run:
```
llvm-build\bin\llvm-lit -v llvm-project\llvm\test\CodeGen\V6Clang\frame-lowering-pop-push.ll
```

> **Implementation Notes**:

### Step 3.8 — Lit test: update existing `frame-lowering.ll` [x]

`one_local` (1-byte): odd → still LXI+DAD+SPHL → CHECK lines unchanged.

`array_local` (4-byte): even, ≤4 → switches to PUSH PSW / POP PSW.
Update the CHECK lines accordingly.

Run:
```
llvm-build\bin\llvm-lit -v llvm-project\llvm\test\CodeGen\V6Clang\frame-lowering.ll
```

Also re-run `frame-leaf.ll` (no SP adjust expected; should be
unaffected).

> **Implementation Notes**:

### Step 3.9 — Build [x]

Rebuild after lit test edits (no source change expected, but confirm
clean state).

> **Implementation Notes**:

### Step 3.10 — Run regression tests [x]

```
python tests\run_all.py
```

If any test fails, diagnose & fix, then rebuild.

Special attention:
* `tests/lit/CodeGen/V6Clang/spill-reload.ll` — exercises the same
  disabled-pass codepath; a 4-byte frame would regress without an
  update.
* `tests/lit/CodeGen/V6Clang/xchg-cancel-peephole.ll` — same gating.
* All 16 golden tests must still pass with the same byte-exact
  outputs (functional equivalence).

> **Implementation Notes**:

### Step 3.11 — Verification assembly steps from `tests\features\README.md` [x]

In `tests/features/47/`:

```
llvm-build\bin\clang.exe --target=i8080-unknown-v6clang -O2 -S \
  -mllvm -v6clang-disable-alloca-promote -mllvm -v6clang-disable-static-stack-alloc \
  tests\features\47\v6clang.c -o tests\features\47\v6clang_new01.asm
```

Compare `v6clang_old.asm` vs `v6clang_new01.asm` — confirm the
prologue/epilogue collapsed from `LXI H, -4; DAD SP; SPHL` /
`LXI H, 4; DAD SP; SPHL` to `PUSH PSW; PUSH PSW` / `POP PSW; POP PSW`.

Iterate `_new02`, `_new03` if needed.

> **Implementation Notes**:

### Step 3.12 — Make sure `result.txt` is created. `tests\features\README.md` [x]

Populate `tests/features/47/result.txt` per the README structure
(C source, c8080 asm, c8080 stats, v6clang asm, v6clang stats).

> **Implementation Notes**:

### Step 3.13 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

Verify `llvm/lib/Target/V6Clang/V6ClangFrameLowering.cpp` matches
`llvm-project/llvm/lib/Target/V6Clang/V6ClangFrameLowering.cpp`.

> **Implementation Notes**:

### Step 3.14 — Mark plan + future_plans/README.md complete [x]

* Set every `[ ]` in this file to `[x]`.
* In `design/future_plans/README.md`: change the O54 row in the
  "Optimization Plans" and "Summary Table" to `[x]`.
* In `design/future_plans/O54_optimal_stack_adjustment.md`: add a
  short "Status: implemented YYYY-MM-DD" note under the title.

> **Implementation Notes**:

## 4. Expected Results

### Example 1 — `array_local` from `frame-lowering.ll`

```asm
; Before:                          ; After:
LXI  H, 0xfffc   ; 3B / 12cc       PUSH PSW         ; 1B / 16cc
DAD  SP          ; 1B / 12cc       PUSH PSW         ; 1B / 16cc
SPHL             ; 1B /  8cc
... body ...                       ... body ...
LXI  H, 4        ; 3B / 12cc       POP  PSW         ; 1B / 12cc
DAD  SP          ; 1B / 12cc       POP  PSW         ; 1B / 12cc
SPHL             ; 1B /  8cc
RET                                RET
; prologue: 5B/32cc                ; prologue: 2B/32cc (-3B, =cc)
; epilogue: 5B/32cc                ; epilogue: 2B/24cc (-3B, -8cc)
```

### Example 2 — `frame2` (single 2-byte spill)

```asm
; Before:                          ; After:
LXI H, 0xffff    ; 5B/32cc         PUSH PSW         ; 1B/16cc
DAD SP                             ...
SPHL                               POP  PSW         ; 1B/12cc
... body ...
LXI H, 1         ; 5B/32cc
DAD SP
SPHL
RET                                RET
; total prologue+epilogue: 10B/64cc → 2B/28cc (-8B, -36cc)
```

### Example 3 — `frame6_size` (`-Os`)

Size-only path picks PUSH×3 / POP×3 (3B / 48cc + 3B / 36cc) over LXI
(5B / 32cc + 5B / 32cc): saves 4B but costs +20cc. Acceptable for
`-Os`/`-Oz`.

### Example 4 — `frame8`

8-byte frame: PUSH×4 (4B / 64cc) loses to LXI (5B / 32cc) on cycles
under any mode that values cycles. The plan correctly falls through
to LXI for n ≥ 8.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `chooseDeadPair` mis-classifies a live register as dead → silently corrupts an arg/return value | (1) Default to `PSW` whose halves are dead at function boundaries by ABI invariant. (2) Mirror the exact liveness checks already used by `emitPrologue` / `emitEpilogue` for `HLIsLiveIn` / `HLUsedByRet`. (3) `frame-lowering-pop-push.ll` covers i8/i16 arg + i8/i16 return cases. (4) When in doubt the helper returns `NoRegister`, which routes to the safe DCX/INX SP path. |
| `INX SP` / `DCX SP` emission rejected by the verifier (operand class mismatch) | `INX`/`DCX` accept `GR16AllPair` and `SP` is in `GR16All` — verified in [V6ClangRegisterInfo.td](../llvm/lib/Target/V6Clang/V6ClangRegisterInfo.td#L102) and [V6ClangInstrInfo.td](../llvm/lib/Target/V6Clang/V6ClangInstrInfo.td#L370). New lit test runs with `-verify-machineinstrs`. |
| `POP rp` without `Dead` flag → verifier fails (`-verify-machineinstrs`) | Always tag `RegState::Define \| RegState::Dead`. New lit test runs with `-verify-machineinstrs`. |
| Frame-pointer path silently still emits LXI for FP setup (not an SP adjustment but identical instruction) | Comment the FP setup explicitly; helper is invoked **only** for SP adjustments. |
| Existing test `frame-lowering.ll` `array_local` CHECK lines tied to LXI sequence break | Update the CHECK lines as part of Step 3.8 — this is an expected, one-time expectation update. |
| Regressions in goldens because PSW push reorders flags between calls | Adjustments are always at function boundaries (entry / RET); no intermediate flag-bearing instructions occur between the adjustment and either function entry or the RET itself. |
| Odd `StackSize` (e.g. 1, 5) silently picks PUSH path | Cost decision rejects odd sizes — falls through to LXI. Covered by `frame_oddsize_5` test. |
| `Mode == Size` decision differs from `Mode == Speed` for n=6 — could surprise reviewers | Documented in plan + lit test (`frame6_speed` vs `frame6_size`). |
| Empirical hit rate is low (0 in C benchmarks, 8 in lit tests, all ≤4) → risk of "dead optimization" | Plan implements the **infrastructure** (`chooseDeadPair`, `emitSPAdjustment`) that O54b/c/d depend on. Direct benefit is small but unblocks higher-impact siblings. |

---

## 6. Relationship to Other Improvements

* **O11 dual cost model**: This plan is the first frame-lowering
  consumer of `getV6ClangOptMode` + `V6ClangInstrCost`. It validates the
  pattern for downstream consumers.
* **O54b** (per-call frame cleanup): Depends on `chooseDeadPair` and
  `emitSPAdjustment` shipped here.
* **O54c** (stack-arg passing): Depends on the `PUSH rp` lowering
  shipped here for the symmetric caller side.
* **O54d** (constant-size alloca): Depends on the same helpers.
* **O10** (V6ClangAllocaPromote + V6ClangStaticStackAlloc): O10 eliminates
  most frames entirely. O54 only helps the residue (recursive,
  callback-taking, var-sized — empirically rare in this codebase).
  Coexistence is automatic: O54 runs in frame lowering only when a
  frame still exists.

## 7. Future Enhancements

* Generalise `chooseDeadPair` to scan a few instructions ahead/behind
  in the body of an MBB (enabling reuse of the helper inside O54b/c).
  Out of scope here — the current liveness check covers function
  boundaries.
* Add a `-v6clang-disable-pop-push-sp-adjust` cl::opt for A/B testing.
  Defer until a regression motivates it.
* Track total SP-adjustment savings via a `Statistic` counter, like
  other passes (e.g. `NumXchgFolded` in V6ClangXchgOpt).

## 8. References

* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
* [V6CLANG Instruction Timings](../docs/V6ClangInstructionTimings.md)
* [Vector 06c Instruction Timings](../docs/Vector_06c_instruction_timings.md)
* [O54 plan](future_plans/O54_optimal_stack_adjustment.md)
* [Future Improvements](future_plans/README.md)
* [Plan format reference](plan_cmp_based_comparison.md)
* `llvm/lib/Target/V6Clang/V6ClangFrameLowering.cpp` — emitter site
* `llvm/lib/Target/V6Clang/V6ClangInstrCost.h` — O11 cost model
* `llvm/test/CodeGen/V6Clang/frame-lowering.ll` — existing baseline
