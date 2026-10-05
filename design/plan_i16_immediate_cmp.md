# Plan: MVI+SUB/SBB Immediate Ordering Comparison (O24)

## 1. Problem

### Current behavior

All i16 ordering comparisons (ULT, UGE, UGT, ULE, SLT, SGE) with
constant RHS materialize the constant into a register pair via LXI,
then use SUB/SBB with register operands:

```asm
; if (x < 1000) ...           ; ULT
    LXI  DE, 1000             ; 12cc, 3B  ← constant in register pair
    MOV  A, E                 ;  8cc, 1B
    SUB  L                    ;  4cc, 1B
    MOV  A, D                 ;  8cc, 1B
    SBB  H                    ;  4cc, 1B
    JC   .target              ; 12cc, 3B
; Comparison: 36cc, 7B (wastes DE for the constant)
```

### Desired behavior

```asm
; if (x < 1000) ...           ; ULT
    MVI  A, 0xe7              ;  8cc, 2B  ← lo8(999), flags untouched
    SUB  L                    ;  4cc, 1B  ← A = lo8(999) - L, sets CF
    MVI  A, 0x03              ;  8cc, 2B  ← hi8(999), CF preserved!
    SBB  H                    ;  4cc, 1B  ← A = hi8(999) - H - CF
    JNC  .target              ; 12cc, 3B
; Comparison: 24cc, 6B (no register pair needed)
```

Key insight: MVI does not affect flags on 8080, so it can be placed
between SUB and SBB without breaking the borrow/carry chain.

### Root cause

The V6CLANG_BR_CC16_IMM pseudo currently only handles EQ/NE conditions.
All ordering conditions fall through to V6CLANG_BR_CC16 (register variant),
which requires the constant in a register pair.

### Impact

| Metric | LXI+SUB/SBB (current) | MVI+SUB/SBB (target) | Savings |
|--------|----------------------|---------------------|---------|
| Cycles | 36cc | 24cc | 12cc |
| Bytes | 7B | 6B | 1B |
| Register pairs | 1 used for constant | 0 | 1 pair freed |

## 2. Strategy

### Approach: Extend V6CLANG_BR_CC16_IMM for ordering conditions

Reuse the existing pseudo-instruction, extending both ISel dispatch
(V6ClangISelDAGToDAG.cpp) and post-RA expansion (V6ClangInstrInfo.cpp) to
handle ordering conditions alongside EQ/NE.

### Why this works

The MVI+SUB/SBB sequence computes `const - reg` (reversed from the
register path's `reg - const`). Two cases arise:

**Case A — Constant on LHS** (from LowerBR_CC GT/LE swap):
The register path already computes `const - reg`. The MVI+SUB/SBB
direction matches, so no adjustment is needed. The CC is used as-is.

**Case B — Constant on RHS** (natural ULT/UGE/SLT/SGE):
The register path computes `reg - const`, but MVI+SUB computes
`const - reg`. To compensate, we adjust the constant to K−1 and
invert the CC (C↔NC, M↔P). This works because:
- `(K-1) - x` has CF=0 ↔ K-1 ≥ x ↔ x < K (matches ULT)
- `(K-1) - x` has CF=1 ↔ K-1 < x ↔ x ≥ K (matches UGE)
- Signed: analogous with SF and JP/JM

### Summary of changes

| File | Change |
|------|--------|
| V6ClangISelDAGToDAG.cpp | Extend BR_CC16 ISel to select V6CLANG_BR_CC16_IMM for ordering CCs with constant/Wrapper operands |
| V6ClangInstrInfo.cpp | Extend V6CLANG_BR_CC16_IMM expansion with MVI+SUB/SBB path for ordering CCs (no MBB split) |
| V6ClangISelLowering.cpp | In LowerSELECT_CC, swap/adjust-K/invert-CC for i16 ordering with constant RHS before emitting CMP |
| V6ClangISelDAGToDAG.cpp | In Select(), match V6ClangISD::CMP with i16 constant operand → V6CLANG_CMP16_IMM |
| V6ClangInstrInfo.td | New V6CLANG_CMP16_IMM pseudo (ins GR16, imm16) |
| V6ClangInstrInfo.cpp | Expand V6CLANG_CMP16_IMM → MVI+SUB, MVI+SBB (same as BR_CC16_IMM ordering, minus the Jcc) |
| br-cc16-imm-ord.ll | New lit test for all ordering conditions with immediate RHS |
| br-cc16-imm.ll | Update `lt_still_register` test to expect MVI+SUB/SBB |

## 3. Implementation Steps

### Step 3.1 — Extend ISel dispatch for ordering conditions [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangISelDAGToDAG.cpp`

In the `V6ClangISD::BR_CC16` case of `Select()`, after the existing EQ/NE
block, add handling for ordering conditions (COND_C/NC/M/P):

1. **Constant on LHS** (from swapped UGT/ULE/SGT/SLE):
   - Detect `ConstantSDNode` or `Wrapper(GlobalAddress)` on LHS
   - Swap: LHS←RHS (register), RHS←LHS (constant)
   - Keep CC unchanged (MVI+SUB direction matches)
   - Select `V6CLANG_BR_CC16_IMM`

2. **Constant on RHS** (natural ULT/UGE/SLT/SGE):
   - Detect `ConstantSDNode` on RHS
   - Adjust constant: K → K−1 (masks to i16)
   - Invert CC: C↔NC, M↔P
   - Guard: skip if K=0 (unsigned) or K=0x8000 (signed) to avoid underflow
   - Select `V6CLANG_BR_CC16_IMM`
   - For `Wrapper(GlobalAddress)` on RHS: adjust offset by −1

> **Implementation Notes**:

### Step 3.2 — Extend V6CLANG_BR_CC16_IMM expansion for ordering conditions [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

In `expandPostRAPseudo()` case `V6CLANG_BR_CC16_IMM`:

1. Remove the `assert((CC == COND_Z || CC == COND_NZ))` guard.
2. After the existing EQ/NE expansion block, add ordering expansion:
   ```
   MVI A, lo8(RHS)   ; via addImmLo lambda
   SUB LhsLo         ; 8080 SUBr
   MVI A, hi8(RHS)   ; via addImmHi lambda
   SBB LhsHi         ; 8080 SBBr
   Jcc Target         ; JC/JNC/JM/JP based on CC
   ```
3. No MBB splitting — ordering comparisons process both bytes via
   the borrow chain before a single conditional branch.

> **Design Notes**: Unlike EQ/NE (which early-exit per byte), ordering
> must process the full 16-bit borrow chain. The SameLoHi optimization
> does NOT apply here because SUB modifies A (unlike CMP).

> **Implementation Notes**:

### Step 3.3 — Add V6CLANG_CMP16_IMM pseudo [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.td`

Add a new pseudo alongside the existing `V6CLANG_CMP16`:
```tablegen
let Defs = [A, FLAGS] in
def V6CLANG_CMP16_IMM : V6ClangPseudo<(outs), (ins GR16:$lhs, imm16:$rhs),
    "# CMP16_IMM $lhs, $rhs",
    []>;
```
No TableGen pattern — ISel selection happens in `Select()` because the
constant-on-RHS case needs K→K-1 + CC inversion, and the CC lives on
a separate SELECT_CC node.

> **Implementation Notes**:

### Step 3.4 — Extend LowerSELECT_CC for ordering with constant RHS [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangISelLowering.cpp`

In `LowerSELECT_CC()`, after the existing O34 zero-test block, add
handling for i16 ordering conditions with constant RHS:

1. **Constant on LHS** (from swapped UGT/ULE):
   - Swap LHS↔RHS so the constant becomes the CMP's second operand
   - Keep CC unchanged (MVI+SUB direction matches `const - reg`)

2. **Constant on RHS** (natural ULT/UGE/SLT/SGE):
   - Adjust constant: K → K-1 (masks to i16)
   - Invert CC: C↔NC, M↔P
   - Guard: skip if K=0 (unsigned) or K=0x8000 (signed)

Then emit `V6ClangISD::CMP(LHS, adjusted_RHS)` + `V6ClangISD::SELECT_CC` with
the adjusted CC. The key insight: this is the only place where both
the CMP operands and the CC are simultaneously accessible.

> **Design Notes**: Unlike BR_CC16 (where CC and constant are on the same
> pseudo), SELECT_CC separates them into CMP and SELECT_CC nodes. The
> swap/adjust must happen here before the nodes are created.

> **Implementation Notes**:

### Step 3.5 — Extend ISel Select() for V6ClangISD::CMP with i16 constant [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangISelDAGToDAG.cpp`

In `Select()`, add a handler for `V6ClangISD::CMP` (alongside the existing
`V6ClangISD::BR_CC16` case):

1. Check if the operation is i16 (`LHS.getValueType() == MVT::i16`)
2. Check if RHS is a `ConstantSDNode` or `Wrapper(GlobalAddress)`
3. If so, select `V6CLANG_CMP16_IMM` instead of letting TableGen match
   `V6CLANG_CMP16`

No CC adjustment here — that was already done in `LowerSELECT_CC()`.

> **Implementation Notes**:

### Step 3.6 — Expand V6CLANG_CMP16_IMM post-RA [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

Add `case V6CLANG::V6CLANG_CMP16_IMM:` in `expandPostRAPseudo()`:
```
MVI A, lo8(RHS)   ; via addImmLo lambda (reuse from BR_CC16_IMM)
SUB LhsLo         ; 8080 SUBr
MVI A, hi8(RHS)   ; via addImmHi lambda
SBB LhsHi         ; 8080 SBBr
```
Same as the BR_CC16_IMM ordering expansion, minus the final Jcc.
The FLAGS output feeds into the SELECT_CC16 diamond.

> **Implementation Notes**:

### Step 3.7 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**:

### Step 3.8 — Lit test: br-cc16-imm-ord.ll [x]

**File**: `llvm-project/llvm/test/CodeGen/V6Clang/br-cc16-imm-ord.ll`

Test all six ordering conditions with integer constants:
- `test_ult`: `icmp ult i16 %x, 1000` → CHECK for MVI+SUB, MVI+SBB, no LXI
- `test_uge`: `icmp uge i16 %x, 1000` → CHECK for MVI+SUB, MVI+SBB
- `test_ugt`: `icmp ugt i16 %x, 1000` → CHECK for MVI+SUB, MVI+SBB
- `test_ule`: `icmp ule i16 %x, 1000` → CHECK for MVI+SUB, MVI+SBB
- `test_slt`: `icmp slt i16 %x, 500` → CHECK for MVI+SUB, MVI+SBB
- `test_sge`: `icmp sge i16 %x, 500` → CHECK for MVI+SUB, MVI+SBB
- `test_ult_global`: `icmp ult ptr %p, @arr+100` → CHECK for lo8/hi8
- `test_select_ult`: `select(icmp ult i16 %x, 1000, ...)` → CHECK for MVI+SUB, MVI+SBB, no LXI
- `test_select_slt`: `select(icmp slt i16 %x, 500, ...)` → CHECK for MVI+SUB, MVI+SBB

> **Implementation Notes**:

### Step 3.9 — Update existing lit test: br-cc16-imm.ll [x]

**File**: `llvm-project/llvm/test/CodeGen/V6Clang/br-cc16-imm.ll`

Update `lt_still_register` test — it currently asserts that ULT uses
the register path. After this change, it should use MVI+SUB/SBB.

> **Implementation Notes**:

### Step 3.10 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**:

### Step 3.11 — Verification assembly steps from `tests\features\README.md` [x]

> **Implementation Notes**:

### Step 3.12 — Make sure result.txt is created. `tests\features\README.md` [x]

> **Implementation Notes**:

### Step 3.13 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**:

## 4. Expected Results

### Example 1: Unsigned less-than with constant

**Before** (LXI + register SUB/SBB):
```asm
test_ult:                       ; if (x < 1000)
    LXI  DE, 999                ; 12cc, 3B — constant in DE
    MOV  A, E                   ;  8cc, 1B
    SUB  L                      ;  4cc, 1B
    MOV  A, D                   ;  8cc, 1B
    SBB  H                      ;  4cc, 1B
    JNC  .done                  ; 12cc, 3B
```
Total comparison: 36cc, 7B. DE occupied.

**After** (MVI + SUB/SBB):
```asm
test_ult:                       ; if (x < 1000)
    MVI  A, 0xe7                ;  8cc, 2B — lo8(999)
    SUB  L                      ;  4cc, 1B
    MVI  A, 0x03                ;  8cc, 2B — hi8(999)
    SBB  H                      ;  4cc, 1B
    JNC  .done                  ; 12cc, 3B
```
Total comparison: 24cc, 6B. No register pair used.

### Example 2: Loop bounds check

**Before**: Loop comparing `i < 200` uses LXI DE, 200 per iteration
(or keeps DE alive across the loop body, occupying a register pair).

**After**: MVI+SUB/SBB inline — DE freed for loop variables, potentially
avoiding a spill.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| K−1 underflow for K=0 (unsigned) | Guard: skip IMM path, fall through to register path. LLVM folds `icmp ult x, 0` anyway. |
| K−1 underflow for K=−32768 (signed) | Guard: skip IMM path. LLVM folds `icmp slt x, INT_MIN` anyway. |
| Signed overflow in SUB/SBB | Same limitation as existing register path — not a new issue |
| Global address offset −1 wrapping | Only possible for globals at address 0, extremely unlikely |

## 6. Relationship to Other Improvements

- **Depends on**: Immediate CMP infrastructure (lo8/hi8 MCExpr, V6CLANG_BR_CC16_IMM
  pseudo) — all already implemented.
- **Benefits from**: O13 (LoadImmCombine) may further optimize redundant MVI
  loads if the same constant appears in adjacent comparisons.
- **Enhances**: All optimizations that benefit from reduced register pressure
  (fewer spills when DE/BC freed from holding comparison constants).

## 7. Future Enhancements

- Pattern-match sequences where the SUB/SBB result is used (not just flags)
- Combine with O29 (cross-BB immediate propagation) for repeated comparisons

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [Feature Description](design\future_plans\O24_i16_immediate_cmp.md)
* [Immediate CMP Plan](design\plan_immediate_cmp.md)
