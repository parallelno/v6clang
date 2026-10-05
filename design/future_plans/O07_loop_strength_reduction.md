# O7. Loop Strength Reduction via TargetTransformInfo

## Problem

The V6CLANG backend generates `base + i` address recomputation on every loop
iteration instead of maintaining and incrementing a pointer. For a simple
array copy:

```c
for (uint8_t i = 0; i < 100; i++)
    array2[i] = array1[i];
```

Each `base + i` costs at minimum 24cc (`LXI` + `DAD`). With two arrays, the
loop body pays ~48cc for address computation alone, plus ~100cc+ of spill
overhead to manage intermediate values.

## Before → After

```asm
; Before (per iteration)               ; After (per iteration)
LXI  HL, array1     ; 12cc            MOV  A, M          ;  8cc  load via HL
; ... extend i to 16-bit ...           XCHG                ;  4cc
DAD  HL              ; 12cc            MOV  M, A          ;  8cc  store via HL (was DE)
MOV  A, M            ;  8cc            XCHG                ;  4cc
; ... spill, reload, recompute ...     INX  HL            ;  8cc  advance ptr1
LXI  HL, array2     ; 12cc            INX  DE            ;  8cc  advance ptr2
; ... extend i again ...               ; ... compare & branch ...
DAD  HL              ; 12cc
MOV  M, A            ;  8cc
; ~200cc+ with spills                  ; ~40cc
```

## Root Cause

LLVM has a built-in Loop Strength Reduction pass (`-loop-reduce`), but it
makes cost decisions through `TargetTransformInfo` (TTI) hooks. V6CLANG has
**no TTI implementation** — it falls back to defaults that assume reg+reg
addressing is free and the target has 32-bit registers. These defaults prevent
LSR from making correct transformations for the 8080.

## Implementation

Implement `V6ClangTargetTransformInfo` class with key hooks:

| Hook | V6CLANG Value |
|------|-----------|
| `isLegalAddressingMode()` | Only reg indirect, no offset |
| `getAddressComputationCost()` | Non-zero (initial: 2) |
| `getNumberOfRegisters()` | 3 (register pairs) |
| `getRegisterBitWidth()` | 16 bits |
| `isNumRegsMajorCostOfLSR()` | `true` |
| `isLSRCostLess()` | Prioritize fewer regs over fewer insns |

This teaches LLVM's existing LSR pass about the 8080's constraints without
writing a custom loop optimization pass.

**Detailed plan**: [plan_loop_strength_reduction.md](../plan_loop_strength_reduction.md)

## Benefit

- **Savings per iteration**: ~120-160cc for dual-array loops
- **Frequency**: Every loop with array/pointer indexing
- **Loop body speedup**: ~3-7× depending on spill pressure

## Complexity

Medium. Creates 4 new files (header, cpp, CMake addition, target machine
registration). The logic is declarative cost tuning, not a new pass.

## Risk

Medium. Incorrect cost parameters can cause LSR to make worse decisions
(e.g., using too many pointers → more spills). Requires tuning with
representative benchmarks (Step 3.9 in plan).
