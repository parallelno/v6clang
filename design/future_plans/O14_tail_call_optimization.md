# O14. Tail Call Optimization (CALL+RET → JMP)

*Inspired by llvm-mos `MOSLateOptimization::tailJMP`.*
*Detailed analysis: [llvm_mos_analysis.md](llvm_mos_analysis.md) §S9.*

## Problem

When a function's last action is a CALL followed by RET, both instructions
can be replaced by a single JMP — the called function's RET will return
directly to the original caller.

## Before → After

```asm
; Before                          ; After
CALL  target     ; 18cc, 3B      JMP  target      ; 12cc, 3B
RET              ; 12cc, 1B
; Total: 30cc, 4B                 ; Total: 12cc, 3B
```

## Implementation

Post-RA peephole: scan each basic block for `CALL target; RET` at the end.
Replace both with `JMP target`. Must verify no stack cleanup is needed
between the CALL and RET (no local frame to deallocate).

## Benefit

- **Savings per instance**: 18cc + 1 byte
- **Frequency**: Common in wrapper functions, dispatch patterns, and at `-O2`
  where inlining creates short call-through functions
- **Additional benefit**: Reduces stack depth, preventing overflow in deep
  call chains

## Complexity

Very Low. ~15 lines in peephole pass.

## Risk

Very Low. Well-understood optimization. Must not apply when there's frame
cleanup (epilogue) between CALL and RET — but V6CLANG already emits epilogue
before the CALL in such cases.
