# Plan: i16 Zero-Test Optimization (MOV+ORA)

## 1. Problem

### Current behavior

When comparing a 16-bit value against zero (`if (x)`, `if (!ptr)`,
`while (n)`), the V6CLANG backend routes through `V6CLANG_BR_CC16_IMM` with
RHS=0, producing a full two-byte CMP expansion with MBB splitting:

```asm
; BB0:
    MVI  A, 0           ; 7cc, 2B — lo8(0) = 0
    CMP  L              ; 4cc, 1B
    JNZ  .Lhi_cmp       ; 10cc, 3B — early-exit to second block
; BB1 (CompareHiMBB):
    MVI  A, 0           ; 7cc, 2B — hi8(0) = 0
    CMP  H              ; 4cc, 1B
    JZ   Target         ; 10cc, 3B
    JMP  Fallthrough    ; 10cc, 3B — explicit JMP for analyzeBranch
; Total: 42cc worst-case, 15B (+ MBB split overhead)
```

### Desired behavior

```asm
    MOV  A, H           ; 4cc, 1B
    ORA  L              ; 4cc, 1B — A = H | L, Z set iff HL == 0
    JZ   Target         ; 10cc, 3B (or JNZ for NE)
; Total: 18cc, 5B, NO MBB split, HL preserved
```

### Root cause

The `V6CLANG_BR_CC16_IMM` expansion treats all immediate values uniformly,
using the general-purpose MVI+CMP MBB-splitting pattern. The special case
of comparing against zero — which can be expressed as `MOV A, Hi; ORA Lo`
(a well-known 8080 idiom) — is not recognized.

---

## 2. Strategy

### Approach: Special case in V6CLANG_BR_CC16_IMM expansion

In `V6ClangInstrInfo.cpp`, `expandPostRAPseudo()` case `V6CLANG::V6CLANG_BR_CC16_IMM`:
add a check for `RhsOp.isImm() && RhsOp.getImm() == 0` before the existing
MBB-splitting code. When triggered, emit `MOV A, LhsHi` + `ORA LhsLo` +
`Jcc Target`, erase the pseudo, and return — no MBB split needed.

### Why this works

The `ORA` instruction ORs two bytes together: `A = A | LhsLo`. The result
is zero if and only if both `LhsHi` (loaded into A by MOV) and `LhsLo`
are zero — i.e., the 16-bit value is zero. The Z flag is set accordingly.

Since this is a single-block, three-instruction replacement:
- **No MBB split** — simpler CFG, better for subsequent optimization passes
- **HL preserved** — only A is modified (MOV copies Hi into A, ORA modifies A)
- **FLAGS correct** — ORA sets Z = (H|L == 0), which is (HL == 0)
- **Single conditional branch** — no early-exit pattern needed

### Summary of changes

| Step | What | Where |
|------|------|-------|
| 3.1 | Add zero-test fast path | `V6ClangInstrInfo.cpp` (expandPostRAPseudo) |
| 3.2 | Build | ninja |
| 3.3 | Lit test | `tests/lit/CodeGen/V6CLANG/br-cc16-zero.ll` |
| 3.4 | Run regression tests | `python tests/run_all.py` |
| 3.5 | Verification assembly | `tests/features/README.md` steps |
| 3.6 | Create result.txt | `tests/features/README.md` |
| 3.7 | Sync mirror | `scripts/sync_llvm_mirror.ps1` |

---

## 3. Implementation Steps

### Step 3.1 — Add zero-test fast path in V6CLANG_BR_CC16_IMM expansion [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`

In the `case V6CLANG::V6CLANG_BR_CC16_IMM:` block, after extracting operands and
sub-registers, add a check before the existing MBB-splitting code:

```cpp
    // --- O27: Fast zero-test path ---
    if (RhsOp.isImm() && RhsOp.getImm() == 0) {
      unsigned JccOpc = (CC == V6ClangCC::COND_Z) ? V6CLANG::JZ : V6CLANG::JNZ;
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::A).addReg(LhsHi);
      BuildMI(MBB, MI, DL, get(V6CLANG::ORAr), V6CLANG::A)
          .addReg(V6CLANG::A).addReg(LhsLo);
      BuildMI(MBB, MI, DL, get(JccOpc)).addMBB(Target);
      MI.eraseFromParent();
      return true;
    }
```

> **Design Notes**: Only fires for plain integer immediates equal to zero.
> Global addresses and external symbols always fall through to the existing
> MBB-splitting code. The three emitted instructions replace the pseudo
> in-place — no new MBBs, no successor changes needed.

> **Implementation Notes**: Added 10-line block after sub-register extraction, before the `addImmLo`/`addImmHi` lambdas. Checks `RhsOp.isImm() && RhsOp.getImm() == 0`, emits MOV+ORA+Jcc, erases pseudo.

### Step 3.2 — Build [x]

```bash
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

Expected: clean build. Change is confined to one case in expandPostRAPseudo.

> **Implementation Notes**: Clean build, 4/4 targets linked.

### Step 3.3 — Lit test: br-cc16-zero.ll [x]

**File**: `tests/lit/CodeGen/V6CLANG/br-cc16-zero.ll`

Test cases:
- `@ne_zero`: `icmp ne i16 %x, 0` → expect `MOV A,` + `ORA` + `JNZ`
- `@eq_zero`: `icmp eq i16 %x, 0` → expect `MOV A,` + `ORA` + `JZ`
- `@ne_nonzero`: `icmp ne i16 %x, 42` → expect `MVI` + `CMP` (existing path)
- `@ne_null_ptr`: `icmp ne ptr %p, null` → expect `MOV A,` + `ORA` + `JNZ`

Verify that:
- Zero comparisons use MOV+ORA (no MVI, no MBB split)
- Non-zero comparisons still use MVI+CMP (existing path unchanged)
- Null pointer checks use MOV+ORA

> **Implementation Notes**: 5 test cases: ne_zero, eq_zero, ne_nonzero (neg), ne_null_ptr, ne_global (neg). All pass.

### Step 3.4 — Run regression tests [x]

```bash
python tests\run_all.py
```

All existing tests must pass. The zero-test optimization should not affect
any non-zero comparison paths.

> **Implementation Notes**: 84/84 lit + 15/15 golden, zero regressions.

### Step 3.5 — Verification assembly steps from `tests\features\README.md` [x]

Compile the feature test case and analyze the assembly for improvements.

> **Implementation Notes**: All 4 test functions show MOV+ORA instead of MVI+CMP. MBB splits eliminated. Savings: 3-4B per zero-test instance.

### Step 3.6 — Make sure result.txt is created. `tests\features\README.md` [x]

> **Implementation Notes**: result.txt created in tests/features/08/.

### Step 3.7 — Sync mirror [x]

```powershell
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Mirror synced successfully.

---

## 4. Expected Results

### Direct savings per i16 zero comparison

| Metric | Before (BR_CC16_IMM, RHS=0) | After O27 | Savings |
|--------|------------------------------|-----------|---------|
| Bytes | 15B (both blocks) | 5B | **10B (67%)** |
| Cycles | 42cc worst-case | 18cc | **24cc (57%)** |
| MBB splits | 1 new block | 0 | **1 block** |
| Registers clobbered | A (via MVI) | A (via MOV) | HL preserved |

### Example: `if (x) return bar(x); return 0;`

Before O27:
```asm
    MOV  D, H           ; save HL to DE
    MOV  E, L
    MVI  A, 0
    CMP  L
    JNZ  .Lhi
    MVI  A, 0
    CMP  H
    JZ   .Lret0
.Lhi:
    MOV  H, D           ; restore HL
    MOV  L, E
    JMP  bar
.Lret0:
    LXI  H, 0
    RET
```

After O27:
```asm
    MOV  A, H
    ORA  L
    JNZ  bar            ; tail call (O14+O23)
    LXI  H, 0
    RET
```

### Cascade savings

Because O27 preserves HL and avoids the MBB split:
- **No DE save/restore**: HL stays intact, saving 2-4 MOVs (8-16cc, 2-4B)
- **Branch inversion enabled**: Single-block code allows BranchOpt's
  Jcc+JMP inversion to fire, potentially saving another 3B+10cc

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| ORA sets flags other than Z (S, P, CY=0) | Only Z and NZ conditions are used for EQ/NE. The other flags are irrelevant. CY is always cleared by ORA, but no code path relies on CY after this expansion. |
| A register clobbered | `Defs = [A, FLAGS]` on the pseudo already tells RA that A is clobbered. No change needed. |
| Non-zero immediates accidentally matched | The check is `RhsOp.isImm() && RhsOp.getImm() == 0` — explicit and conservative. Global addresses and external symbols are never matched. |
| Regression in existing tests | Only the RHS=0 case is affected. All other immediate values use the existing MBB-splitting path unchanged. |

---

## 6. Relationship to Other Improvements

- **O17 (Redundant Flag Elimination)**: O27 generates `ORA` which sets flags.
  If a subsequent `ORA A` is emitted by another path, O17 will eliminate it.
- **O14/O23 (Tail Call)**: O27's single-block output enables conditional tail
  calls by keeping the code path simple (no MBB split between the condition
  and the CALL+RET).
- **O28 (Branch Threading)**: O27 eliminates MBB splits that would create
  JMP-only blocks. O28 would clean those up, but O27 prevents them entirely.

---

## 7. Future Enhancements

- **V6CLANG_BR_CC16 (register-register)**: Could detect when RHS register is
  known to be zero (via O13 value tracking), but this is rare enough to defer.
- **SELECT_CC with 0**: Similar optimization for `x ? a : b` when x is i16.
  The SELECT_CC16 expansion could use the same ORA pattern.

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O27 Feature Description](design\future_plans\O27_i16_zero_test.md)
* [Plan Format Reference](design\plan_cmp_based_comparison.md)
