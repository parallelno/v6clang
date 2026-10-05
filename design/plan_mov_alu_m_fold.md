# Plan: MOV r, M + ALU r Fold (O65)

## 1. Problem

### Current behavior

After register allocation, codegen routinely leaves sequences such as:

```asm
LXI   HL, __v6clang_ss.many_i8+3
MOV   L, M        ; 7cc, 1B — load [HL] into scratch L
XRA   L           ; 4cc, 1B — A ^= L, L dead after
```

The 8080 has direct memory-operand ALU instructions
(`ADD M`, `ADC M`, `SUB M`, `SBB M`, `ANA M`, `XRA M`, `ORA M`, `CMP M`)
that read the operand straight from `[HL]`. They already exist in
[V6ClangInstrInfo.td](../llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td#L293) (lines
294–303) as `ADDM/ADCM/SUBM/SBBM/ANAM/XRAM/ORAM/CMPM` with empty ISel
pattern lists. They are never selected today — every `[HL]`-operand ALU
is materialized through a scratch register.

### Desired behavior

```asm
LXI   HL, __v6clang_ss.many_i8+3
XRA   M           ; 7cc, 1B — A ^= [HL] directly
```

Savings per fold: **4cc, 1B**.

Reference: `tests/features/38/v6clang_new01.asm` function `many_i8`
contains four consecutive `MOV L, M; XRA L` pairs — **16cc, 4B** saved
in that function body alone:

```asm
LDA   __v6clang_ss.many_i8+1
LXI   HL, __v6clang_ss.many_i8
MOV   L, M
XRA   L
LXI   HL, __v6clang_ss.many_i8+2
MOV   L, M
XRA   L
LXI   HL, __v6clang_ss.many_i8+3
MOV   L, M
XRA   L
LXI   HL, __v6clang_ss.many_i8+4
MOV   L, M
XRA   L
```

### Root cause

O49 (direct memory ALU ISel) would catch this at DAG level via pseudos
but is not implemented. Even with O49 in place, some folds leak through
to post-RA because the load materializes early and only later gets
paired with an ALU op, or is emitted by a lowering pass that bypasses
ISel entirely.

---

## 2. Strategy

### Approach: post-RA peephole in `V6ClangPeephole.cpp`, three stages

Add a new pattern method `foldMovAluM()` to the existing
[V6ClangPeephole.cpp](../llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp#L1). Single
linear scan per MBB, implemented in three progressively more powerful
stages:

**Stage 1 — strict adjacency** (`MOV r, M; OP r` → `OP M`):

```
MOV  r, M          (V6CLANG::MOVrM,  dst=r, implicit use HL)
OP   r             (V6CLANG::{ADD|ADC|SUB|SBB|ANA|XRA|ORA|CMP}r, rhs=r)
```

that collapses to:

```
OP   M             (V6CLANG::{ADD|ADC|SUB|SBB|ANA|XRA|ORA|CMP}M, implicit use HL)
```

**Stage 2 — non-adjacent fold** (same head and tail, arbitrary
independent MIs in between):

```
MOV  r, M
… independent MIs that touch neither r, HL, A, FLAGS, nor memory …
OP   r
```

same collapse. Enabled by a `scanBetweenSafe()` helper that walks every
MI between the head and tail and rejects the fold if any MI reads/writes
`r`, reads/writes HL (or `H`/`L`), reads/writes `A` or `FLAGS`, is a
control-flow instruction, or has `mayStore`.

**Stage 3 — `INR M` / `DCR M` / `MVI M, imm8` triad**:

```
MOV  A, M          →   INR  M       (also DCR M)
INR/DCR A
MOV  M, A

MVI  A, imm        →   MVI  M, imm
MOV  M, A
```

Gated by the same `scanBetweenSafe()` walk plus `A` dead after `MOV M, A`.

### Why this works

- The two MIs are strictly adjacent → nothing between them can read `r`
  or redefine HL.
- `r` is dead after the OP → removing the MOV is safe; no downstream
  user of `r` can observe the missing value.
- For `r ∈ {H, L}` this is still safe because the fold also deletes the
  ALU op that consumed `r`; we never evaluate `OP M` while HL holds the
  pre-load value.
- `MOVrM` does not touch FLAGS → no flag state to preserve between the
  MOV and OP.
- Excluding `r = A` is mandatory: `MOV A, M; ADD A` would double the
  loaded value, not equal `ADD M`. (For the XRA specific case `r = A`
  would zero A unconditionally, also different semantics.)
- The memory-form instructions produce the same A / FLAGS result the
  original OP produced, so downstream consumers of A and FLAGS see no
  change.

### Summary of changes

| File | Change |
|------|--------|
| llvm-project/llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp | Add `foldMovAluM()` (stages 1–2) + `foldIncDecMviM()` (stage 3) methods, `scanBetweenSafe()` helper, opcode maps, call in `runOnMachineFunction` |
| llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp | Mirror (via `sync_llvm_mirror.ps1`) |
| tests/lit/CodeGen/V6CLANG/mov-alu-m-fold.ll | Lit test covering all eight ALU kinds + negative cases + non-adjacent cases |
| tests/lit/CodeGen/V6CLANG/inc-dec-mvi-m-fold.ll | Lit test covering `INR M` / `DCR M` / `MVI M, imm8` folds + negative cases |
| tests/features/42/ | New feature test folder (XRA M + INR M + MVI M reproduction) |

No TableGen changes are required — the target `ADDM/…/CMPM` instructions
already exist.

---

## 3. Implementation Steps

### Step 3.1 — Stage 1: add `foldMovAluM()` (strict adjacency) [ ]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp`

Add a private method `foldMovAluM(MachineBasicBlock &MBB)` and a small
opcode-mapping helper. Reuse the existing
[`isRegDeadAfter()`](../llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp#L186) helper
already in the file.

```cpp
/// Map a register-form ALU opcode to its memory-form counterpart.
/// Returns 0 if MI is not a foldable ALU-r instruction.
static unsigned aluRegToMemOpcode(unsigned Opc) {
  switch (Opc) {
  case V6CLANG::ADDr: return V6CLANG::ADDM;
  case V6CLANG::ADCr: return V6CLANG::ADCM;
  case V6CLANG::SUBr: return V6CLANG::SUBM;
  case V6CLANG::SBBr: return V6CLANG::SBBM;
  case V6CLANG::ANAr: return V6CLANG::ANAM;
  case V6CLANG::XRAr: return V6CLANG::XRAM;
  case V6CLANG::ORAr: return V6CLANG::ORAM;
  case V6CLANG::CMPr: return V6CLANG::CMPM;
  default:        return 0;
  }
}

/// Fold MOV r, M; OP r → OP M when r is dead after OP (O65).
///
/// Pattern:
///   MOV  r, M        ; V6CLANG::MOVrM, defs r, implicit use HL
///   OP   r           ; V6CLANG::{ADD|ADC|…|CMP}r, uses A + r
/// into:
///   OP   M           ; V6CLANG::{ADD|ADC|…|CMP}M, uses A, implicit use HL
///
/// Safety conditions:
///   - MOVrM and the ALU op are strictly adjacent (skipping only debug MIs).
///   - The MOV's dst register == the ALU's rhs register.
///   - r != A (MOV A, M; ADD A doubles A, not equal to ADD M).
///   - r is dead after the ALU op (checked via isRegDeadAfter).
///   - HL is unchanged between MOV and OP (guaranteed by adjacency —
///     MOVrM only defs r, register-form ALU only defs A + FLAGS).
bool V6ClangPeephole::foldMovAluM(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();
  const TargetInstrInfo &TII = *MBB.getParent()->getSubtarget().getInstrInfo();

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ) {
    if (I->getOpcode() != V6CLANG::MOVrM) { ++I; continue; }

    // Find next non-debug instruction.
    auto J = std::next(I);
    while (J != E && J->isDebugInstr()) ++J;
    if (J == E) { ++I; continue; }

    unsigned MemOpc = aluRegToMemOpcode(J->getOpcode());
    if (MemOpc == 0) { ++I; continue; }

    Register MovDst  = I->getOperand(0).getReg();                 // r
    // OPr operand layout: (outs Acc:$dst) (ins Acc:$lhs, GR8:$rs)
    // CMPr operand layout: (outs)       (ins Acc:$lhs, GR8:$rs)
    bool IsCMP = (J->getOpcode() == V6CLANG::CMPr);
    unsigned RhsIdx = IsCMP ? 1 : 2;
    Register AluRhs  = J->getOperand(RhsIdx).getReg();

    if (MovDst != AluRhs || MovDst == V6CLANG::A) { ++I; continue; }

    if (!isRegDeadAfter(MBB, J, MovDst, TRI)) { ++I; continue; }

    // Build OP M. For non-CMP:   outs Acc:$dst; ins Acc:$lhs (tied).
    //              For CMP:      outs;          ins Acc:$lhs.
    MachineInstrBuilder MIB = BuildMI(MBB, *J, J->getDebugLoc(),
                                      TII.get(MemOpc));
    if (!IsCMP)
      MIB.addReg(V6CLANG::A, RegState::Define);   // $dst
    MIB.addReg(V6CLANG::A);                        // $lhs

    // Erase original MOV and OPr.
    auto Next = std::next(J);
    J->eraseFromParent();
    I->eraseFromParent();
    I = Next;
    Changed = true;
  }
  return Changed;
}
```

Wire the method into `runOnMachineFunction`, placed **before**
`eliminateSelfMov` / `eliminateRedundantMov` so the fold happens while
operand adjacency is still intact, and before `foldXraCmpZeroTest` so
that the folded `XRA M` / `CMP M` is still visible to later patterns.

Also add `foldMovAluM` to the private-method declarations in the class
body.

> **Design Notes**: The memory-form ALU instructions are declared with
> `Defs = [FLAGS], Uses = [HL], mayLoad = 1` ([V6ClangInstrInfo.td](../llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td#L291)),
> so the MachineInstr receives the correct implicit operands automatically
> through `TII.get(MemOpc)`. No manual `implicit use HL` / `implicit def FLAGS` needed.
>
> Kill flags on HL: the existing MOVrM implicit-use of HL carries the
> original kill; `ADDM/…/CMPM`'s implicit-use HL is the same register,
> so after the MOV is erased no stale kill survives. We rely on the
> post-RA regalloc-free environment — no LiveIntervals update required.
>
> **Implementation Notes**: _(empty, filled after completion)_

### Step 3.2 — Stage 1: Build & smoke test [ ]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

Recompile `tests/features/42/v6clang.c` → `v6clang_new01.asm` and
confirm the four `MOV L, M; XRA L` folds have become `XRA M`. This is
the quick-verification gate before building stages 2 and 3.

> **Implementation Notes**: _(empty)_

### Step 3.3 — Stage 1 lit test: mov-alu-m-fold.ll [ ]

**File**: `tests/lit/CodeGen/V6CLANG/mov-alu-m-fold.ll`

Minimal IR with:
1. Eight positive cases (one per ALU kind) loading a global byte, OPing
   with A, producing A or a flag-dependent branch, where the temp reg
   is dead after the ALU.
2. Negative case: temp reg used again after the ALU → no fold.
3. Negative case: the ALU uses `A` as RHS → no fold.
4. Toggle run with `-v6clang-disable-peephole` → the MOV + OPr pair survives.

`CHECK` lines use `XRA\tM` / `ADD\tM` / `CMP\tM` syntax and `CHECK-NOT:
MOV\t[BCDEHL], M` to lock down the fold.

> **Design Notes**: `CMPr` is special — no tied output def. The test
> checks that the branch condition still matches post-fold.
>
> **Implementation Notes**: _(empty)_

### Step 3.4 — Stage 2: non-adjacent fold + `scanBetweenSafe()` helper [ ]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp`

Extend `foldMovAluM()` to look forward beyond the immediate successor of
`MOVrM`, using a new helper:

```cpp
/// Walk MIs in [Begin, End). Return true if every MI is safe to cross
/// while carrying a value of register `R` intact AND preserving the
/// A / FLAGS / HL observer chain. Debug MIs always skipped.
///
/// Specifically, every MI K in the range must:
///   * not read or write R (or any aliasing reg),
///   * not read or write any register overlapping HL (H, L, HL, super),
///   * not read or write A or FLAGS,
///   * not be a call, branch, return, or barrier (including any MI that
///     modifies SP, which conservatively covers CALLSEQ markers),
///   * not be mayStore (a store could alias [HL]).
static bool scanBetweenSafe(MachineBasicBlock::iterator Begin,
                            MachineBasicBlock::iterator End,
                            Register R,
                            const TargetRegisterInfo *TRI);
```

The main loop finds the next `OPr` with `rhs == r` via a forward walk,
stopping on the first unsafe MI. All stage-1 safety conditions (`r != A`,
`r` dead after OP) still apply.

> **Design Notes**: To avoid quadratic behavior in large BBs, cap the
> scan window (e.g. 16 MIs) — the fold is almost always worthless beyond
> that because register pressure would force new uses of `r`.
>
> **Implementation Notes**: _(empty)_

### Step 3.5 — Stage 2: Build & extend lit test [ ]

Rebuild and extend `mov-alu-m-fold.ll` with:
1. Positive: `MOV L, M; INX DE; XRA L` (intervening MI touches neither
   `L`, `HL`, `A`, nor memory) → folds to `INX DE; XRA M`.
2. Positive: `MOV B, M; MOV C, D; ORA B` → folds to `MOV C, D; ORA M`.
3. Negative: intervening `STA <sym>` → no fold (mayStore).
4. Negative: intervening `DAD DE` → no fold (writes HL).
5. Negative: intervening `CPI 0` → no fold (writes FLAGS).
6. Negative: intervening `MOV A, B` → no fold (writes A).

> **Implementation Notes**: _(empty)_

### Step 3.6 — Stage 3: add `foldIncDecMviM()` [ ]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp`

New private method recognizing two shapes:

**Shape A** (`INR M` / `DCR M`):
```
MOV  A, M       ; V6CLANG::MOVrM, dst=A
INR/DCR A       ; V6CLANG::INRr/DCRr, op0=A
MOV  M, A       ; V6CLANG::MOVMr, src=A
```
→ `INR M` / `DCR M`.

**Shape B** (`MVI M, imm`):
```
MVI  A, imm     ; V6CLANG::MVIr, dst=A
MOV  M, A       ; V6CLANG::MOVMr, src=A
```
→ `MVI M, imm`.

Both shapes require:
- the three/two MIs bookend the window (intervening MIs permitted as
  long as they pass `scanBetweenSafe` with `R = A` and the
  `allowAWrite=false` guard); and
- `A` dead after `MOV M, A`.

Opcode map:
```cpp
static unsigned incDecRegToMemOpcode(unsigned Opc) {
  switch (Opc) {
  case V6CLANG::INRr: return V6CLANG::INRM;
  case V6CLANG::DCRr: return V6CLANG::DCRM;
  default:        return 0;
  }
}
```

> **Design Notes**: `MVIM` takes an immediate operand \u2014 the builder
> must forward the `imm8` from the original `MVIr` MI. Kill flags on
> HL follow the same rule as stages 1 & 2.
>
> **Implementation Notes**: _(empty)_

### Step 3.7 — Stage 3: Build & lit test inc-dec-mvi-m-fold.ll [ ]

**File**: `tests/lit/CodeGen/V6CLANG/inc-dec-mvi-m-fold.ll`

IR cases:
1. Positive: `++global_byte` → `INR M`.
2. Positive: `--global_byte` → `DCR M`.
3. Positive: `global_byte = 0x42` → `MVI M, 0x42`.
4. Negative: `uint8_t x = global_byte++; use(x);` (A still live) → no fold.
5. Negative: intervening `MOV M, B` (store to `[HL]`) → no fold.
6. Toggle: `-v6clang-disable-peephole` → the three-MI sequence survives.

> **Implementation Notes**: _(empty)_

### Step 3.8 — Run regression tests [ ]

```
python tests\run_all.py
```

All lit + golden + integration suites must remain green.

> **Implementation Notes**: _(empty)_

### Step 3.9 — Verification assembly steps from `tests\features\README.md` [ ]

Compile `tests/features/42/v6clang.c` → `v6clang_newNN.asm` with all
three stages enabled. Confirm:
1. Every `MOV r, M; XRA/ANA/ORA/ADD r` in `xor_bytes` / `and_bytes` /
   `or_bytes` / `add_bytes` has collapsed to `XRA M` / `ANA M` / `ORA M`
   / `ADD M`.
2. If the test exposes `++global` or `global = imm` patterns, the
   corresponding `INR M` / `DCR M` / `MVI M, imm` forms appear.

> **Implementation Notes**: _(empty)_

### Step 3.10 — Make sure result.txt is created [ ]

Create `tests/features/42/result.txt` with:
- the C test code,
- c8080's main+deps asm (for comparison),
- c8080 stats,
- v6clang asm (post-fold),
- v6clang stats.

> **Implementation Notes**: _(empty)_

### Step 3.11 — Sync mirror [ ]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: _(empty)_

---

## 4. Expected Results

### Example 1 — Stage 1: `many_i8` (feature 38)

Four folds in one function body → **16cc saved, 4B saved**. The folded
sequence becomes:

```asm
LDA   __v6clang_ss.many_i8+1
LXI   HL, __v6clang_ss.many_i8
XRA   M
LXI   HL, __v6clang_ss.many_i8+2
XRA   M
LXI   HL, __v6clang_ss.many_i8+3
XRA   M
LXI   HL, __v6clang_ss.many_i8+4
XRA   M
```

### Example 2 — Stage 2: non-adjacent fold across safe MIs

```asm
; Before:
LXI   HL, __v6clang_ss.x
MOV   L, M            ; load *HL into L
MOV   C, D            ; independent of L, HL, A, FLAGS
ORA   L

; After (Stage 2):
LXI   HL, __v6clang_ss.x
MOV   C, D
ORA   M
```

Saves 4cc, 1B while the `MOV C, D` stays in place.

### Example 3 — Stage 3: in-place increment / constant store

```asm
; Before:
LXI   HL, counter
MOV   A, M
INR   A
MOV   M, A              ; 20cc, 3B total

; After:
LXI   HL, counter
INR   M                 ; 10cc, 1B  (saves 10cc, 2B)
```

```asm
; Before:
LXI   HL, flag
MVI   A, 0x01
MOV   M, A              ; 15cc, 3B total

; After:
LXI   HL, flag
MVI   M, 0x01           ; 10cc, 2B  (saves 5cc, 1B)
```

### Example 4 — CMP cascades (Stage 1)

Any `MOV r, M; CMP r` (for `r ≠ A`, `r` dead) collapses to `CMP M`.
Frequent after O10 static-stack allocation exposes named global byte
comparisons.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `isRegDeadAfter` false positive → incorrect fold | Helper is already battle-tested in `foldCounterBranch` / `foldXraCmpZeroTest`. Unit test covers the "still live" negative case. |
| Missed fold because a `DBG_VALUE` sits between MOV and OP | Skip `isDebugInstr()` during adjacency scan — matches existing peephole conventions. |
| Kill flag on HL stale after fold | The `OP M` form already carries implicit `Uses = [HL]`; the stale kill on the erased `MOVrM` disappears with the instruction. MachineVerifier run in lit mode will flag any inconsistency. |
| Interaction with `foldXraCmpZeroTest` (O38) | O38 rewrites `MOV A, r; ORA A; Jcc` into `XRA A; CMP r; Jcc`. Our fold requires `r != A` so the two patterns operate on disjoint MI shapes. Run order: `foldMovAluM` first so the folded `CMP M` is visible to later passes, not the reverse (we never produce `MOV A, r`). |
| `r = A` accidentally accepted (Stage 1) | Explicit `MovDst == V6CLANG::A` early-exit. Covered by negative lit test. |
| Stage 2: intervening store aliases `[HL]` | `scanBetweenSafe` vetoes any `mayStore` MI. Covers STA, SHLD, STAX, MOV M, r, PUSH (writes SP-relative). |
| Stage 2: intervening MI redefines HL (DAD, LXI, XCHG, LHLD, POP HL) | `scanBetweenSafe` checks every operand against any register overlapping HL — catches both explicit and implicit defs. |
| Stage 2: intervening MI redefines FLAGS (any ALU op, CMP, rotate) | `scanBetweenSafe` rejects MIs that write FLAGS — required because the OP M we emit will set FLAGS that downstream consumers (Jcc) expect. |
| Stage 2: large BB causes quadratic scan | Hard-cap the forward scan window (e.g. 16 MIs). After that, register pressure almost certainly forces `r` into a new role and the fold no longer applies. |
| Stage 3: `A` observed after `MOV M, A` | `isRegDeadAfter(A, MovMr)` must succeed. Covered by negative lit test. |
| Stage 3: incorrect opcode mapping (INRr → INRM mismatch) | Opcode map is a closed switch; fuzz via lit test with all three shapes (INR/DCR/MVI). |
| Stage 3: store-to-load forwarding collision | Unchanged — O16 runs later and may still observe the now-fused `INR M` sequence; there is no semantic difference compared to the original three-MI form. |

---

## 6. Relationship to Other Improvements

- **O49 (direct memory ALU/store ISel)** — O65 is an orthogonal post-RA
  backstop. O49 eliminates the temporary at DAG level; O65 recovers any
  fold that survives to post-RA (loads emitted by expansion passes, ops
  paired after rescheduling, the not-yet-implemented state of O49).
- **O10 (static stack)** and **O20 (honest load/store defs)** — expose
  more single-use `[HL]` byte reads, increasing O65's hit rate.
- **O42 (liveness-aware expansion)** and **O44 (XCHG cancellation)** —
  share the peephole pass. No interference; ordered first by
  `cancelAdjacentXchg`, then this pattern.
- **O38 (XRA+CMP zero test)** — disjoint (see Risks above).

---

## 7. Future Enhancements

1. **Teach `V6ClangLoadImmCombine` / `V6ClangAccumulatorPlanning`** — now that
   `A` transitions fewer times through scratch registers, upstream
   analyses can tighten their invalidation rules.
2. **Commutative ALU back-fold** — when the operand register holding
   the load-from-`[HL]` value is the ALU's LHS (e.g. `MOV A, r;
   MOV r, M; ADD A, r` shapes that survive scheduling), a commutativity-
   aware fold could swap operands before attempting Stage 2.
3. **LXI HL, <sym>; OP M coalescing with preceding stores** — when a
   nearby `STA <sym>` or `MOV M, A` is proven to write the same byte,
   the entire `LXI+OP M` pair could be recognized as store-to-load
   forwarding and collapsed further. Overlaps with O16.

---

## 8. References

* [O65 feature description](future_plans/O65_mov_alu_m_fold.md)
* [O49 design (direct memory ALU ISel)](future_plans/O49_direct_memory_alu_isel.md)
* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md)
* [Future Improvements](future_plans/README.md)
* [Peephole pass source](../llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp)
* [M-form ALU instruction definitions](../llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td#L291)
