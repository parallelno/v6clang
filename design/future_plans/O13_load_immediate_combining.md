# O13. Load-Immediate Combining (Register Value Tracking)

*Inspired by llvm-mos `MOSLateOptimization::combineLdImm`.*
*Detailed analysis: [llvm_mos_analysis.md](llvm_mos_analysis.md) §S4.*

## Problem

After pseudo expansion, the emitted code often contains redundant `MVI r, imm`
instructions where another register already holds the needed value, or where
the target register already holds `imm ± 1`.

## How llvm-mos Does It

Forward scan through each basic block tracking the known constant value in
each register (A, X, Y). When a load-immediate is encountered:
1. If another register holds the same value → replace with register transfer
2. If a register holds value ± 1 → replace with INX/DEX/INY/DEY
3. Track transfers (TAX, TAY) to propagate known values across registers

## V6CLANG Adaptation

Track known values in all 7 registers (A, B, C, D, E, H, L). Replacements:
- `MVI r, imm` → `MOV r, r'` when r' holds imm (saves 1 byte, same 8cc)
- `MVI r, imm` → `INR r` or `DCR r` when r holds imm±1 (saves 4cc + 1 byte)
- `MVI r, 0` → `MOV r, known_zero_reg` (extremely common for zext hi-byte)

## Before → After

```asm
; Before                          ; After
MVI  E, 0       ;  8cc, 2B       MVI  E, 0       ;  8cc, 2B  (first occurrence)
MOV  B, E        ;  8cc, 1B       MOV  B, E        ;  8cc, 1B
...
MVI  H, 0       ;  8cc, 2B  ←    MOV  H, E        ;  8cc, 1B  (E still 0)
```

## Benefit

- **Savings per instance**: 1 byte per MVI→MOV; 4cc+1B per MVI→INR/DCR
- **Frequency**: High — zero-byte materialization is extremely common
- **Test case**: Saves 2 bytes in the reference test (two `MVI 0` → `MOV r, E`)

## Complexity

Low. ~60 lines. Single-BB forward scan, no inter-BB analysis needed.

## Risk

Very Low. Only replaces when register value is provably known. Invalidates
tracking when a register is modified by a non-immediate instruction.
