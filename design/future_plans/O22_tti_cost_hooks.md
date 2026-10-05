# O22. TTI Cost Hooks Expansion

*From plan_loop_strength_reduction.md Future Enhancements.*
*Extension of O7 (TTI for Loop Strength Reduction) with additional cost hooks.*

## Problem

O7 implemented `isLegalAddressingMode()` and LSR cost functions, enabling
LLVM's Loop Strength Reduction pass. However, other LLVM IR-level passes
(loop unroller, SLP vectorizer, cost-based inliner) still use default TTI
costs, which assume a modern RISC architecture with cheap 32-bit ops.

On the 8080:
- 16-bit arithmetic costs 3-10× more than 8-bit
- Memory access always requires HL setup (no indexed addressing)
- 16-bit comparisons expand to multi-instruction sequences
- There are no scaled addressing modes

Without accurate costs, LLVM may:
- Unroll loops too aggressively (creating register pressure)
- Fail to unroll small loops where it would help
- Inline functions that cause massive spilling

## Implementation

Add TTI hooks in `V6ClangTargetTransformInfo.h/.cpp`:

### getArithmeticInstrCost()
```cpp
InstructionCost getArithmeticInstrCost(unsigned Opcode, Type *Ty, ...) {
  if (Ty->isIntegerTy(8))
    return 1;   // 8-bit ALU: 4-8cc
  if (Ty->isIntegerTy(16))
    return 6;   // 16-bit ALU: 24-48cc (multi-instruction)
  if (Ty->isIntegerTy(32))
    return 20;  // 32-bit ALU: libcall overhead
  return BaseT::getArithmeticInstrCost(Opcode, Ty, ...);
}
```

### getMemoryOpCost()
```cpp
InstructionCost getMemoryOpCost(unsigned Opcode, Type *Src, ...) {
  // All memory ops require HL setup — no free addressing modes
  if (Src->isIntegerTy(8))
    return 2;   // LXI + MOV M/MOV r,M
  if (Src->isIntegerTy(16))
    return 4;   // LXI + 2×MOV + INX
  return BaseT::getMemoryOpCost(Opcode, Src, ...);
}
```

### getCmpSelInstrCost()
```cpp
InstructionCost getCmpSelInstrCost(unsigned Opcode, Type *ValTy, ...) {
  if (ValTy->isIntegerTy(8))
    return 1;   // CMP r: 4cc
  if (ValTy->isIntegerTy(16))
    return 4;   // MVI+CMP+JNZ+MVI+CMP: ~40cc
  return BaseT::getCmpSelInstrCost(Opcode, ValTy, ...);
}
```

### getScalingFactorCost()
```cpp
InstructionCost getScalingFactorCost(Type *Ty, GlobalValue *BaseGV,
                                     StackOffset BaseOffset,
                                     bool HasBaseReg, int64_t Scale, ...) {
  // No scaled addressing modes on 8080
  if (Scale != 0 && Scale != 1)
    return InstructionCost::getInvalid();  // illegal
  return 0;
}
```

## Benefit

- **Primary**: Better loop unrolling decisions — stops over-unrolling
  tight loops (which causes massive register spilling on 8080)
- **Secondary**: More accurate inlining heuristics — prevents inlining
  of functions that would blow the register file
- **Tertiary**: Correct cost model for any future LLVM pass that
  queries TTI

## Complexity

Low-Medium. ~50-80 lines. Each hook is straightforward — just returning
appropriate cost constants. Requires understanding of how LLVM IR passes
use these costs.

## Risk

Low for correctness — these are cost hints, wrong values produce
suboptimal code, not incorrect code. **However, the regression risk is
real**: changing TTI costs perturbs the input IR seen by every
downstream codegen pass (unroller, inliner, SLP, LSR, IR-level CSE/LICM
trade-offs). On a small target like i8080 a single bad cost choice can
shift the regression corpus by hundreds of bytes in either direction.

### Opt-out flag (mandatory)

Implementation **must** add a hidden `cl::opt` to disable the new hooks
wholesale, mirroring the existing `-v6clang-lsr-strategy` pattern:

```cpp
static cl::opt<bool> EnableV6ClangTTICosts(
    "v6clang-tti-cost-hooks",
    cl::desc("Enable V6CLANG-specific TTI cost hooks (arith/mem/cmp/scaling). "
             "Disable to fall back to BasicTTI defaults."),
    cl::init(true), cl::Hidden);
```

Each hook checks the flag first and falls back to `BaseT::...` when off.
This lets us:

1. Bisect regressions per-function via `-mllvm -v6clang-tti-cost-hooks=0`.
2. Disable globally if a corpus-wide regression is found late.
3. A/B compare on the regression suite without rebuilding.

Consider also per-hook flags
(`-v6clang-tti-cost-arith`, `-v6clang-tti-cost-mem`, `-v6clang-tti-cost-cmp`,
`-v6clang-tti-cost-scaling`) so individual hooks can be toggled when
narrowing down a regression.

## Dependencies

O7 (TTI infrastructure) — already complete. This extends it.

## Testing

1. Existing golden tests for regression
2. Manual inspection of loop unrolling decisions with `-debug-pass=Structure`
3. Compare code size with/without hooks on real programs
