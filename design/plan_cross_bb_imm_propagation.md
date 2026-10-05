# Plan: Cross-BB Immediate Value Propagation (O29)

## 1. Problem

### Current behavior

When `V6CLANG_BR_CC16_IMM` expands a 16-bit comparison with a non-zero
immediate, it splits the MBB into two blocks. The second block
(CompareHiMBB) always emits `MVI A, hi8(imm)` even when `lo8 == hi8`,
meaning A already holds the correct value from the first block.

More generally, `V6ClangLoadImmCombine` resets all register tracking at each
basic block boundary. Blocks with a single predecessor lose knowledge of
register values that are provably available from the predecessor's exit
state.

### Desired behavior

1. In BR_CC16_IMM expansion: skip the hi-byte MVI when `lo8 == hi8`
   (CMP and Jcc do not modify A).
2. In LoadImmCombine: for single-predecessor blocks, inherit the
   predecessor's register exit state so redundant MVI/LXI instructions
   can be eliminated across block boundaries.

### Root cause

1. The BR_CC16_IMM expansion unconditionally emits both MVI instructions
   without checking whether they load the same value.
2. LoadImmCombine's `invalidateAll()` at block entry discards all register
   knowledge, even when the predecessor uniquely determines register state.

---

## 2. Strategy

### Approach: Two-pronged fix

1. **Quick fix in BR_CC16_IMM expansion** (~5 lines in V6ClangInstrInfo.cpp):
   Guard the CompareHiMBB's `MVI A, hi8` with `lo8 != hi8`. This is trivially
   correct because CMP and Jcc/JMP don't modify A.

2. **Cross-BB propagation in LoadImmCombine** (~30 lines in V6ClangLoadImmCombine.cpp):
   Add `initFromPredecessor()` that forward-scans a single predecessor's
   instructions using existing `updateKnownValues` logic, then uses the exit
   state to initialize `KnownVal[]` for the current block.

### Why this works

- CMP sets only FLAGS, not A. JNZ/JZ/JMP modify no registers. So after
  `MVI A, lo8; CMP LhsLo; JNZ Target`, A still holds `lo8` on the
  fallthrough to CompareHiMBB.
- For the general case, single-predecessor blocks have exactly one possible
  register state at entry. Forward-scanning the predecessor recovers it.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Quick fix | Skip hi-byte MVI when lo8 == hi8 | V6ClangInstrInfo.cpp |
| Cross-BB init | Add initFromPredecessor() | V6ClangLoadImmCombine.cpp |
| Lit test | Cross-BB propagation test | tests/lit/CodeGen/V6Clang/ |

---

## 3. Implementation Steps

### Step 3.1 — Quick fix: skip hi-byte MVI when lo8 == hi8 in BR_CC16_IMM [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

In the V6CLANG_BR_CC16_IMM expansion (both NE and EQ paths), wrap the
CompareHiMBB's `MVI A, hi8` in `if (!sameLoHi)` where `sameLoHi` is
true when the RHS operand is an integer and `(imm & 0xFF) == ((imm >> 8) & 0xFF)`.

For global/symbol operands, `sameLoHi` is always false (lo8/hi8 are
address-dependent and generally differ).

```cpp
bool SameLoHi = RhsOp.isImm() &&
    (RhsOp.getImm() & 0xFF) == ((RhsOp.getImm() >> 8) & 0xFF);
```

Then for NE path, change:
```cpp
{
  auto MIB = BuildMI(CompareHiMBB, DL, get(V6CLANG::MVIr), V6CLANG::A);
  addImmHi(MIB);
}
```
to:
```cpp
if (!SameLoHi) {
  auto MIB = BuildMI(CompareHiMBB, DL, get(V6CLANG::MVIr), V6CLANG::A);
  addImmHi(MIB);
}
```

Same for EQ path.

> **Implementation Notes**: _empty_

### Step 3.2 — Cross-BB propagation: add initFromPredecessor() to LoadImmCombine [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangLoadImmCombine.cpp`

Add a new method that, for blocks with a single predecessor, forward-scans
the predecessor block using the same instruction-processing logic as
`processBlock` to compute the exit register state. This replaces
`invalidateAll()` as the initial state for the current block.

The method must:
1. Check `MBB.pred_size() == 1` (conservative: only single-predecessor).
2. Call `invalidateAll()` to clear state.
3. Forward-scan each instruction in the predecessor, applying the same
   tracking updates (MVI/MOV/LXI/INR/DCR/XCHG/POP/ALU/CALL/etc.).
4. Return — KnownVal now reflects predecessor's exit state.

In `processBlock`, replace the bare `invalidateAll()` call with
`initFromPredecessor(MBB)` which internally calls `invalidateAll()` when
there are multiple predecessors.

The existing `seedPredecessorValues()` still runs after, overriding with
branch-implied values where applicable.

> **Design Note**: This reuses all existing tracking logic — no new
> value-update code. The predecessor scan can be expensive for large blocks
> but single-predecessor blocks in typical V6CLANG code are small (from MBB
> splits).

> **Implementation Notes**: _empty_

### Step 3.3 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: _empty_

### Step 3.4 — Lit test: cross-bb-imm-propagation.ll [x]

**File**: `tests/lit/CodeGen/V6Clang/cross-bb-imm-propagation.ll`

Test cases:
1. **NE with lo8==hi8 (0x4242)**: Verify only one `MVI A, 66` appears.
2. **EQ with lo8==hi8**: Same pattern.
3. **NE with lo8!=hi8 (0x1234)**: Verify both MVI appear (negative test).
4. **Cross-BB propagation**: A function where a single-predecessor block
   starts with MVI that matches predecessor exit state → MVI eliminated.

> **Implementation Notes**: _empty_

### Step 3.5 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: _empty_

### Step 3.6 — Verification assembly steps from `tests\features\README.md` [x]

Compile the feature test case (`tests/features/18/v6clang.c`) and verify
the redundant MVI instructions are eliminated.

> **Implementation Notes**: _empty_

### Step 3.7 — Make sure result.txt is created. `tests\features\README.md` [x]

> **Implementation Notes**: _empty_

### Step 3.8 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: _empty_

---

## 4. Expected Results

### Example 1: NE comparison with 0x4242

Before:
```asm
    MVI  A, 0x42        ; 7cc, 2B
    CMP  L              ; 4cc, 1B
    JNZ  Target         ; 10cc, 3B
    MVI  A, 0x42        ; 7cc, 2B  ← REDUNDANT
    CMP  H              ; 4cc, 1B
    JNZ  Target         ; 10cc, 3B
    JMP  Fallthrough    ; 10cc, 3B
```

After (quick fix):
```asm
    MVI  A, 0x42        ; 7cc, 2B
    CMP  L              ; 4cc, 1B
    JNZ  Target         ; 10cc, 3B
    CMP  H              ; 4cc, 1B
    JNZ  Target         ; 10cc, 3B
    JMP  Fallthrough    ; 10cc, 3B
```

Saves: **2B + 7cc** per instance.

### Example 2: General cross-BB MVI elimination

Before:
```asm
BB0:
    MVI  A, 5
    ...
    JNZ  BB2
BB1:                    ; single predecessor = BB0
    MVI  A, 5          ; ← REDUNDANT, A still holds 5
    ...
```

After:
```asm
BB0:
    MVI  A, 5
    ...
    JNZ  BB2
BB1:
    ; (MVI A, 5 deleted)
    ...
```

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Quick fix incorrect when CMP modifies A | CMP only modifies FLAGS on 8080 — verified|
| Cross-BB propagation incorrect for multi-pred | Guard: `pred_size() == 1` only |
| Performance (scanning large predecessor blocks) | Single-predecessor blocks from MBB splits are small; negligible cost |
| Interaction with seedPredecessorValues() | Seeds run after and override — strictly additive |

---

## 6. Relationship to Other Improvements

- **O13 (Load-Immediate Combining)**: O29 extends O13's per-BB tracking
  to cross-BB. Uses the same KnownVal infrastructure.
- **O27 (i16 Zero-Test)**: Already eliminates MBB split for `== 0` case.
  O29 handles the remaining non-zero `lo8 == hi8` cases.
- **O36 (Branch-Implied Value Propagation)**: seedPredecessorValues seeds
  values based on branch conditions. O29's initFromPredecessor seeds based
  on predecessor's actual instruction stream. They compose (seed overrides init).

## 7. Future Enhancements

- Extend to multi-predecessor blocks with consistent exit state (all
  predecessors agree on a register's value). Low priority — rarely
  beneficial in practice.

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O29 Design](design\future_plans\O29_cross_bb_imm_propagation.md)
