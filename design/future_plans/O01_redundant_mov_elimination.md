# O1. Redundant MOV Elimination after BUILD_PAIR + ADD16

## Problem

`V6CLANG_ADD16` expansion emits `MOV A, LhsLo` unconditionally. When the
preceding `V6CLANG_BUILD_PAIR` just did `MOV L, A`, the accumulator already
holds the value. The resulting `MOV A, L` is a no-op.

## Before → After

```asm
; Before                          ; After
MOV  H, E      ;  8cc            MOV  H, E      ;  8cc
MOV  L, A      ;  8cc            MOV  L, A      ;  8cc
MOV  A, L      ;  8cc  ← dead    ADD  C         ;  4cc
ADD  C          ;  4cc            MOV  C, A      ;  8cc
MOV  C, A       ;  8cc           ...
```

## Implementation

Extend `V6ClangPeephole::eliminateRedundantMov()` to catch the pattern:
`MOV dst, A` followed (with no A/dst clobber in between) by `MOV A, dst`
→ remove the second MOV.

The existing peephole already handles `MOV A, X; MOV A, X` (duplicate
loads into A). This extends it to the symmetric `MOV X, A; ... MOV A, X`
case when neither A nor X is modified between them.

## Benefit

- **Savings per instance**: 8cc, 1 instruction, 1 byte
- **Frequency**: Very common — every `zext i8 → i16` + `add i16` pair
- **Test case savings**: 16cc (two instances)

## Complexity

Low. ~20 lines added to the existing peephole pass. Pattern is local
(within a basic block, bounded scan window).

## Risk

Low. Only removes provably redundant copies. The existing `eliminateRedundantMov`
infrastructure already handles the safety checks (no clobber between).
