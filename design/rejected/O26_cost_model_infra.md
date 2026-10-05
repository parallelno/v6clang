# O26. Cost Model Infrastructure (getInstrCost + copyCost)

*From plan_dual_cost_model.md Future Enhancements.*
*Extension of O11 (Dual Cost Model) with MachineInstr-level cost queries.*

## Rejected
 its goals are already met in practice. Revisit only if a future pass needs to compare arbitrary MachineInstr sequences (e.g., a generic peephole framework). Keep V6ClangInstrCost.h as-is; pre-defined constants are sufficient.

## Problem

O11 introduced `V6ClangInstrCost` with pre-defined constants (e.g.,
`V6ClangCost::MOVrr`, `V6ClangCost::LXI`). Each optimization pass manually selects
the appropriate constant. This works but has limitations:

1. **No MachineInstr → cost mapping**: Passes must manually map opcodes to
   cost constants. If a pass encounters an unfamiliar opcode, it can't
   query its cost.

2. **No copy cost awareness**: Register allocation and copy-related passes
   (O12, O20) don't know that `MOV D,H; MOV E,L` (16cc) is cheaper than
   `PUSH HL; POP DE` (24cc) for a DE←HL pair copy, or that XCHG (4cc) is
   cheapest when both pairs are live.

3. **No scheduling integration**: The V6ClangSchedule.td defines SchedWrite
   resources with latencies, but these aren't connected to V6ClangInstrCost.
   Passes that compare expansion costs must duplicate cycle counts.

## Implementation

### getInstrCost(const MachineInstr &MI)

Add to `V6ClangInstrCost.h`:

```cpp
/// Compute the cost of a single MachineInstr.
inline V6ClangInstrCost getInstrCost(const MachineInstr &MI) {
  switch (MI.getOpcode()) {
  case V6CLANG::MOVrr:  return V6ClangCost::MOVrr;
  case V6CLANG::MOVrM:  return V6ClangCost::MOVrM;
  case V6CLANG::MOVMr:  return V6ClangCost::MOVMr;
  case V6CLANG::MVIr:   return V6ClangCost::MVI;
  case V6CLANG::LXIrp:  return V6ClangCost::LXI;
  case V6CLANG::INXrp:  return V6ClangCost::INX;
  case V6CLANG::DCXrp:  return V6ClangCost::INX;  // same cost
  case V6CLANG::DADrp:  return V6ClangCost::DAD;
  case V6CLANG::PUSH:   return V6ClangCost::PUSH;
  case V6CLANG::POP:    return V6ClangCost::POP;
  case V6CLANG::CALL:   return V6ClangCost::CALL;
  case V6CLANG::RET:    return V6ClangCost::RET;
  // ... ALU ops, branches, etc.
  default:           return V6ClangInstrCost(1, 4); // conservative default
  }
}

/// Compute total cost of a range of MachineInstrs.
inline V6ClangInstrCost getSequenceCost(MachineBasicBlock::iterator Begin,
                                     MachineBasicBlock::iterator End) {
  V6ClangInstrCost Total(0, 0);
  for (auto I = Begin; I != End; ++I)
    Total = Total + getInstrCost(*I);
  return Total;
}
```

### copyCost(MCRegister Src, MCRegister Dst)

```cpp
/// Cost of copying between physical registers or register pairs.
inline V6ClangInstrCost copyCost(MCRegister Src, MCRegister Dst) {
  // 8-bit register copy
  if (V6CLANG::GR8RegClass.contains(Src) && V6CLANG::GR8RegClass.contains(Dst))
    return V6ClangCost::MOVrr;  // MOV dst, src: 8cc, 1B

  // 16-bit pair copy
  if (Src == V6CLANG::HL && Dst == V6CLANG::DE)
    return V6ClangCost::MOVrr * 2;  // MOV D,H; MOV E,L: 16cc, 2B
  if (Src == V6CLANG::DE && Dst == V6CLANG::HL)
    return V6ClangCost::MOVrr * 2;  // MOV H,D; MOV L,E: 16cc, 2B
  // BC↔HL, BC↔DE: also 2 MOVs
  return V6ClangCost::MOVrr * 2;    // 16cc, 2B for any pair copy
}

/// Cost of XCHG (DE↔HL swap) — only valid when both are live.
inline V6ClangInstrCost xchgCost() {
  return V6ClangInstrCost(1, 4);  // XCHG: 4cc, 1B
}
```

### Scheduling integration (optional)

Map SchedWrite resources from V6ClangSchedule.td to V6ClangInstrCost in a
helper table. This ensures consistency between the scheduler's latency
model and the cost model used by optimization passes.

## Benefit

- **Reduces code duplication**: Passes don't manually map opcodes to costs
- **Enables cost-aware expansion**: Pseudos can query expansion cost to
  choose the cheapest sequence at expansion time
- **copyCost**: Enables O12 (global copy opt) and O20 (honest store/load
  defs) to make cost-aware register transfer decisions
- **getSequenceCost**: Use in V6ClangLoadStoreOpt, V6ClangSPTrickOpt, etc. to
  compare before/after costs of transformations

## Complexity

Low. ~60-80 lines in V6ClangInstrCost.h. Pure infrastructure — header-only,
no new passes.

## Risk

Very Low. Cost queries are read-only. Wrong costs → suboptimal (not
incorrect) code. Can be tuned incrementally.

## Dependencies

O11 (Dual Cost Model) — already complete. This extends it.

## Testing

1. Unit-level: verify getInstrCost returns correct values for key opcodes
2. No behavioral change expected — this is infrastructure for other passes
