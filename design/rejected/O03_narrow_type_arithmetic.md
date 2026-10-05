# O3. Narrow-Type Arithmetic (i8 Chain Instead of i16)

## Resolution
Already implemented.

## Problem

The LLVM IR frontend emits `zext i8 → i16` before every arithmetic
operation, even when all operands are `i8` and the result only needs
widening at the final use (e.g., return value). This forces the backend
to generate 16-bit add chains (6 instructions, ~40cc each) when a single
8-bit `ADD r` (4cc) would suffice.

## Before → After (Ideal)

```asm
; Before (current: 3 zext + 2 ADD16)  ; After (narrow chain + 1 zext)
LXI  HL, 0                            LXI  HL, 0       ; 10cc
MOV  A, M                             MOV  A, M         ;  8cc
MVI  E, 0                             INX  HL           ;  6cc
MOV  B, E                             ADD  M            ;  8cc  ← 8-bit add
MOV  C, A                             INX  HL           ;  6cc
LXI  HL, 1                            ADD  M            ;  8cc  ← 8-bit add
MOV  A, M                             MOV  L, A         ;  8cc
MOV  H, E                             MVI  H, 0         ;  8cc  ← single zext
MOV  L, A                             RET               ; 12cc
MOV  A, L                             ; Total: 74cc
ADD  C
MOV  C, A
MOV  A, H
ADC  B
MOV  B, A
LXI  HL, 2
MOV  A, M
MOV  H, E
MOV  L, A
DAD  BC
RET
; Total: 174cc
```

## Implementation

**Approach: Custom DAGCombine to sink `zext` past `add`.**

In `V6ClangISelLowering::PerformDAGCombine`, match the pattern:
```
(add (zext i8:$a), (zext i8:$b))  →  (zext (add i8:$a, i8:$b))
```

This is valid when the `add` has `nuw` (no unsigned wrap) or when the
result is only used in further additions/stores (not in comparisons that
depend on the full 16-bit range). For the general case, it's valid when
the wider add has `nuw nsw` flags (which Clang emits for small unsigned
values).

Upstream LLVM has `ReduceWidth` and `TruncInstCombine` passes but they
operate on LLVM IR and often miss target-specific opportunities. A
DAGCombine is more reliable for the V6CLANG case.

## Benefit

- **Savings**: Replaces 16-bit arithmetic (6 insns, ~40cc) with 8-bit
  (1 insn, 4-8cc) per operation. Eliminates intermediate `zext` materialization.
- **Frequency**: Extremely common in `uint8_t` array processing, character
  manipulation, sensor data aggregation.
- **Test case savings**: ~100cc (from 174cc to ~74cc)

## Complexity

High. Requires careful handling of:
- `nuw`/`nsw` flag propagation
- Multi-use values (if a zext result is used elsewhere, can't eliminate it)
- Carry semantics (8-bit add wraps at 256, 16-bit doesn't)
- Interaction with existing BUILD_PAIR / ADD16 patterns

## Risk

Medium-high. Incorrect narrowing can silently produce wrong results for
values that overflow 8 bits. Needs extensive test coverage with boundary
values (127, 128, 255, 256).
