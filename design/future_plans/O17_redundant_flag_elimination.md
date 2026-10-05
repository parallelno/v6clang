# O17. Redundant Flag-Setting Elimination (Post-RA)

*Inspired by llvm-z80 `Z80PostRACompareMerge`.*
*Detailed analysis: [llvm_z80_analysis.md](llvm_z80_analysis.md) §S7.*

## Problem

The V6CLANG backend frequently emits `ORA A` (or `ANA A`) before conditional
branches to set the zero flag, even when the preceding ALU instruction
already set the flags correctly.

```asm
XRA  E          ; sets Z flag (A = A XOR E)
ORA  A          ; redundant — Z already reflects A's value
JZ   .label
```

V6CLANG's `V6ClangEliminateZeroTest` pass handles the `ZERO_TEST` pseudo, but this
is limited to specific patterns at pseudo expansion time. Post-RA code may
have additional redundant flag-setting instructions that are missed.

## Implementation

Post-RA `MachineFunctionPass`: forward scan through each basic block tracking
whether the Z flag is "valid for A" (set by an instruction that both defines
FLAGS and operates on A):

1. On any ALU instruction that defines FLAGS and A (ADD, ADC, SUB, SBB, ANA,
   ORA, XRA, CMP, CPI): mark `ZFlagValid = true`
2. On `ORA A` or `ANA A` when `ZFlagValid`: erase the instruction
3. On any instruction that modifies A without setting flags (MOV A,r, MVI A,
   LDA, etc.): mark `ZFlagValid = false`
4. On call, return, branch, or pseudo: mark `ZFlagValid = false`

## Before → After

```asm
; Before                    ; After
ANA  D       ;  4cc         ANA  D       ;  4cc
ORA  A       ;  4cc  ←del
JZ   label   ; 12cc         JZ   label   ; 12cc
```

## Benefit

- **Savings per instance**: 4cc + 1 byte
- **Frequency**: Medium-high — occurs after comparison expansions, loop
  condition checks, and any conditional branch based on an ALU result

## Complexity

Low. ~50 lines. Simple forward scan, no inter-BB analysis needed.

## Risk

Very Low. The Z flag semantics are well-defined for all affected instructions.
Only erases when provably redundant.
