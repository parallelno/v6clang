# O52. Index Induction Variable Rewriting (8-bit Loop Indices)

## Resolution
"superseded by V6ClangLoopPointerInduction." The optimization is not needed and implementing it would provide zero measurable benefit on any testable case.

*Inspired by llvm-mos `MOSIndexIV`.*
*Detailed analysis: [llvm_mos_analysis.md](llvm_mos_analysis.md) §S2.*

## Problem

C code commonly uses `int` (i16 on 8080) loop counters even when the loop
count fits in 8 bits:

```c
for (int i = 0; i < 100; i++)
    array[i] = 0;
```

On the 8080, a 16-bit loop counter decrement costs ~18cc (DCX pair + MOV A,L;
ORA H; JNZ pattern), while an 8-bit decrement is just `DCR r` (4cc) + `JNZ`
(12cc). The savings per iteration are 14cc+ — significant in tight loops.

## How llvm-mos Does It

An IR-level loop pass (`MOSIndexIV`) using SCEV analysis:

1. For each GEP in a loop, check if the index SCEV is an `SCEVAddRecExpr`
2. Verify both the step and the full index range fit in `[0, 255]`
3. Rewrite `GEP base, index_i16` → `GEP base, zext(index_i8)`
4. Insert a `trunc` for the narrow index and `zext` for the GEP
5. Run before `IndVarSimplify` to let LLVM simplify the new forms

The pass is nearly target-independent — only the address space check and
data layout differ.

## V6CLANG Adaptation

Register the pass via `registerLateLoopOptimizationsEPCallback` in
`V6ClangTargetMachine.cpp`. The core logic is:

```cpp
for (Loop *L : LPM) {
  for (auto &BB : L->blocks()) {
    for (auto &I : *BB) {
      if (auto *GEP = dyn_cast<GetElementPtrInst>(&I)) {
        // Check index SCEV fits in [0, 255]
        const SCEV *IdxSCEV = SE.getSCEV(GEP->getOperand(1));
        if (auto *AR = dyn_cast<SCEVAddRecExpr>(IdxSCEV)) {
          ConstantRange Range = SE.getUnsignedRange(AR);
          if (Range.getUnsignedMax().ule(255)) {
            // Rewrite to i8 index + zext
          }
        }
      }
    }
  }
}
```

## Before → After

```asm
; Before (i16 counter)        ; After (i8 counter)
loop:                          loop:
  ; ... body ...                 ; ... body ...
  DCX  DE      ;  8cc           DCR  E       ;  4cc
  MOV  A, E    ;  8cc           JNZ  loop    ; 12cc
  ORA  D       ;  4cc           ; Total: 16cc/iter
  JNZ  loop    ; 12cc
  ; Total: 32cc/iter
```

## Benefit

- **Savings per instance**: 14-16cc per loop iteration
- **Frequency**: High — most `for` loops in embedded code iterate < 256 times
- **Additional benefit**: Frees a register pair (DE or BC) for other uses,
  reducing spill pressure inside the loop

## Complexity

Low. ~80 lines. IR-level pass, nearly target-independent using SCEV.

## Risk

Low. Only rewrites when SCEV proves range fits in 8 bits. The `zext` ensures
correctness for GEP addressing.

## Dependencies

Complements O7 (TTI for LSR) — IndexIV narrows the index; LSR then
optimizes the pointer arithmetic. Independent of post-RA optimizations.
