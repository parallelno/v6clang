# Plan: O32 — XCHG in copyPhysReg (RA-Time DE↔HL Swap)

## 1. Problem

### Current behavior

When the register allocator needs to copy between DE and HL, it calls
`V6ClangInstrInfo::copyPhysReg()` which unconditionally emits two MOV
instructions:

```asm
    MOV  H, D           ; 1B  8cc
    MOV  L, E           ; 1B  8cc
```

This costs 2 bytes and 16 cycles.

### Desired behavior

When the source register pair is dead after the copy (`KillSrc=true`),
emit a single XCHG instruction instead:

```asm
    XCHG                ; 1B  4cc
```

Savings: 1 byte, 12 cycles per DE↔HL copy where source is killed.

### Root cause

`copyPhysReg()` uses a generic 16-bit copy path that decomposes the pair
into sub-registers and emits two MOVs. It does not check whether the
specific DE↔HL case can use the hardware XCHG instruction.

The register allocator provides a `KillSrc` flag that is always accurate
for physical register copies. When `KillSrc=true`, XCHG is semantically
safe — the "reverse swap" side-effect into the source pair doesn't matter
since nobody reads it.

---

## 2. Strategy

### Approach: Early check in copyPhysReg for DE↔HL + KillSrc

Add a check at the beginning of the 16-bit copy path: if both registers
are in {DE, HL} and `KillSrc` is true, emit XCHG instead of two MOVs.

### Why this works

- The RA has **authoritative liveness** — `KillSrc` is always correct
- XCHG does not affect FLAGS on 8080
- XCHG clobbers both DE and HL — but `KillSrc=true` guarantees the source
  is dead, and the destination gets the correct value
- No pattern-matching heuristics needed (unlike V6ClangXchgOpt peephole)
- Runs earlier, giving downstream passes better input

### Summary of changes

| File | Change |
|------|--------|
| V6ClangInstrInfo.cpp | Add XCHG early-exit in `copyPhysReg()` 16-bit path |
| xchg-copyphysreg.ll | New lit test verifying XCHG for DE→HL dead-source copy |

---

## 3. Implementation Steps

### Step 3.1 — Add XCHG optimization in copyPhysReg [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`

Add an early check in the 16-bit copy path of `copyPhysReg()`. Before
the existing sub-register decomposition, check if both registers are
DE and HL (in either direction) and `KillSrc` is true. If so, emit
a single XCHG and return.

```cpp
  // 16-bit pair copy: two MOV instructions (hi byte, then lo byte)
  if (V6CLANG::GR16RegClass.contains(DestReg) &&
      V6CLANG::GR16RegClass.contains(SrcReg)) {

    // DE↔HL with source killed: use XCHG (1B/4cc vs 2B/16cc).
    // Safe because source is dead — the reverse swap side-effect is harmless.
    if (KillSrc &&
        ((DestReg == V6CLANG::HL && SrcReg == V6CLANG::DE) ||
         (DestReg == V6CLANG::DE && SrcReg == V6CLANG::HL))) {
      BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
      return;
    }

    // General case: two MOV instructions
    ...
  }
```

> **Design Notes**: XCHG has `Defs = [DE, HL], Uses = [DE, HL]` in the
> .td definition. Since `KillSrc` is true, the source pair being
> overwritten is harmless. The destination pair gets the source's value,
> which is the desired semantics.

> **Implementation Notes**: Added 6-line early-exit check before sub-register decomposition. Checks `KillSrc && ((DestReg == V6CLANG::HL && SrcReg == V6CLANG::DE) || (DestReg == V6CLANG::DE && SrcReg == V6CLANG::HL))` and emits `BuildMI(MBB, MI, DL, get(V6CLANG::XCHG))`.

### Step 3.2 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Build succeeded — 5/5 targets linked.

### Step 3.3 — Lit test: xchg-copyphysreg.ll [x]

**File**: `tests/lit/CodeGen/V6CLANG/xchg-copyphysreg.ll`

Create a lit test that verifies XCHG is emitted for a DE→HL copy where
the source register is dead. A function that returns its second argument
(passed in DE) triggers a DE→HL copy with `KillSrc=true` since DE is dead
at the return point.

```llvm
; RUN: llc -march=v6clang < %s | FileCheck %s

; The second i16 argument arrives in DE. Returning it requires a copy
; DE→HL. Since DE is dead after the copy, copyPhysReg should emit XCHG.

; CHECK-LABEL: return_second:
; CHECK:       XCHG
; CHECK-NEXT:  RET
define i16 @return_second(i16 %a, i16 %b) {
  ret i16 %b
}
```

> **Implementation Notes**: Created `tests/lit/CodeGen/V6CLANG/xchg-copyphysreg.ll` with `return_second` (returns 2nd i16 arg). CHECK: XCHG / CHECK-NEXT: RET / CHECK-NOT: MOV H, D / CHECK-NOT: MOV L, E. Test passes.

### Step 3.4 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: 87/87 lit + 15/15 golden — all pass. No regressions.

### Step 3.5 — Verification assembly steps from `tests\features\README.md` [x]

Compile feature test case and verify XCHG appears instead of MOV pairs
at function exits where DE→HL copies have dead sources.

> **Implementation Notes**: `return_second`: XCHG+RET (2B/16cc) vs MOV H,D+MOV L,E+RET (3B/28cc). Savings: 1B, 12cc confirmed.

### Step 3.6 — Make sure result.txt is created. `tests\features\README.md` [x]

> **Implementation Notes**: result.txt created in tests/features/11/.

### Step 3.7 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Mirror sync complete. V6ClangInstrInfo.cpp synced to llvm/.

---

## 4. Expected Results

### Example 1: `return_second` (return 2nd arg)

Before:
```asm
return_second:
    MOV  H, D           ; 1B  8cc
    MOV  L, E           ; 1B  8cc
    RET                 ; 1B 12cc
    ; total: 3B 28cc
```

After:
```asm
return_second:
    XCHG                ; 1B  4cc
    RET                 ; 1B 12cc
    ; total: 2B 16cc
```

Savings: **1 byte, 12 cycles**.

### Example 2: Function epilogue with DE→HL copy

Any function that computes a result in DE and needs to return it in HL
will benefit. The RA marks the DE source as killed at the copy point
since it's the last use before the function return.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| XCHG clobbers both DE and HL | `KillSrc=true` guarantees source is dead; destination gets correct value |
| Interaction with FLAGS | XCHG does not affect FLAGS on 8080 — no risk |
| Post-RA passes confused by XCHG | XCHG is already used by V6ClangXchgOpt; all passes handle it |
| `KillSrc` accuracy | Set by the register allocator — authoritative for physical copies |

---

## 6. Relationship to Other Improvements

- **Supersedes most V6ClangXchgOpt (O8/M8) cases**: The peephole catches MOV pairs
  that `copyPhysReg` emitted. With this change, those pairs are never emitted
  when the source is killed — the peephole has less work.
- **O33 (XCHG peephole relaxation)**: Handles remaining edge cases where
  `KillSrc=false` but source becomes dead later.
- **No dependencies**: Standalone change to `copyPhysReg()`.

---

## 7. Future Enhancements

- O33 can relax the V6ClangXchgOpt peephole to drop the `isRegLiveBefore` guard,
  catching more XCHG opportunities that `copyPhysReg` can't see.

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [Feature Design](design\future_plans\O32_xchg_in_copy_phys_reg.md)
