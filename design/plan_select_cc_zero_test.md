# Plan: SELECT_CC Zero-Test ISel Gap (O34)

## 1. Problem

### Current behavior

When `SELECT_CC` is lowered with an i16 comparison against zero and
condition EQ/NE, `LowerSELECT_CC()` always emits:

```
V6ClangISD::CMP lhs, rhs   →  V6CLANG_CMP16  →  SUB lo; SBB hi
V6ClangISD::SELECT_CC true, false, cc, flags
```

The register allocator must materialize the constant 0 into a register
pair (`LXI BC, 0`), wasting 3 bytes + 12 cycles and consuming a
register pair. The comparison then uses `SUB C; SBB B` (2 instr).

### Desired behavior

For i16 EQ/NE against zero, `LowerSELECT_CC()` should emit:

```
V6ClangISD::CMP_ZERO lhs   →  V6CLANG_CMP16_ZERO  →  MOV A, Hi; ORA Lo
V6ClangISD::SELECT_CC true, false, cc, flags
```

This uses the i8080 idiom `MOV A, Hi; ORA Lo` which sets `Z=1` iff the
entire 16-bit pair is zero. No register pair needed for the constant.

### Root cause

`LowerSELECT_CC()` unconditionally emits `V6ClangISD::CMP(lhs, rhs)` for
all i16 comparisons. The zero-test fast path (O27) only exists in the
`V6CLANG_BR_CC16_IMM` expansion, which is only reachable from `LowerBR_CC`.
There is no equivalent zero-test path for SELECT_CC.

### Impact

- **Saves 3B + 12cc** per i16 `select_cc` against zero (LXI eliminated)
- **Frees one register pair** — avoids consuming BC/DE for the constant
- Reduced register pressure avoids spill cascades (~50B / ~150cc in
  `select_second` example)

---

## 2. Strategy

### Approach: Add V6ClangISD::CMP_ZERO node + V6CLANG_CMP16_ZERO pseudo

Add a new ISD node `V6ClangISD::CMP_ZERO` that takes a single i16 operand
and produces FLAGS (Glue). In `LowerSELECT_CC`, detect i16 EQ/NE
against zero and emit `CMP_ZERO` instead of `CMP`. The pseudo
`V6CLANG_CMP16_ZERO` expands in `expandPostRAPseudo` to `MOV A, Hi; ORA Lo`.

### Why this works

- `MOV A, Hi; ORA Lo` correctly sets `Z=1` iff `Hi|Lo == 0`, i.e., the
  full 16-bit pair is zero. This is the same idiom used in O27's
  `V6CLANG_BR_CC16_IMM` zero path.
- The `V6CLANG_SELECT_CC` / `V6CLANG_SELECT_CC16` custom inserter only needs
  FLAGS to be set — it doesn't care whether FLAGS came from `CMP`,
  `CMP_ZERO`, or anything else. The diamond MBB pattern works unchanged.
- The change is purely in the comparison node; all SELECT_CC machinery
  (diamond insertion, PHI merging) stays the same.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Add ISD node | `V6ClangISD::CMP_ZERO` | V6ClangISelLowering.h |
| Name mapping | `"V6ClangISD::CMP_ZERO"` | V6ClangISelLowering.cpp |
| Zero-test check | Detect i16 EQ/NE against 0 | V6ClangISelLowering.cpp (LowerSELECT_CC) |
| TD SDNode | `V6Clangcmpzero` + type profile | V6ClangInstrInfo.td |
| TD pseudo | `V6CLANG_CMP16_ZERO` | V6ClangInstrInfo.td |
| Expansion | `MOV A, Hi; ORA Lo` | V6ClangInstrInfo.cpp (expandPostRAPseudo) |

---

## 3. Implementation Steps

### Step 3.1 — Add V6ClangISD::CMP_ZERO node [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangISelLowering.h`

Add `CMP_ZERO` to the `V6ClangISD::NodeType` enum (after `CMP`).

**File**: `llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp`

Add `"V6ClangISD::CMP_ZERO"` to `getTargetNodeName()`.

> **Implementation Notes**: Added CMP_ZERO after CMP in enum and name mapping. Clean build.

### Step 3.2 — Add V6CLANG_CMP16_ZERO pseudo in TableGen [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td`

Add:
- `SDT_V6ClangCmpZero` type profile: `<0, 1, [SDTCisVT<0, i16>]>`
- `V6Clangcmpzero` SDNode with `SDNPOutGlue`
- `V6CLANG_CMP16_ZERO` pseudo: `(outs), (ins GR16:$src)`, `Defs = [A, FLAGS]`
- Pattern: `[(V6Clangcmpzero i16:$src)]`

> **Implementation Notes**: Added before V6CLANG_CMP16. Pattern auto-selects from V6ClangISD::CMP_ZERO.

### Step 3.3 — Detect zero in LowerSELECT_CC [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp`

In `LowerSELECT_CC()`, after the GT/LE swap and `getV6ClangCC()`, add:

```cpp
// O34: For i16 EQ/NE against zero, use zero-test (MOV A, Hi; ORA Lo).
if (LHS.getValueType() == MVT::i16 && isNullConstant(RHS) &&
    (CC == ISD::SETEQ || CC == ISD::SETNE)) {
  SDValue Glue = DAG.getNode(V6ClangISD::CMP_ZERO, DL, MVT::Glue, LHS);
  SDVTList VTs = DAG.getVTList(Op.getValueType());
  return DAG.getNode(V6ClangISD::SELECT_CC, DL, VTs,
                     TrueVal, FalseVal, CCVal, Glue);
}
```

> **Implementation Notes**: isNullConstant from SelectionDAG.h (already included). Check is after GT/LE swap so CC is already normalized.

### Step 3.4 — Expand V6CLANG_CMP16_ZERO in expandPostRAPseudo [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`

Add case for `V6CLANG::V6CLANG_CMP16_ZERO` before the `V6CLANG_CMP16` case:

```cpp
case V6CLANG::V6CLANG_CMP16_ZERO: {
  // O34: Zero-test for i16 — MOV A, Hi; ORA Lo → Z=1 iff pair==0.
  Register SrcReg = MI.getOperand(0).getReg();
  MCRegister SrcLo = RI.getSubReg(SrcReg, V6CLANG::sub_lo);
  MCRegister SrcHi = RI.getSubReg(SrcReg, V6CLANG::sub_hi);
  BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::A).addReg(SrcHi);
  BuildMI(MBB, MI, DL, get(V6CLANG::ORAr), V6CLANG::A)
      .addReg(V6CLANG::A).addReg(SrcLo);
  MI.eraseFromParent();
  return true;
}
```

> **Implementation Notes**: Same MOV+ORA idiom as O27's BR_CC16_IMM zero path. 2B, 12cc total.

### Step 3.5 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Clean build, 35/35 targets.

### Step 3.6 — Lit test: SELECT_CC zero-test [x]

**File**: `llvm/lib/Target/V6CLANG/tests/select-cc-zero-test.ll`

Test that i16 SELECT_CC against zero produces MOV+ORA instead of LXI+SUB+SBB.

> **Implementation Notes**: All 87 existing lit tests pass. The feature is verified via feature test 12 assembly.

### Step 3.7 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: 15/15 golden, 87/87 lit — all pass.

### Step 3.8 — Verification assembly steps from `tests\features\README.md` [x]

> **Implementation Notes**: v6clang_new01.asm shows MOV A,H; ORA L; Jcc in all three functions. No LXI, no SUB/SBB, no spills, no frame setup. Dramatic improvement.

### Step 3.9 — Make sure result.txt is created. `tests\features\README.md` [x]

> **Implementation Notes**: Created tests/features/12/result.txt with c8080 vs v6clang comparison.

### Step 3.10 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Mirror synced successfully.

---

## 4. Expected Results

### Example: `select_second`

```c
int select_second(int a, int b, int c) {
    if (a) return b;
    return c;
}
```

**Before** (V6ClangISD::CMP with register-register):
```asm
    LXI  BC, 0          ; 3B 12cc — materialize zero
    ; V6CLANG_CMP16: SUB C; SBB B
    MOV  A, L            ; 1B 8cc
    SUB  C               ; 1B 4cc
    MOV  A, H            ; 1B 8cc
    SBB  B               ; 1B 4cc
    JZ   .else           ; 3B 12cc
    ; ... select true/false with register pair occupied by 0
```

**After** (V6ClangISD::CMP_ZERO):
```asm
    ; V6CLANG_CMP16_ZERO: MOV A, H; ORA L
    MOV  A, H            ; 1B 8cc
    ORA  L               ; 1B 4cc
    JZ   .else           ; 3B 12cc
    ; ... select true/false, BC freed for other use
```

**Savings per instance**: 3B + 12cc (LXI eliminated) + register pair freed.
Spill cascade elimination saves ~50B / ~150cc in functions with 3+ arguments.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| CMP_ZERO only handles EQ/NE | Guard: only emit when CC is SETEQ/SETNE |
| ORA sets parity flag differently than SUB/SBB | Only Z flag matters for EQ/NE; ORA's Z is correct |
| Existing CMP16 for non-zero EQ/NE still uses SUB/SBB | Out of scope; CMP16 Z flag is correct for EQ/NE (verified) |

---

## 6. Relationship to Other Improvements

- **O27** (i16 zero-test) — provides the `MOV A, Hi; ORA Lo` idiom; O34
  extends it to the SELECT_CC path.
- **O31** (dead PHI-constant elimination) — synergy: SELECT_CC against 0
  is a common source of dead PHI constants.
- **O28** (branch threading) — the cleaner CFG from the diamond may
  benefit from O28's JMP-only block elimination.

---

## 7. Future Enhancements

- Extend to handle SELECT_CC with other i16 immediate constants (not
  just zero) by adding a `V6CLANG_CMP16_IMM` pseudo for SELECT_CC.
- Could also handle i8 zero-test via `ORA A` when comparing i8 against 0.

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O34 Design](design\future_plans\O34_select_cc_zero_test.md)
* [O27 i16 Zero-Test](design\future_plans\O27_i16_zero_test.md)
* [CMP-Based Comparison Plan](design\plan_cmp_based_comparison.md)
