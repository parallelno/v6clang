# Plan: V6CLANG_LOAD16_P Redesign — Honest Per-Shape Preservation

Source design: [O71 V6CLANG_LOAD16_P Redesign](future_plans/O71_V6CLANG_LOAD16_P_redesign.md)

## 1. Problem

### Current behavior

`V6CLANG_LOAD16_P` is the generic 16-bit load-through-pointer pseudo:

```tablegen
let mayLoad = 1 in
def V6CLANG_LOAD16_P : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$addr),
    "# LOAD16P $dst, ($addr)",
    [(set i16:$dst, (load i16:$addr))]>;
```

The pseudo declares **no `Defs`**, so RA and pre-RA passes treat the
instruction as preserving every register except `$dst`. The post-RA
expander in `V6ClangInstrInfo::expandPostRAPseudo()` is responsible for
honoring that contract. It does not — five concrete bugs are visible
today:

1. **`addr=HL, dst=HL`** silently corrupts `A`:
   `MOV A,M; INX H; MOV H,M; MOV L,A`. `A` is a temp, never saved.
2. **`addr=HL, dst∈{BC,DE}`** leaks `HL = orig + 1`:
   `MOV lo,M; INX H; MOV hi,M`. The `INX H` is never undone.
3. **`addr=DE, dst=DE`** computes wrong values in HL and DE:
   `XCHG; MOV E,M; INX H; MOV D,M; XCHG` ends with HL = loaded value
   (wrong) and DE = ptr+1 (wrong). Observed in
   `temp\asm_inline\custom_cc.s`.
4. **`addr=BC` with HL dead** skips PUSH/POP and leaks HL via
   `MOV H,B; MOV L,C; …; INX H`, so HL exits as `orig_BC + 1`.
   Benign while `HLDead` truly means dead, but the pseudo's declared
   `Defs` (none) still lies to any later pass.
5. **`addr=BC, dst=HL`** silently corrupts `A` for the same reason
   as bug 1.

### Desired behavior

After the redesigned expander runs:

- `A` is preserved across every shape (a dead GR8 is preferred as
  the temp; `PUSH PSW`/`POP PSW` is the fallback when no GR8 is
  dead and `A` is live).
- The address pair (`HL`, `BC`, or `DE`) is preserved across every
  shape when it is live across the pseudo, using the cheapest
  available recovery (`DCX rp` after `INX rp`, or `PUSH H`/`POP H`
  when HL was overwritten as part of the shape).
- `dst=HL` shapes correctly deliver the loaded value into HL via
  the trailing `XCHG` (case 3b) or the `MOV L,SpareR` pair (cases
  1, 6).
- The pseudo's pre-RA contract — "defines `$dst`, preserves
  everything else" — is honest.

### Root cause

The original expander conflated several distinct `(addr, dst)`
shapes onto two code paths (`emitLoad` and the BC PUSH/POP wrapper)
and treated the temporaries (`A`, the trailing `INX H`, the leading
`XCHG`) as locally invisible. The `(outs GR16:$dst)` declaration,
combined with no `Defs`, makes RA trust those locally-invisible
clobbers, and miscompiles follow. A single blanket `Defs = [HL, A,
FLAGS]` would close the holes but would force RA to spill `A`
across every pointer load even on shapes where `A` is genuinely
preserved (most of cases 2 and 3).

---

## 2. Strategy

### Approach: per-shape expansion with cheap-first preservation

Keep `V6CLANG_LOAD16_P` exactly as declared today (`(outs GR16:$dst),
(ins GR16:$addr)`, no `Defs`). Replace the body of `case
V6CLANG::V6CLANG_LOAD16_P:` in `V6ClangInstrInfo::expandPostRAPseudo()` with a
six-case dispatch on `(addr, dst)` register pairs. For each case,
compute post-RA liveness for the address pair, for `HL`, for `A`,
and for the GR8 set, then pick preservation in cheap-first order:

1. Use any dead GR8 as the low-byte temp (cases 1, 4, 6).
2. Emit `DCX rp` to undo `INX rp` when the address pair is live
   (cases 1, 2, 3a, 3b, 4).
3. Wrap `PUSH PSW` / `POP PSW` when no GR8 is dead and `A` is live
   (cases 1, 4, 6).
4. Wrap `PUSH H` / `POP H` when HL was overwritten and HL is live
   (cases 5, 6 — `addr=BC`).

### Why this works

- **Pressure-friendly.** RA still sees the pseudo as preserving
  every non-`$dst` register, so it does not insert spills around
  pointer loads.
- **Honest at expansion time.** All clobbers are visible to the
  expander because RA has committed; the expander emits exactly
  the recovery code each instance needs.
- **Cheaper than RA-visible `Defs`.** RA cannot emit `DCX rp`
  (operates at vreg granularity) and cannot pick a dead GR8 at
  expansion time. Both are key cost levers on this 3-element-GR16
  / 1-element-A ISA. See the design doc's pre-RA-vs-expander
  table.
- **Reuses existing liveness machinery.** `isRegDeadAtMI`
  (V6ClangInstrInfo.cpp:474) already handles forward scans plus
  successor live-ins, and is correct across loop back-edges. The
  only new helper is `findDeadGR8AtMI`.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Add helper | `findDeadGR8AtMI(MI, MBB, &RI)` returns a dead GR8 or `0` | V6ClangInstrInfo.cpp |
| Rewrite expander | Six-case dispatch with cheap-first preservation | V6ClangInstrInfo.cpp `case V6CLANG::V6CLANG_LOAD16_P:` |
| (No change) | `V6CLANG_LOAD16_P` td declaration unchanged | V6ClangInstrInfo.td |
| Test coverage | Lit test per case + runtime guard derived from `custom_cc.c` | tests/lit/, tests/features/53/ |
| Doc updates | Mark O71 done in `design/future_plans/README.md`, fill Implementation Notes | design/future_plans/ |

---

## 3. Implementation Steps

### Step 3.1 — Add `findDeadGR8AtMI` helper [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

Add a static helper near `isRegDeadAtMI` (line 474) that scans the
seven GR8 registers and returns the first one dead at the pseudo's
location, or `Register()` if none.

```cpp
// Return a GR8 register that is dead at MI, or Register() if none.
// Order matches GR8AllocationOrder so we prefer call-clobbered
// registers first, leaving callee-saved ones untouched. The
// preferred set excludes A (callers handle A specially via
// PUSH PSW/POP PSW). When ExcludeReg is non-zero, that register
// (and its sub-registers) is also excluded.
static Register findDeadGR8AtMI(const MachineInstr &MI,
                                const MachineBasicBlock &MBB,
                                const TargetRegisterInfo *TRI,
                                Register ExcludeReg = Register());
```

Iterate the GR8 register class (excluding `A`, excluding any
register that aliases `ExcludeReg`); return the first one that
`isRegDeadAtMI` reports as dead.

> **Design Notes**: `ExcludeReg` lets cases 1/4/6 exclude the
> address pair and the destination pair from the candidate set,
> avoiding accidental aliasing with HL/DE/BC sub-regs.

> **Implementation Notes**: Implemented as `findDeadGR8AtMI(MI, MBB,
> TRI, ExcludeReg1, ExcludeReg2)` — two excludes (cases 4 and 6 need
> both the address pair and the destination pair excluded). Iterates
> {B, C, D, E, H, L} (skips A; A is handled by the caller via PUSH
> PSW). Skips any candidate that overlaps either exclude. Returns
> `Register()` if none. Located just after `isRegDeadAtMI` in
> V6ClangInstrInfo.cpp.

### Step 3.2 — Rewrite expander: case 2 (`addr=HL, dst∈{BC,DE}`) [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`,
`case V6CLANG::V6CLANG_LOAD16_P:` (currently line ~1372).

Start with the simplest case to anchor the new structure:

```asm
    MOV  DstLo, M
    INX  H
    MOV  DstHi, M
    DCX  H               ; only if HL live after the pseudo
```

Branch on `AddrReg == V6CLANG::HL && (DstReg == V6CLANG::BC || DstReg == V6CLANG::DE)`.
Emit `DCX H` iff `!isRegDeadAtMI(V6CLANG::HL, MI, MBB, &RI)`.

> **Design Notes**: This fixes bug 2.

> **Implementation Notes**: Lambda closures `emitMOVrM(R)`,
> `emitINXHL()`, `emitDCX(rp)` factor the common shape. `DCX H` is
> emitted only when `!isRegDeadAtMI(V6CLANG::HL, MI, ...)` — saves 1 B /
> 5 cy when the pointer is dead, which is the common case.

### Step 3.3 — Case 1 (`addr=HL, dst=HL`) [x]

```asm
    MOV  Spare, M
    INX  H
    MOV  H, M
    MOV  L, Spare
```

`Spare = findDeadGR8AtMI(MI, MBB, &RI, /*ExcludeReg=*/V6Clang::HL)`.
If `Spare == 0`, set `Spare = V6CLANG::A` and wrap with
`PUSH PSW` / `POP PSW` iff `!isRegDeadAtMI(V6CLANG::A, MI, MBB, &RI)`.

No `DCX H` — the load itself overwrites HL, so no recovery is
needed (and no recovery is possible).

> **Design Notes**: Fixes bug 1. Note `dst=HL` ⇒ HL is *not* live
> across the pseudo as the original value; only the loaded value
> matters.

> **Implementation Notes**: PUSH PSW / POP PSW fallback only when
> *no* GR8 spare is dead AND `A` is live across the pseudo. In all
> O22 / O23 / `temp/asm_inline/custom_cc.c` runs observed so far the
> dead-GR8 spare path is taken (typically B or C); the PUSH PSW path
> exists only as a worst-case safety net.

### Step 3.4 — Cases 3a (`addr=DE, dst=BC`) and 3b (`addr=DE, dst=HL`) [x]

Case 3a:
```asm
    XCHG
    MOV  C, M
    INX  H
    MOV  B, M
    XCHG
    DCX  D            ; only if DE live after the pseudo
```

Case 3b:
```asm
    XCHG
    MOV  E, M
    INX  H
    MOV  D, M
    XCHG              ; mandatory — delivers loaded value to HL
    DCX  D            ; only if DE live after the pseudo
```

`DCX D` is emitted iff `!isRegDeadAtMI(V6CLANG::DE, MI, MBB, &RI)`.
The trailing `XCHG` is always emitted (it is the delivery for 3b
and the DE-restore for 3a).

> **Design Notes**: Case 3b never needs `A` and never clobbers HL
> (the original HL value lands in DE during the load and is
> restored by the trailing XCHG, modulo +1 which `DCX D` corrects
> via the swapped role).

> **Implementation Notes**: My first pass collapsed cases 3a and 3b
> into a single shared body that staged the load through
> `DstLo`/`DstHi`. That happens to work for 3a (`dst=BC` does not
> overlap HL) but is wrong for 3b: after the leading `XCHG`, HL
> holds the address, so writing into `DstLo=L` and `DstHi=H` would
> clobber the address mid-sequence. The design doc was correct from
> the start (it explicitly says `MOV E, M; INX H; MOV D, M`); my
> implementation drifted from the spec, the test caught it, fixed
> by branching on `DstReg == V6CLANG::HL` and forcing `LoadLo=E`,
> `LoadHi=D` for that branch. Case 3a still uses `DstLo=C, DstHi=B`
> directly. The trailing `XCHG` is sometimes eliminated by
> `foldXchgDad` when the next op is `DAD D` and DE is dead.

### Step 3.5 — Case 4 (`addr=DE, dst=DE`) [x]

```asm
    XCHG
    MOV  Spare, M
    INX  H
    MOV  H, M
    MOV  L, Spare
    XCHG
```

`Spare = findDeadGR8AtMI(MI, MBB, &RI, V6CLANG::HL, V6CLANG::DE)`. If
`Spare == 0`, set `Spare = V6CLANG::A` and wrap with `PUSH PSW` /
`POP PSW` iff `!isRegDeadAtMI(V6CLANG::A, MI, MBB, &RI)`.

No `DCX D` is ever needed: `dst=DE` means the destination of the
load is DE, so the caller cannot also expect DE to still hold the
old address afterwards.

> **Design Notes**: Fixes bug 3. The spare-selection rule is
> per-byte, not per-pair. After the leading `XCHG`, `HL` holds the
> address, so `H` and `L` are off-limits unconditionally (the load
> body would clobber the address). The trailing `XCHG` swaps DE↔HL
> again — whatever value sits in `D` (resp. `E`) at that moment
> ends up in `H` (resp. `L`) post-load. Since `D` physically holds
> `H_orig` after `XCHG #1` and `E` holds `L_orig`, the rule is:
>
>   * `B` is a candidate iff `B` is dead across the pseudo.
>   * `C` is a candidate iff `C` is dead across the pseudo.
>   * `D` is a candidate iff **`H`** is dead across the pseudo.
>   * `E` is a candidate iff **`L`** is dead across the pseudo.
>   * `H`, `L` are never candidates.
>
> A blanket `Exclude=DE` would be safe but over-conservative:
> when `HL` is fully dead, `D` and `E` become valid spares and we
> avoid the `PUSH PSW` fallback. The original design doc's
> "optional `DCX D` if DE live" line is incorrect for this shape
> and is dropped — `dst=DE` means DE is being redefined, so the
> address pair is by construction not preserved.

> **Implementation Notes**: First implementation used
> `findDeadGR8AtMI(..., V6CLANG::HL, V6CLANG::DE)`, which excludes the
> entire DE pair. Per the per-byte rule above, that
> over-conservatively forces the `PUSH PSW` fallback whenever B
> and C are both live, even though `D` (or `E`) might be safe.
> Replaced with an inline `findCase4Spare` lambda that probes
> {B, C} via `isRegDeadAtMI(R)` and {D, E} via
> `isRegDeadAtMI(H)` / `isRegDeadAtMI(L)`. The bug-3 reproducer
> (`tests/features/53/bug3_de_de`, where HL holds `sum` and is
> live) still picks `B` as before, so `v6clang_new01.asm` is
> byte-identical; the refinement only activates when HL is
> partly or fully dead.

### Step 3.6 — Cases 5 (`addr=BC, dst∈{BC,DE}`) and 6 (`addr=BC, dst=HL`) [x]

Case 5:
```asm
    PUSH H            ; only if HL live after the pseudo
    MOV  H, B
    MOV  L, C
    MOV  DstLo, M
    INX  H
    MOV  DstHi, M
    POP  H            ; matches the PUSH
```

Case 6:
```asm
    MOV  H, B
    MOV  L, C
    MOV  Spare, M
    INX  H
    MOV  H, M
    MOV  L, Spare
```
(wrapped with `PUSH PSW`/`POP PSW` iff no spare GR8 and `A` live).

For case 5: emit `PUSH H`/`POP H` iff
`!isRegDeadAtMI(V6CLANG::HL, MI, MBB, &RI)`. No `DCX BC` is needed —
BC is never modified (we only copy `B→H`, `C→L`).

For case 6: `dst=HL` means the caller's HL is the destination of
the load, so the original HL value is dead by definition — never
emit `PUSH H`/`POP H`. `Spare = findDeadGR8AtMI(MI, MBB, &RI,
V6CLANG::HL, V6CLANG::BC)` (must exclude both BC, since BC holds the
address, and HL, since HL is being filled with the load result).
If `Spare == 0`, set `Spare = V6CLANG::A` and wrap `PUSH PSW`/`POP PSW`
iff `A` is live.

> **Design Notes**: Fixes bugs 4 and 5. Earlier drafts assumed
> case 6 also needed `PUSH H`/`POP H` to "preserve HL," requiring a
> two-spare staging trick or `XTHL`. That was wrong: `dst=HL`
> defines HL, so original HL is not live across the pseudo. The
> simple six-instruction body (no PUSH/POP HL, single spare) is
> always sufficient.

> **Implementation Notes**: Case 6 spare excludes both HL (dst) and
> BC (addr); fallback is PUSH PSW / POP PSW. No PUSH/POP HL is ever
> emitted in this shape — the design doc's claim was wrong.

### Step 3.7 — Build [x]

Run from repo root:

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

Fix any compile errors, then proceed.

> **Implementation Notes**: One ambiguity error (`Register` →
> `MCRegister` conversion) was resolved by calling `.asMCReg()` on
> the candidate registers. No other diagnostics. Build succeeds.

### Step 3.8 — Lit test: load16p-shapes (case 1 + case 4) [x]

**File**: `llvm-project/llvm/test/CodeGen/V6Clang/load16p-shapes.ll`

Consolidated into a single lit file pinning the two highest-value
shapes:

  * `case1_hl_hl` — addr=HL, dst=HL — verifies dead-GR8 spare path
    (`MOV B, M; INX H; MOV H, M; MOV L, B`) and absence of `PUSH`.
  * `case4_de_de` — addr=DE, dst=DE — bug-3 regression. Asserts
    `XCHG; MOV [BC], M; INX H; MOV H, M; MOV L, [BC]` and absence
    of the old `MOV E, M; INX H; MOV D, M` shape. The trailing
    `XCHG` is intentionally not asserted because `foldXchgDad`
    optimizes it away in this context.

Cases 2, 3, 5, 6 are exercised end-to-end by
`tests/features/53/v6clang.c` (and indirectly across the rest of the
lit / golden suite — 128 lit tests + 16 golden tests pass). The
V6CLANG calling convention places the first 16-bit arg in HL and the
second in DE, so granular shape pinning via plain C IR is awkward
for cases 5/6 (addr=BC); those shapes are validated through the
golden runner instead of FileCheck.

> **Implementation Notes**: Two pre-existing tests had their CHECK
> updated for the new pattern: `load-store-i16.ll` (load_ptr) and
> `pointer-arith.ll` (gep_i16) — both now use
> `MOV [[T:[A-Z]+]], M ... MOV L, [[T]]` placeholders to accept any
> dead-GR8 spare instead of pinning `MOV A, M`.

### Step 3.13 — Run regression tests [x]

```
python tests\run_all.py
```

Diagnose and fix any regression. Re-run until clean.

> **Implementation Notes**: 128/128 lit tests pass, 16/16 golden
> tests pass after the mirror sync.

### Step 3.14 — Verification assembly steps from `tests\features\README.md` [x]

Compile `tests\features\53\v6clang.c` to `v6clang_new01.asm` and
analyze:

- Case 2: `DCX H` appears when HL pointer is reused after the load.
- Case 1/4/6: temp is a dead GR8 when one is available; otherwise
  `PUSH PSW`/`POP PSW` wraps the load.
- Case 3 (DE): trailing `XCHG` is always present; `DCX D` only when
  DE is reused.
- Case 4: bug-3 regression — check the assembly matches the
  expected pattern.
- Cases 5/6: `PUSH H`/`POP H` when HL live; case 6 single-spare
  uses `XTHL`.

Iterate to `v6clang_new02.asm`, `v6clang_new03.asm`, … until the
expected improvements are present.

> **Implementation Notes**: `v6clang_new01.asm` matches
> `v6clang.asm` byte-for-byte. `bug3_de_de` now produces `XCHG; MOV
> B, M; INX H; MOV H, M; MOV L, B; DAD D; RET` (correct, +1 byte
> over the buggy old shape). `case2_hl_reused` and
> `case5_bc_with_hl_live` use `MOV B, M ... MOV L, B` (A preserved,
> same size as the old `MOV A, M ... MOV L, A`). `case16_a_live`
> unchanged at `INX H; XRA M; RET`.

### Step 3.15 — Make sure `result.txt` is created (`tests\features\README.md`) [x]

Document c8080 vs v6clang cycles/bytes per function and the
shape-by-shape matrix.

> **Implementation Notes**: `tests/features/53/result.txt` written.
> Includes c8080 reference, baseline old asm (with the bug 3
> demonstration), the new asm, and per-function instruction-count /
> approx-cycle stats.

### Step 3.16 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Mirror synced; `tests\lit` reflects the
> updated `load-store-i16.ll`, `pointer-arith.ll`, and
> `load16p-shapes.ll`.

### Step 3.17 — Mark O71 complete in `design/future_plans/README.md` [x]

Add the **DONE** marker on the O71 row, set the implementation
order checkbox.

> **Implementation Notes**: O71 row marked **DONE** in
> `design/future_plans/README.md`.

---

## 4. Expected Results

### Example 1 — `custom_cc.c` (bug 3 regression)

**Before** (broken):
```asm
DAD     B            ; HL = sum
XCHG
MOV     E, M
INX     H
MOV     D, M
XCHG                 ; HL = loaded (wrong), DE = ptr+1 (wrong)
DAD     D            ; HL = loaded + (ptr + 1)   -- WRONG
```

**After** (case 4, DE dead):
```asm
DAD     B            ; HL = sum
XCHG
MOV     <Spare>, M
INX     H
MOV     H, M
MOV     L, <Spare>
XCHG                 ; DE = loaded value, HL = sum
DAD     D            ; HL = sum + loaded   -- correct
```

### Example 2 — pointer-reuse loop, `addr=HL, dst=BC`

**Before** (case 2, leaks HL):
```asm
MOV  C, M
INX  H
MOV  B, M
; HL = orig + 1, but RA thinks HL is unchanged
LXI  H, ptr          ; reload required → +3B/+10cc/iter
```

**After**:
```asm
MOV  C, M
INX  H
MOV  B, M
DCX  H               ; +1B / +5cc, HL = ptr restored
; loop reuses HL directly → −3B/−10cc/iter on the next load
```

Net per iteration: **−2B / −5cc** in the typical sequential-load
loop, plus **+correctness**.

### Example 3 — `A` live across `addr=HL, dst=HL`

**Before**: silent corruption.
**After**: dead-GR8 spare (zero overhead) when one is available;
otherwise `PUSH PSW`/`POP PSW` (+2B / +23cc) — but at least
correct.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Missed live-reg case in the dispatch leaves a clobber unrecovered | Per-case lit tests with both live-after and dead-after variants; runtime guard derived from `custom_cc.c`. |
| `findDeadGR8AtMI` returns a register that aliases the address or destination pair | Helper takes an `ExcludeReg` argument; expander passes the address+destination pairs. |
| Case 6 single-spare `XTHL` path has subtle stack interaction with surrounding code | Lit test exercises the path; runtime guard runs the expansion under the emulator with `--halt-exit`. |
| Increased expander size (~150 LOC) raises maintenance cost | Single switch on `(addr, dst)` shape with shared helpers (`emitDCXIfLive`, `wrapPushHIfLive`, `wrapPushPSWIfLive`); each shape body is 5–10 lines. |
| Regression on hot paths that previously got "lucky" with the old expander | `python tests\run_all.py` covers golden + lit; `tests\features\53` exercises every shape. |

---

## 6. Relationship to Other Improvements

- **O20 (Honest Store/Load Pseudo Defs)** — same structural problem
  but at the td-declaration level. O71 takes the orthogonal
  expander-side approach for `LOAD16_P` because RA-visible Defs
  cost more than expander-time recovery on this ISA. O72 (planned)
  applies the same template to `V6CLANG_STORE16_P`.
- **O42 (Liveness-Aware Pseudo Expansion)** — provides
  `isRegDeadAtMI`, the foundation for O71's preservation
  decisions.
- **O44 (Adjacent XCHG Cancellation)** — cancels the trailing
  `XCHG` of a case-3/case-4 load against the leading `XCHG` of an
  adjacent `addr=DE` load, so the nominal +4cc XCHG overhead is
  paid only at chain boundaries.


---

## 6. Phase 4 — `addr=BC` LDAX-Based Refinement [x]

The original O71 expander always used the `MOV H,B; MOV L,C; MOV r,M;
INX H; ...` template for `addr=BC` (cases 5 and 6). That shape is
free of A traffic but always pays at least 5B/40cc and adds a
PUSH/POP HL pair (+28cc, +2B) when HL is live across the load.
For most `addr=BC` shapes the V6CLANG `LDAX rp` instruction (8cc) makes
a strictly cheaper template available — at the cost of clobbering
A and incrementing BC. Phase 4 adds a per-shape decision tree that
picks whichever template is cheapest for the live-set at the load.

### Step 4.1 — Replace case 6 (`addr=BC, dst=HL`) with two-shape dispatch [x]

```
Shape A (M-staging) — used iff A is live AND a non-{HL,BC} GR8 spare
                      is dead:
    MOV H,B; MOV L,C; MOV S,M; INX H; MOV H,M; MOV L,S
    6B / 48cc, no A traffic, BC preserved.

Shape B (LDAX) — otherwise:
    [PUSH PSW] LDAX B; MOV L,A; INX B; LDAX B; MOV H,A [POP PSW]
    [DCX B if BC live]
    A dead:                  5B / 40cc (+1B/8cc if BC live)
    A live, no spare:        7B / 68cc (+1B/8cc if BC live)
```

> **Implementation Notes**: When A is live and a spare is available,
> shape A wins on both bytes and cycles (6B/48cc) over a wrapped
> shape B (`MOV S,A; LDAX B; ...; MOV A,S` = 7B/56cc + DCX). When A
> is dead, shape B is unconditionally cheaper; when A is live and no
> spare exists, shape B with `PUSH PSW`/`POP PSW` (7B/68cc) beats
> the previous A-using shape A (8B/76cc).

### Step 4.2 — Split case 5 into `dst=DE` (5a) and `dst=BC` (5b) [x]

The two halves have very different constraints:

* `dst=DE` keeps the LDAX-shape template option, gated on HL liveness.
* `dst=BC` cannot use the naive LDAX template — `MOV C,A` mid-sequence
  would corrupt the address pair before the second `LDAX`. A
  three-tier dispatch covers it cleanly without any DCX BC (BC is
  the destination).

### Step 4.3 — Implement case 5a (`addr=BC, dst=DE`) four-way dispatch [x]

```
1. HL dead — current shape (5B / 40cc, BC preserved):
     MOV H,B; MOV L,C; MOV E,M; INX H; MOV D,M

2. HL live, A dead — LDAX (5B / 40cc, +1B/8cc if BC live):
     LDAX B; MOV E,A; INX B; LDAX B; MOV D,A; (DCX B if BC live)

3. HL live, A live, spare in {H,L} dead — LDAX with cheap MOV-wrap
   A-preservation (7B / 56cc, +1B/8cc if BC live):
     MOV S,A; LDAX B; MOV E,A; INX B; LDAX B; MOV D,A; MOV A,S
     (DCX B if BC live)

4. Otherwise — PUSH H wraps the current shape (7B / 68cc, BC
   preserved):
     PUSH H; MOV H,B; MOV L,C; MOV E,M; INX H; MOV D,M; POP H
```

> **Implementation Notes**: Shape 3's spare must avoid {A,B,C,D,E}
> so it can only come from {H,L}. We're already in the HL-live
> branch, so use a per-byte rule (case 4 style): H is candidate iff
> H is dead at MI; L is candidate iff L is dead at MI. If neither
> half is dead we fall through to shape 4.

### Step 4.4 — Implement case 5b (`addr=BC, dst=BC`) three-tier dispatch [x]

```
Tier 1 — HL fully dead (5B / 40cc):
     MOV H,B; MOV L,C; MOV C,M; INX H; MOV B,M

Tier 2 — A dead AND a non-{B,C} GR8 spare is dead (6B / 48cc).
         The spare buffers the low byte across INX B so we never
         write into the address pair before the second LDAX:
     LDAX B; MOV S,A; INX B; LDAX B; MOV B,A; MOV C,S

Tier 3 — fallback (7B / 68cc):
     PUSH H; tier-1; POP H
```

No DCX BC in any tier — BC is the destination of the load and is
intentionally redefined.

> **Implementation Notes**: A naive `LDAX B; MOV C,A; INX B; ...`
> sequence would be incorrect — overwriting C between the two LDAXs
> would corrupt the address pair. Tier 2 staging via a non-BC GR8
> spare (S ∈ {D,E,H,L} dead at MI) is the cheapest correct LDAX
> shape. Note that we don't need to wrap with PUSH PSW for tier 2
> because the tier requires A dead.

### Step 4.5 — Lit test coverage [x]

Added two tests to `llvm-project/llvm/test/CodeGen/V6Clang/load16p-shapes.ll`:

* `case6_bc_hl_simple` — 3-arg function (`ptr` in BC by ABI),
  returns the loaded value (dst=HL, A dead, BC dead). Pins the
  new shape B sequence: `LDAX B; MOV L,A; INX B; LDAX B; MOV H,A`.
* `case5a_bc_de` — 3-arg function with HL live across the load
  (HL holds `%x`, used by a tail call sink). Pins the case-5a
  shape-2 sequence: `LDAX B; MOV E,A; INX B; LDAX B; MOV D,A`.

Both are naturally generated — no inline asm or ABI tricks needed.

### Step 4.6 — Build, regress, sync [x]

* Build: `ninja -C llvm-build clang llc` — clean.
* Regression: `python tests\run_all.py` — 130 lit + 16 golden pass.
* Mirror sync: `powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1`.

> **Implementation Notes**: No existing tests changed asm output —
> the old `addr=HL` and `addr=DE` paths are untouched, and the
> existing asm corpus didn't naturally hit `addr=BC` (the V6CLANG ABI
> places i16/ptr args 1 and 2 in HL and DE; only the rare
> 3rd-arg-pointer pattern, or LSR-derived addr=BC patterns, exercise
> cases 5/6).


---

## 7. Future Enhancements

- **O72 — `V6CLANG_STORE16_P` redesign** along the same template.
  Same five-shape problem; same dead-GR8/`DCX rp`/PUSH PSW/PUSH H
  toolkit.
- **`V6CLANG_LOAD16_G` / `V6CLANG_STORE16_G` global-address variants** —
  same shape-conflation pattern, follow-up.
- **Two-load chain cancellation peephole** — when two `addr=DE`
  loads abut, the trailing `XCHG` of the first cancels the leading
  `XCHG` of the second (covered by O44, but explicitly track the
  `LOAD16_P` use case).
- **INX/DCX Cancelation Peephole** — `DCX rp` after
  `INX rp` or vice versa pair elimitation peephole.
- **POP RP/PUSH RP Cancelation Peephole**.

---

## 8. References

* [O71 design doc](future_plans/O71_V6CLANG_LOAD16_P_redesign.md)
* [Plan format reference](plan_cmp_based_comparison.md)
* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md)
* [Future Improvements](future_plans/README.md)
* [Feature Test Cases](../tests/features/README.md)
* [Pipeline](pipeline_feature.md)
* [v6emul CLI](../tools/v6emul/docs/cli.md)
* [v6asm CLI](../tools/v6asm/docs/cli.md)
