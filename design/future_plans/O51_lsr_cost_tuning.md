# O51. LSR Cost Tuning (isLSRCostLess Enhancement)

*Inspired by llvm-z80 `Z80TargetTransformInfo::isLSRCostLess()`.*
*Detailed analysis: [llvm_z80_analysis.md](llvm_z80_analysis.md) §S11.*

## Problem

V6CLANG already overrides `isLSRCostLess()` (implemented as part of O7), but
the Z80 backend's approach differs in a significant way: it prioritizes
**instruction count first**, ahead of register count.

The current V6CLANG ordering is:
```
NumRegs > Insns > NumBaseAdds > NumIVMuls > AddRecCost > ImmCost > SetupCost > ScaleCost
```

The Z80 ordering prioritizes `Insns` first:
```
Insns > NumRegs > AddRecCost > NumIVMuls > NumBaseAdds > ScaleCost > ImmCost > SetupCost
```

## Analysis

The Z80 rationale: each extra instruction costs 4-12cc and 1-3 bytes with
certainty, while an extra register *may* cause a spill (52-104cc) but often
doesn't if the register allocator finds slack.

The current V6CLANG rationale: register pressure is the dominant constraint with
only 3 GP pairs, so minimizing registers first avoids the worst case.

**Which is better for i8080?** This depends on typical register pressure. If
most loops already use all 3 pairs, then an extra register always spills and
NumRegs-first is correct. If loops typically have 1-2 pairs free, then the
Z80's Insns-first ordering avoids paying instruction cost for a spill that
may not occur.

## Implementation

Evaluate the Z80 ordering on the test suite and compare with the current
V6CLANG ordering. The change is a single line:

```cpp
// Option A: Current V6CLANG (register-first)
return std::tie(C1.NumRegs, C1.Insns, C1.NumBaseAdds, ...) <
       std::tie(C2.NumRegs, C2.Insns, C2.NumBaseAdds, ...);

// Option B: Z80 style (instruction-first)
return std::tie(C1.Insns, C1.NumRegs, C1.AddRecCost, ...) <
       std::tie(C2.Insns, C2.NumRegs, C2.AddRecCost, ...);
```

A `-mllvm` flag could allow switching between strategies:
```cpp
static cl::opt<bool> InsnFirst("v6clang-lsr-insns-first",
  cl::desc("Prioritize instruction count over register count in LSR"),
  cl::init(false));
```

## Benefit

- **Savings per instance**: Indirect — better LSR formula selection in loops
- **Frequency**: All loops with induction variables
- **Measurement**: Compare total cycle counts across test suite with both orderings

## Complexity

Very Low. ~10 lines. Single `std::tie` reordering in existing function.

## Risk

Very Low. Easily reversible. Can be A/B tested with flag.

## Dependencies

O7 (done) — `isLSRCostLess` already exists, this is a tuning change.
