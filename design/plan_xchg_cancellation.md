# Plan: Adjacent XCHG Cancellation Peephole (O44)

## 1. Problem

### Current behavior

Multiple pseudo expansions independently emit XCHG instructions to
temporarily swap HL↔DE. When two such expansions are adjacent in the MIR,
their trailing/leading XCHGs become consecutive in the final instruction
stream:

```asm
SHLD  __v6clang_ss.sumarray+2    ; spill arr1_ptr (DE via XCHG+SHLD+XCHG)
XCHG                          ; ← trailing from SPILL16 DE
XCHG                          ; ← leading from LOAD16_P DE
MOV   E, M                    ; load arr1[i] lo
INX   HL
MOV   D, M                    ; load arr1[i] hi
XCHG                          ; trailing from LOAD16_P DE
```

Cost: 8cc and 2B per pair for zero net effect.

### Desired behavior

```asm
SHLD  __v6clang_ss.sumarray+2    ; spill arr1_ptr
                               ; (two XCHGs cancelled — 8cc, 2B saved)
MOV   E, M
INX   HL
MOV   D, M
XCHG
```

### Root cause

The O42 liveness-aware expansion correctly preserves the trailing XCHG
when `!(IsKill && HLDead)`. This is semantically correct but creates
adjacent `XCHG; XCHG` pairs when two XCHG-using expansions are
consecutive. Fixing this in `eliminateFrameIndex` would create fragile
coupling between independent expansions.

---

## 2. Strategy

### Approach: Post-expansion peephole in V6ClangPeepholePass

Add a new pattern method `cancelAdjacentXchg()` to `V6ClangPeephole.cpp`.
Single linear scan over each MBB looking for XCHG pairs that cancel out.
Two modes:

1. **Adjacent**: Two XCHGs with only debug instrs between them — delete both.
2. **Non-adjacent**: Two XCHGs separated by instructions that don't read or
   write DE, HL, or any of their sub-registers (D, E, H, L). Since the
   intervening instructions are DE/HL-agnostic, they behave identically
   regardless of the swap state — so the pair still cancels.

### Why this works

- XCHG swaps HL↔DE. Two XCHGs = identity = no-op.
- If all instructions between the two XCHGs are DE/HL-agnostic, they
  produce the same result with or without the swap — safe to remove both.
- XCHG does not affect flags on the 8080, so no flag state to preserve.
- The peephole runs after all pseudo expansions, so it sees the final
  instruction stream with no coupling risk.

### Summary of changes

| File | Change |
|------|--------|
| V6ClangPeephole.cpp | Add `cancelAdjacentXchg()` method + `touchesDEorHL()` helper, call first in `runOnMachineFunction` |
| V6ClangXchgOpt.cpp | Add adjacent XCHG cancellation cleanup loop after MOV→XCHG conversion |

---

## 3. Implementation Steps

### Step 3.1 — Add `cancelAdjacentXchg()` to V6ClangPeephole.cpp [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp`

Add a new private method `cancelAdjacentXchg(MachineBasicBlock &MBB)`:

```cpp
/// Return true if MI reads or writes DE, HL, or any sub-register (D,E,H,L).
static bool touchesDEorHL(const MachineInstr &MI,
                          const TargetRegisterInfo *TRI) {
  for (const MachineOperand &MO : MI.operands()) {
    if (!MO.isReg())
      continue;
    Register Reg = MO.getReg();
    if (TRI->regsOverlap(Reg, V6CLANG::DE) || TRI->regsOverlap(Reg, V6CLANG::HL))
      return true;
  }
  return false;
}

/// Cancel XCHG pairs: XCHG; ...; XCHG → ... (remove both XCHGs).
/// Two XCHG instructions swap HL↔DE twice, which is a no-op.
/// Safe when all intervening instructions are DE/HL-agnostic (don't
/// read or write D, E, H, L, DE, or HL). Also handles the simple
/// adjacent case (no intervening instructions). Skips debug instrs.
bool V6ClangPeephole::cancelAdjacentXchg(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ) {
    if (I->getOpcode() != V6CLANG::XCHG) {
      ++I;
      continue;
    }
    // Scan forward looking for a matching XCHG.
    auto J = std::next(I);
    bool CanCancel = true;
    while (J != E) {
      if (J->isDebugInstr()) {
        ++J;
        continue;
      }
      if (J->getOpcode() == V6CLANG::XCHG)
        break; // Found matching XCHG.
      if (touchesDEorHL(*J, TRI)) {
        CanCancel = false;
        break; // Intervening instr uses DE/HL — can't cancel.
      }
      ++J;
    }
    if (CanCancel && J != E && J->getOpcode() == V6CLANG::XCHG) {
      // XCHG pair found — delete both.
      MBB.erase(J);        // erase second XCHG
      I = MBB.erase(I);    // erase first XCHG, I now points to next
      Changed = true;
      continue;             // re-check from new I (may be another XCHG)
    }
    ++I;
  }
  return Changed;
}
```

Call it first in `runOnMachineFunction` (before other peephole patterns
so they see cleaner code):

```cpp
bool V6ClangPeephole::runOnMachineFunction(MachineFunction &MF) {
  if (DisablePeephole)
    return false;
  bool Changed = false;
  for (MachineBasicBlock &MBB : MF) {
    Changed |= cancelAdjacentXchg(MBB);   // ← new, runs first
    Changed |= eliminateSelfMov(MBB);
    // ... rest unchanged ...
  }
  return Changed;
}
```

> **Design Notes**: Running first ensures later patterns (foldXchgDad, etc.)
> see cleaner code without redundant XCHG pairs.
> **Implementation Notes**: _empty_

### Step 3.2 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: _empty_

### Step 3.3 — Lit test: `xchg-cancel-peephole.ll` [x]

**File**: `llvm-project/llvm/test/CodeGen/V6CLANG/xchg-cancel-peephole.ll`

Create a lit test that checks adjacent XCHG pairs are removed from
the output assembly. Use a function with adjacent DE spill/reload
pseudo expansions that produce XCHG; XCHG pairs.

The test should verify:
- CHECK-NOT: consecutive XCHG lines (no adjacent XCHG pairs remain)
- CHECK: remaining single XCHGs are preserved where needed

> **Implementation Notes**: _empty_

### Step 3.4 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: _empty_

### Step 3.5 — Verification assembly steps from `tests\features\README.md` [x]

Compile the feature test case and analyze assembly for XCHG cancellation.

> **Implementation Notes**: _empty_

### Step 3.6 — Make sure result.txt is created. `tests\features\README.md` [x]

> **Implementation Notes**: _empty_

### Step 3.7 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: _empty_

---

## 4. Expected Results

### Sumarray loop with `--enable-deferred-spilling`

Adjacent XCHG pairs from SPILL16-DE + LOAD16_P-DE should be eliminated.
Expected savings: 8cc, 2B per XCHG pair in the loop body.

### General register-heavy code

Any code path where two XCHG-emitting pseudo expansions are adjacent
will benefit. This is most common with static stack spills/reloads
involving DE.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Debug instructions between XCHGs prevent match | Algorithm skips DBG_VALUE/CFI_INSTRUCTION |
| Removing XCHGs changes register state | Two XCHGs = identity; removal preserves exact register state |
| Non-adjacent removal changes semantics | Only cancelled when ALL intervening instrs are DE/HL-agnostic (operand check) |
| Interaction with foldXchgDad | cancelAdjacentXchg runs first, so foldXchgDad sees clean code |

---

## 6. Relationship to Other Improvements

- **O42 (liveness-aware expansion)**: O42's trailing XCHG fix creates
  these adjacent pairs. O44 cleans them up.
- **O43 (SHLD/LHLD→PUSH/POP)**: O44 should run before O43 so that
  cancelled XCHGs expose more direct SHLD/LHLD HL pairs for O43 to match.
- **foldXchgDad**: Complementary — foldXchgDad removes XCHG before DAD,
  cancelAdjacentXchg removes XCHG; XCHG pairs.

---

## 7. Future Enhancements

None identified.

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O44 Design](design\future_plans\O44_xchg_cancellation.md)
* [O42 Liveness-Aware Expansion](design\plan_liveness_aware_expansion.md)
