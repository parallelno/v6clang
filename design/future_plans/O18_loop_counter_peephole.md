# O18. Loop Counter DEC+Branch Peephole

*Inspired by llvm-z80 `Z80LateOptimization` dec-and-branch peephole and
`Z80ExpandPseudo` DJNZ expansion.*
*Detailed analysis: [llvm_z80_analysis.md](llvm_z80_analysis.md) §S8.*

## Problem

V6CLANG emits a 5-instruction sequence for "decrement counter and branch if
nonzero" because the accumulator is required for both `DCR` (which doesn't
set all flags on all registers) and the branch test:

```asm
MOV  A, B        ;  8cc   load counter into A
DCR  A           ;  4cc   decrement
MOV  B, A        ;  8cc   store back
ORA  A           ;  4cc   set flags
JNZ  loop        ; 12cc   branch if nonzero
; Total: 36cc, 6B
```

The 8080's `DCR r` instruction sets the Z flag directly for any register r.
The entire 5-instruction sequence can be replaced with:

```asm
DCR  B           ;  8cc   decrement B, sets Z flag
JNZ  loop        ; 12cc   branch if nonzero
; Total: 16cc, 2B
```

## Implementation

Post-RA peephole: match the 5-instruction template `MOV A,r; DCR A; MOV r,A;
ORA A; JNZ target` and replace with `DCR r; JNZ target`. Preconditions:
1. A must be dead after the sequence (not used before next definition)
2. No intervening instructions between the 5

## Benefit

- **Savings per instance**: 20cc + 4 bytes per loop iteration
- **Frequency**: Very high — this is the standard loop counter pattern
- **Compound**: Loop iterations × savings → massive in tight loops

## Complexity

Low. ~40 lines. Pattern matching on 5 consecutive instructions with a
register liveness check.

## Risk

Very Low. `DCR r` and `JNZ` have identical semantics to the expanded sequence.
Only applies when A is dead after (checked by forward scan to next A def/use).
