# O28. Branch Threading Through JMP-Only Blocks

*Identified from analysis of temp/compare/07/v6clang.c output.*
*Synergy between O27 (i16 zero-test) and O14/O23 (tail calls).*

## Problem

When a conditional branch targets a basic block that contains only an
unconditional `JMP`, the conditional branch can be redirected directly to
the JMP's target, eliminating the intermediate block entirely. This pattern
appears frequently after O14/O23 tail call optimization creates JMP-only
blocks.

### Pattern: Conditional branch to JMP-only block

Before:
```asm
; BB0:
    MOV  A, H
    ORA  L
    JNZ  .LBB1         ; conditional branch to JMP-only block
    ; fall through to BB2
; BB1:
    JMP  bar            ; tail call — only instruction in block
; BB2:
    LXI  HL, 0
    RET
```

After threading:
```asm
; BB0:
    MOV  A, H
    ORA  L
    JNZ  bar            ; redirect directly to tail call target
    ; fall through to BB2
; BB2:
    LXI  HL, 0
    RET
; BB1 removed (dead code, no predecessors)
```

### How V6ClangBranchOpt's existing inversion relates

The existing `invertConditionalBranch()` in V6ClangBranchOpt handles a different
pattern: `Jcc .Lskip / JMP .Ltarget / .Lskip:` at the **end of the same
block**. It inverts to `J!cc .Ltarget` when the Jcc target is the layout
successor.

After O27 (zero-test) produces single-block code, the common case is:
```asm
; BB0:
    MOV  A, H
    ORA  L
    JZ   .LBB2         ; zero → return 0
    JMP  bar            ; non-zero → tail call
; BB2:
    LXI  HL, 0
    RET
```

Here the existing `invertConditionalBranch` fires correctly: `JZ .LBB2` +
`JMP bar` are in the same block, `.LBB2` is the layout successor → invert to
`JNZ bar`. **This case works for free once O27 is implemented.**

However, branch threading handles the **more general case** where the
conditional branch and the JMP are in **different blocks**. This occurs when:
- Block layout doesn't place both branches in the same block
- Multiple blocks conditionally branch to the same tail-call block
- The JMP-only block has multiple predecessors initially

### Full synergy with O27: `if (x) return bar(x); return 0;`

Without O27+O28 (current output, 22 bytes):
```asm
test_pattern_a:
    MOV  D, H           ; save x to DE (HL about to be clobbered)
    MOV  E, L
    LXI  HL, 0          ; materialize 0 for comparison AND return
    MOV  A, H            ; A = 0
    CMP  E               ; compare lo bytes
    JNZ  .LBB0_1
    MVI  A, 0            ; redundant (A still 0)
    CMP  D               ; compare hi bytes
    JZ   .LBB0_2
.LBB0_1:
    MOV  H, D            ; restore x from DE to HL
    MOV  L, E
    JMP  bar             ; tail call
.LBB0_2:
    RET
```

With O27 (zero-test) + existing BranchOpt inversion (8 bytes):
```asm
test_pattern_a:
    MOV  A, H            ; zero test: A = H
    ORA  L               ; A = H | L, Z flag set iff HL == 0
    JNZ  bar             ; non-zero → conditional tail call (3B)
    LXI  HL, 0           ; zero → return 0 (3B)
    RET                  ; (1B)
```

Savings: **14 bytes (64%)** and ~30+ cycles.

## Implementation

### Approach: Add JMP-threading pass to V6ClangBranchOpt

Add a new method `threadJMPOnlyBlocks()` to `V6ClangBranchOpt.cpp`:

```cpp
/// Thread conditional branches through JMP-only successor blocks.
/// If a Jcc targets a block whose only instruction is JMP target,
/// redirect the Jcc to target directly.
bool V6ClangBranchOpt::threadJMPOnlyBlocks(MachineFunction &MF) {
  bool Changed = false;

  for (MachineBasicBlock &MBB : MF) {
    for (MachineInstr &MI : MBB.terminators()) {
      unsigned InvOpc = getInvertedJcc(MI.getOpcode());
      if (!InvOpc && MI.getOpcode() != V6CLANG::JMP)
        continue;  // Not a branch to an MBB

      if (!MI.getOperand(0).isMBB())
        continue;

      MachineBasicBlock *Target = MI.getOperand(0).getMBB();

      // Check if Target is a JMP-only block.
      if (Target->size() != 1)
        continue;
      MachineInstr &TargetMI = Target->front();
      if (TargetMI.getOpcode() != V6CLANG::JMP)
        continue;
      if (!TargetMI.getOperand(0).isMBB())
        continue;

      // Redirect our branch to the JMP's target.
      MachineBasicBlock *FinalTarget = TargetMI.getOperand(0).getMBB();
      MI.getOperand(0).setMBB(FinalTarget);

      // Update CFG edges.
      MBB.replaceSuccessor(Target, FinalTarget);
      Changed = true;
    }
  }

  return Changed;
}
```

### Pass ordering

Add `threadJMPOnlyBlocks()` **before** `invertConditionalBranch()` and
`removeRedundantJMP()` in `runOnMachineFunction()`:

```cpp
bool V6ClangBranchOpt::runOnMachineFunction(MachineFunction &MF) {
  if (DisableBranchOpt)
    return false;

  bool Changed = false;
  Changed |= threadJMPOnlyBlocks(MF);       // NEW: thread through JMP blocks
  Changed |= invertConditionalBranch(MF);
  Changed |= removeRedundantJMP(MF);
  Changed |= removeDeadBlocks(MF);          // removes orphaned JMP-only blocks
  return Changed;
}
```

The `removeDeadBlocks()` pass (already existing) will clean up any JMP-only
blocks that become unreachable after threading.

## Benefit

- **3B + 10cc** per threaded branch (eliminated JMP instruction)
- **Entire block** removed when all predecessors are threaded (via dead block
  removal)
- **Frequency**: Medium — appears whenever conditional branches target
  tail-call blocks or other JMP-only blocks

## Complexity

Low. ~20-25 lines added to existing `V6ClangBranchOpt.cpp`. Uses existing
infrastructure (terminator iteration, CFG edge updates, dead block removal).

## Risk

Very Low. Conservative: only threads through blocks with exactly 1
instruction (JMP). Does not modify the block being threaded through — only
the branch source. Dead block removal handles cleanup.

## Dependencies

- O27 (i16 zero-test) creates the single-block patterns that benefit most
  from this optimization.
- O14/O23 (tail calls) create the JMP-only blocks that get threaded through.
- Both are recommended prerequisites but not hard requirements — the
  optimization is valid independently.
