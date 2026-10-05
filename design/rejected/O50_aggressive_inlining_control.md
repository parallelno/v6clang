# O50. Aggressive Inlining Control (TTI Override)

*Inspired by llvm-z80 `Z80TargetTransformInfo::areInlineCompatible()`.*
*Detailed analysis: [llvm_z80_analysis.md](llvm_z80_analysis.md) §S10.*

## Problem

LLVM's default inlining thresholds are tuned for targets with 16-32 GPRs
(x86, ARM). The i8080 has only 3 general-purpose register pairs (BC, DE, HL).
When LLVM inlines a large function into a caller, the combined function has
far more live values than registers available, causing massive spilling.

Each spill/reload on the 8080 costs 52-104cc (SHLD/LHLD or multi-instruction
LXI+DAD SP+MOV sequences). A function with 5 extra spills from aggressive
inlining loses 260-520cc — far more than the 30cc saved by eliminating the
CALL+RET.

## Implementation

Override `areInlineCompatible()` in `V6ClangTargetTransformInfo` to restrict
inlining:

```cpp
bool V6ClangTTIImpl::areInlineCompatible(const Function *Caller,
                                      const Function *Callee) const {
  // Allow explicitly-marked inline functions (inline keyword, always_inline)
  if (Callee->hasFnAttribute(Attribute::InlineHint) ||
      Callee->hasFnAttribute(Attribute::AlwaysInline))
    return true;

  // Allow small functions where call overhead dominates
  if (Callee->getInstructionCount() <= 10)
    return true;

  // Block inlining of large functions to prevent spill explosions
  return false;
}
```

## Before → After

```c
// Caller has 3 live register pairs already
void caller() {
  int a = compute1();
  int b = compute2();
  int c = large_helper(a, b);  // 50-instruction function
  use(a, b, c);
}

// Before (large_helper inlined): 8+ spills in combined body (~400cc overhead)
// After (call preserved): CALL + RET = 30cc, no extra spills
```

## Benefit

- **Savings per instance**: Prevents 200-500cc+ spill overhead per aggressive inline
- **Frequency**: High — LLVM inlines many functions at -O2 by default
- **Code size**: Also reduces code bloat from inlining

## Complexity

Very Low. ~10 lines in `V6ClangTargetTransformInfo.h/.cpp`.

## Risk

Low. Conservative threshold (10 instructions) may miss some beneficial
inlines, but `InlineHint` and `always_inline` attributes provide escape
hatches. The threshold can be tuned or made into a `-mllvm` flag.

## Dependencies

None. Independent of all other optimizations.

## Resolution

Rejected because inlining can be opt out with
```c
__attribute__((noinline))
```