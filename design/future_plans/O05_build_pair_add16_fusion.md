# O5. BUILD_PAIR(x, 0) + ADD16 Fusion

## Problem

Zero-extending `i8` to `i16` generates `BUILD_PAIR(val, 0)` which becomes
`MOV hi, 0; MOV lo, val`. The subsequent `ADD16` then does a full 6-instruction
chain including `ADC hi` which is just `ADC 0` (carry propagation only).

## Before → After

```asm
; Before (BUILD_PAIR + ADD16)     ; After (fused)
MOV  H, E      ;  8cc (H = 0)    ADD  C         ;  4cc
MOV  L, A      ;  8cc             MOV  C, A      ;  8cc
MOV  A, L      ;  8cc             MOV  A, B      ;  8cc
ADD  C          ;  4cc             ACI  0         ;  8cc  (or ADC E if E==0)
MOV  C, A       ;  8cc            MOV  B, A      ;  8cc
MOV  A, H       ;  8cc            ; Total: 36cc
ADC  B          ;  4cc
MOV  B, A       ;  8cc
; Total: 56cc
```

Or better, when the high byte of one operand is known-zero:
```asm
ADD  C          ;  4cc            ; low add
MOV  C, A       ;  8cc
MVI  A, 0       ;  8cc            ; high = 0 + B + carry
ADC  B          ;  4cc
MOV  B, A       ;  8cc
; Total: 32cc
```

## Implementation

In `expandPostRAPseudo` for `V6CLANG_ADD16`, detect when one operand's high
sub-register was defined by `MVI reg, 0` (scan backward, similar to
`findDefiningLXI`). If so, emit a shorter sequence that skips the high
byte load (use `MVI A, 0; ADC hi` instead of `MOV A, hi; ADC hi`).

## Benefit

- **Savings per instance**: 16-24cc
- **Frequency**: Every `zext i8 → i16` followed by 16-bit arithmetic
- **Test case savings**: ~32cc

## Complexity

Medium. Similar to the existing INX/DCX constant detection. ~30 lines
in the ADD16 expansion.

## Risk

Low-medium. Must correctly identify the zero high byte. False positives
if the MVI 0 was overwritten. Use same TRI-aware scanning as the
`findDefiningLXI` fix.
