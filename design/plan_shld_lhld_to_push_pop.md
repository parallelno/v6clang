# Plan: SHLD/LHLD to PUSH/POP Peephole (O43)

## 1. Problem

### Current behavior

In static stack mode, `V6CLANG_SPILL16 $hl` expands to `SHLD addr` (20cc, 3B)
and `V6CLANG_RELOAD16 $hl` expands to `LHLD addr` (20cc, 3B). When a spill
and its matching reload are nearby with no SP-affecting instructions between
them, this costs 40cc and 6B for a round-trip save/restore.

```asm
; sumarray inner loop with --enable-deferred-spilling:
SHLD  __v6clang_ss.sumarray    ; 20cc 3B — spill sum (HL)
MOV   H, B
MOV   L, C
MOV   E, M
INX   HL
MOV   D, M
LHLD  __v6clang_ss.sumarray    ; 20cc 3B — reload sum (HL)
                            ; total: 40cc, 6B
```

### Desired behavior

```asm
PUSH  HL                    ; 16cc 1B — spill sum (HL)
MOV   H, B
MOV   L, C
MOV   E, M
INX   HL
MOV   D, M
POP   HL                    ; 12cc 1B — reload sum (HL)
                            ; total: 28cc, 2B  (saves 12cc, 4B)
```

### Root cause

Static stack expansion always uses absolute-address SHLD/LHLD regardless
of proximity. A post-expansion peephole can detect close pairs and replace
them with cheaper PUSH/POP.

---

## 2. Strategy

### Approach: Post-expansion peephole in V6ClangPeepholePass

Add a new method `foldShldLhldToPushPop(MachineBasicBlock &MBB)` to
`V6ClangPeephole.cpp`. Single linear scan over each MBB: for each SHLD,
scan forward tracking SP delta. If a matching LHLD (same address) is
found with SP delta == 0, replace both.

### Why this works

- `PUSH HL` saves HL to the hardware stack; `POP HL` restores it.
  Semantically identical to SHLD/LHLD when SP returns to the same
  position and no one reads the static stack slot between them.
- SP delta tracking handles intervening balanced PUSH/POP pairs.
- `MI.modifiesRegister(V6CLANG::SP, TRI)` catches all SP-affecting
  instructions; the `else → abort` fallthrough is conservative.
- CALL/Ccc/RST are net-zero (callee restores SP via RET).
- DAD SP does not define SP, so `modifiesRegister` returns false.

### Summary of changes

| File | Change |
|------|--------|
| V6ClangPeephole.cpp | Add `foldShldLhldToPushPop()` method, call after `cancelAdjacentXchg` |

---

## 3. Implementation Steps

### Step 3.1 — Add `foldShldLhldToPushPop()` to V6ClangPeephole.cpp [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangPeephole.cpp`

Add a helper to compare SHLD/LHLD address operands, then the main method:

```cpp
/// Return true if two MachineOperands represent the same address
/// (both GlobalAddress with same GV and offset).
static bool isSameAddress(const MachineOperand &A, const MachineOperand &B) {
  if (A.getType() != B.getType())
    return false;
  if (A.isGlobal())
    return A.getGlobal() == B.getGlobal() && A.getOffset() == B.getOffset();
  if (A.isImm())
    return A.getImm() == B.getImm();
  return false;
}

/// Replace SHLD addr / LHLD addr pairs with PUSH HL / POP HL when
/// the pair is in the same basic block with SP delta == 0 at the LHLD.
bool V6ClangPeephole::foldShldLhldToPushPop(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();
  const TargetInstrInfo &TII = *MBB.getParent()->getSubtarget().getInstrInfo();

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ++I) {
    if (I->getOpcode() != V6CLANG::SHLD)
      continue;

    const MachineOperand &ShldAddr = I->getOperand(1);
    int SPDelta = 0;
    bool Abort = false;
    MachineBasicBlock::iterator MatchIt;
    bool Found = false;

    for (auto J = std::next(I); J != E; ++J) {
      if (J->isDebugInstr())
        continue;

      // Check for matching LHLD.
      if (J->getOpcode() == V6CLANG::LHLD &&
          isSameAddress(ShldAddr, J->getOperand(1))) {
        if (SPDelta == 0) {
          MatchIt = J;
          Found = true;
        } else {
          Abort = true;
        }
        break;
      }

      // Abort on re-spill to same address.
      if (J->getOpcode() == V6CLANG::SHLD &&
          isSameAddress(ShldAddr, J->getOperand(1))) {
        Abort = true;
        break;
      }

      // SP delta tracking.
      if (J->modifiesRegister(V6CLANG::SP, TRI)) {
        unsigned Opc = J->getOpcode();
        if (Opc == V6CLANG::PUSH) {
          SPDelta -= 2;
        } else if (Opc == V6CLANG::POP) {
          SPDelta += 2;
          if (SPDelta > 0) { Abort = true; break; }
        } else if (J->isCall()) {
          // CALL/Ccc/RST: net-zero SP effect, skip.
        } else {
          // Unknown SP modifier (SPHL, LXI SP, INX SP, DCX SP, etc.)
          Abort = true;
          break;
        }
      }
    }

    if (Abort || !Found)
      continue;

    // Replace SHLD with PUSH HL.
    BuildMI(MBB, *I, I->getDebugLoc(), TII.get(V6CLANG::PUSH))
        .addReg(V6CLANG::HL);
    // Replace LHLD with POP HL.
    BuildMI(MBB, *MatchIt, MatchIt->getDebugLoc(), TII.get(V6CLANG::POP), V6CLANG::HL);

    MatchIt->eraseFromParent();
    I = MBB.erase(I);
    Changed = true;
    --I; // compensate for ++I in loop header
  }
  return Changed;
}
```

Call it in `runOnMachineFunction` after `cancelAdjacentXchg`:

```cpp
Changed |= cancelAdjacentXchg(MBB);
Changed |= foldShldLhldToPushPop(MBB);    // ← new
Changed |= eliminateSelfMov(MBB);
```

> **Design Notes**: Runs after XCHG cancellation so that cancelled XCHGs
> expose more SHLD/LHLD HL pairs from DE spill sequences.
> **Implementation Notes**: _empty_

### Step 3.2 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: _empty_

### Step 3.3 — Lit test: `shld-lhld-push-pop-peephole.ll` [x]

**File**: `llvm-project/llvm/test/CodeGen/V6Clang/shld-lhld-push-pop-peephole.ll`

Positive test: function with short-lived HL spill between non-SP instructions.
Verify SHLD/LHLD are replaced with PUSH HL/POP HL.

Negative tests (SHLD/LHLD must NOT be replaced):
- SPHL between SHLD and LHLD
- LXI SP between SHLD and LHLD
- INX SP between SHLD and LHLD
- DCX SP between SHLD and LHLD
- Unbalanced PUSH/POP between SHLD and LHLD

> **Implementation Notes**: _empty_

### Step 3.4 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: _empty_

### Step 3.5 — Verification assembly steps from `tests\features\README.md` [x]

Compile feature test case and analyze assembly for PUSH/POP replacement.

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

Each SHLD/LHLD pair in the loop body (two pairs per iteration for sum
and arr1_ptr spills) should be converted to PUSH/POP, saving 12cc and
4B per pair.

### General register-heavy code

Any static-stack HL spill/reload pair with no unresolvable SP changes
between them benefits. Most common in loops where HL is the accumulator.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Intervening PUSH/POP breaks stack alignment | SP delta tracking; abort if delta != 0 at match or goes positive |
| Unknown SP modifier missed | `modifiesRegister(SP)` + `else → abort` fallthrough |
| Re-spill to same address (SHLD overwrite) | Abort on second SHLD to same address |
| LHLD with non-zero SP delta | Abort (POP would retrieve wrong value) |

---

## 6. Relationship to Other Improvements

- **O42 (liveness-aware expansion)**: O42 eliminates PUSH/POP around
  scratch register saves. O43 converts primary spill/reload SHLD/LHLD
  to PUSH/POP. Complementary.
- **O44 (XCHG cancellation)**: Should run before O43 so that cancelled
  XCHGs expose more direct SHLD/LHLD HL pairs from DE spill sequences.
- **O16 (store-to-load forwarding)**: O16 eliminates redundant reloads
  entirely. O43 handles pairs that O16 can't eliminate.

---

## 7. Future Enhancements

None identified.

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O43 Design](design\future_plans\O43_shld_lhld_to_push_pop.md)
* [O44 XCHG Cancellation](design\plan_xchg_cancellation.md)
