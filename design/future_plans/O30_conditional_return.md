# O30. Conditional Return Peephole (Jcc RET → Rcc)

*Identified from analysis of O27 (i16 zero-test) output.*
*The 8080 has single-byte conditional return instructions that are never emitted.*

## Problem

The 8080 instruction set includes conditional return instructions (`RZ`, `RNZ`,
`RC`, `RNC`, `RPO`, `RPE`, `RP`, `RM`) — each 1 byte, 11 cycles if taken,
5 cycles if not taken. The V6CLANG backend defines them in `V6ClangInstrInfo.td` but
never emits them — all returns go through unconditional `RET`.

The pattern `Jcc .Lret; ...; .Lret: RET` appears frequently. When the
conditional branch target is a block containing only `RET`, the entire
sequence can be replaced with a single conditional return instruction.

### Example: `if (x) return bar(x); return 0;`

Current output (after O27):
```asm
test_ne_zero:
    MOV  A, H          ; 1B  4T
    ORA  L             ; 1B  4T
    JZ   .LBB0_2       ; 3B 10T
    JMP  bar           ; 3B 10T
.LBB0_2:
    RET                ; 1B 10T
```
Total: 9 bytes (5 instructions).

With conditional return:
```asm
test_ne_zero:
    MOV  A, H          ; 1B  4T
    ORA  L             ; 1B  4T
    RZ                 ; 1B 11T (5T not taken)
    JMP  bar           ; 3B 10T
```
Total: **6 bytes** (4 instructions).

Savings: **3 bytes, 1 instruction** per instance.

### Frequency

This pattern appears whenever:
- If-then-else with early return
- Null-pointer / zero-check guards with fallthrough to function body
- Loop exit conditions returning a value
- Error-check bailouts

Estimated frequency: Medium-High (1-3 instances per non-trivial function).

### Interaction with existing optimizations

- **O14 (tail call)**: After CALL+RET → JMP, the RET block may become a
  conditional-return candidate if another branch targets it
- **O23 (conditional tail call)**: Reduces RET blocks, but remaining RET blocks
  are still targets for Jcc → Rcc
- **O27 (i16 zero-test)**: Produces `JZ .Lret` / `JNZ .Lret` patterns that
  are ideal candidates
- **O28 (branch threading)**: Threading JMP-only blocks may expose new
  Jcc→RET patterns or eliminate them — both passes should run

## Condition Code Mapping

| Jcc Opcode | Rcc Opcode | Condition |
|-----------|-----------|-----------|
| JZ  | RZ  | Zero |
| JNZ | RNZ | Not Zero |
| JC  | RC  | Carry |
| JNC | RNC | Not Carry |
| JPE | RPE | Parity Even |
| JPO | RPO | Parity Odd |
| JP  | RP  | Plus (Sign=0) |
| JM  | RM  | Minus (Sign=1) |

All Rcc instructions are already defined in `V6ClangInstrInfo.td` (lines 454-465)
with `isReturn = 1, isTerminator = 1, Uses = [SP, FLAGS]`.

## Implementation

### Approach: Add to V6ClangBranchOpt peephole pass

Add a new method `foldConditionalReturns()` to `V6ClangBranchOpt.cpp`:

```cpp
/// Replace `Jcc .Lret` with `Rcc` when .Lret contains only `RET`.
bool V6ClangBranchOpt::foldConditionalReturns(MachineFunction &MF) {
  bool Changed = false;

  for (MachineBasicBlock &MBB : MF) {
    for (MachineInstr &MI : MBB.terminators()) {
      unsigned Opc = MI.getOpcode();
      unsigned RccOpc = getConditionalReturn(Opc);
      if (!RccOpc)
        continue;

      MachineBasicBlock *Target = MI.getOperand(0).getMBB();
      if (!isReturnOnlyBlock(*Target))
        continue;

      // Replace Jcc with Rcc
      BuildMI(MBB, MI, MI.getDebugLoc(), TII->get(RccOpc));
      MI.eraseFromParent();
      Changed = true;
      break;  // terminators changed, restart
    }
  }
  return Changed;
}

static unsigned getConditionalReturn(unsigned JccOpc) {
  switch (JccOpc) {
  case V6CLANG::JZ:  return V6CLANG::RZ;
  case V6CLANG::JNZ: return V6CLANG::RNZ;
  case V6CLANG::JC:  return V6CLANG::RC;
  case V6CLANG::JNC: return V6CLANG::RNC;
  case V6CLANG::JPE: return V6CLANG::RPE;
  case V6CLANG::JPO: return V6CLANG::RPO;
  case V6CLANG::JP:  return V6CLANG::RP;
  case V6CLANG::JM:  return V6CLANG::RM;
  default: return 0;
  }
}

static bool isReturnOnlyBlock(const MachineBasicBlock &MBB) {
  auto I = MBB.begin();
  while (I != MBB.end() && I->isDebugInstr())
    ++I;
  return I != MBB.end() && I->getOpcode() == V6CLANG::RET &&
         std::next(I) == MBB.end();
}
```

### Run order

Run **after** O28 (branch threading) — threading may redirect branches away
from RET blocks, and conditional return should get what's left. Also run
after `invertConditionalBranch` since inversion can change which Jcc targets
the RET block.

### Dead block cleanup

After replacing `JZ .Lret` with `RZ`, the `.Lret: RET` block may become
unreachable (no remaining predecessors). The existing
`removeDeadBlocks()` in V6ClangBranchOpt already handles this.

## Complexity: Low

~30 lines of new code (mapping table + block check + replacement). The
conditional return instructions are already defined with correct encoding.
No new TableGen, no ISel changes. Pure post-RA peephole.

## Risk: Very Low

- Conditional returns are standard 8080 instructions
- 1:1 correspondence between Jcc and Rcc opcodes
- RET-only block detection is trivial
- No flag/register side effects beyond what Jcc already requires

## Testing

### Lit tests
- `Jcc .Lret; .Lret: RET` → `Rcc` for each condition code
- RET block with debug instructions — still folds
- RET block with other instructions — does NOT fold
- Multiple predecessors sharing same RET block — all get Rcc

### Golden tests
- Recompile `tests/features/08/` — should see `RZ`/`RNZ` in output
