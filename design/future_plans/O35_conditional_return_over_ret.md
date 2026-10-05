# O35. Conditional Return Over RET (Jcc-over-RET → Rcc)

*Identified from analysis of temp/test_o28.asm `test_cond_zero_tailcall`.*
*Extends V6ClangBranchOpt — complements O30 (Jcc→RET block → Rcc).*

## Problem

When a conditional branch jumps over a `RET` instruction that is the
fallthrough, the sequence can be replaced by an inverted conditional
return (`Rcc`), eliminating the `Jcc` + `RET` pair (4 bytes → 1 byte).

The existing O30 (`foldConditionalReturns`) handles the case where the
Jcc **target** is a RET-only block. This optimization handles the
**complementary** case: the Jcc jumps **over** a fallthrough RET.

### Pattern: Jcc over RET

Before:
```asm
; bb.0:
    MOV  A, H
    ORA  L
    JZ   .LBB0_1       ; 3 bytes — conditional branch over RET
; bb.2:
    RET                 ; 1 byte — fallthrough return
.LBB0_1:
    LXI  HL, 0
    JMP  bar            ; tail call
```

After:
```asm
; bb.0:
    MOV  A, H
    ORA  L
    RNZ                 ; 1 byte — inverted conditional return
; merged with .LBB0_1:
    LXI  HL, 0
    JMP  bar            ; tail call
```

### Savings

- Eliminates: `JZ .LBB0_1` (3 bytes, 12cc) + `RET` (1 byte, 12cc)
- Replaces with: `RNZ` (1 byte, 6cc when not taken / 12cc when taken)
- **Net savings: 3 bytes per instance.** Cycles: 18cc saved when returning,
  0cc saved when falling through.

### Where this pattern appears

This pattern is common in short functions with early-return guards:

```c
int test_cond_zero_tailcall(int x) {
    if (x == 0) return bar(0);
    return 0;
}
```

After O27 (zero-test) + O28 (branch threading), the compiler generates the
"Jcc over RET" pattern because:
1. LLVM's block layout places the RET fallthrough *between* the conditional
   branch and the tail-call block.
2. `invertConditionalBranch` doesn't fire because the second instruction
   is `RET`, not `JMP`/`V6CLANG_TAILJMP`.
3. `foldConditionalReturns` doesn't fire because the Jcc **target** is
   the tail-call block, not the RET block.

### Relationship with existing sub-passes

| Sub-pass | Pattern | This case |
|----------|---------|-----------|
| `invertConditionalBranch` | `Jcc skip / JMP target / skip:` | ✗ — second instr is RET, not JMP |
| `foldConditionalReturns` (O30) | `Jcc → RET-only block` → `Rcc` | ✗ — Jcc target is tail-call block, not RET |
| **O35 (this)** | `Jcc skip / RET / skip:` → `Rcc_inv / skip:` | ✓ |

## Implementation

### Approach: Add `invertConditionalOverRET()` to V6ClangBranchOpt

Add a new method that detects `Jcc .Lskip / RET / .Lskip:` and replaces
with the inverted conditional return.

### Pseudocode

```cpp
/// Look for: Jcc .Lskip / RET / .Lskip: (layout successor)
/// Transform to: Rcc_inv  (inverted conditional return)
/// Then the code falls through to .Lskip's instructions.
bool V6ClangBranchOpt::invertConditionalOverRET(MachineFunction &MF) {
  bool Changed = false;

  for (MachineBasicBlock &MBB : MF) {
    if (MBB.size() < 2)
      continue;

    auto LastI = MBB.end();
    --LastI;
    MachineInstr &Last = *LastI;   // RET
    if (Last.getOpcode() != V6CLANG::RET)
      continue;

    --LastI;
    MachineInstr &Prev = *LastI;   // Jcc .Lskip
    unsigned InvOpc = getInvertedJcc(Prev.getOpcode());
    if (!InvOpc)
      continue;

    if (!Prev.getOperand(0).isMBB())
      continue;

    MachineBasicBlock *JccTarget = Prev.getOperand(0).getMBB();
    MachineFunction::iterator NextBB = std::next(MBB.getIterator());
    if (NextBB == MF.end() || &*NextBB != JccTarget)
      continue;

    // Map inverted Jcc → Rcc
    unsigned RccOpc = getConditionalReturn(InvOpc);
    if (!RccOpc)
      continue;

    BuildMI(MBB, Prev, Prev.getDebugLoc(), TII.get(RccOpc));
    Last.eraseFromParent();    // remove RET
    Prev.eraseFromParent();    // remove Jcc
    Changed = true;
  }

  return Changed;
}
```

### Pass ordering

Run after `invertConditionalBranch` (which handles Jcc+JMP) and before
`foldConditionalReturns` (which handles Jcc→RET block). Insert in
`runOnMachineFunction`:

```cpp
Changed |= threadJMPOnlyBlocks(MF);
Changed |= invertConditionalBranch(MF);
Changed |= invertConditionalOverRET(MF);   // ← new
Changed |= removeRedundantJMP(MF);
Changed |= foldConditionalReturns(MF);
Changed |= removeDeadBlocks(MF);
```

### Existing toggle

Uses the same `-v6clang-disable-branch-opt` flag (part of V6ClangBranchOpt).

### Affected tests

- `test_cond_zero_tailcall` in `tests/features/13/` — should now emit `RNZ`
  instead of `JZ` + `RET`.
- May need to update `tests/lit/CodeGen/V6Clang/branch-threading.ll` and
  `conditional-tail-call.ll` CHECK patterns.

## Complexity & Risk

- **Complexity:** Very Low (~20 lines)
- **Risk:** Very Low — pattern is simple and well-isolated; only fires when
  Jcc target is layout successor and the intervening instruction is RET.
- **Dependencies:** None strictly; benefits most after O27+O28 create the pattern.
