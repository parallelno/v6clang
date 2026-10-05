# O56. Pre-RA Load Folding (optimizeLoadInstr)

*Inspired by jacobly0 `Z80MachinePreRAOptimization`.*
*Detailed analysis: [llvm_z80_analysis.md](llvm_z80_analysis.md) §S3.*

## Rejected
Verdict: Plan is obsolete. The optimization it describes is already delivered by O49 (Direct Memory ALU ISel), which is fully implemented and runs at ISel time — exactly catching the patterns O56 targeted.

## Problem

After instruction selection, some load instructions have a single use that
could consume the loaded value directly from memory instead of going through
a register. Folding the load into its consumer eliminates the load instruction
and frees the register it would have occupied.

On the Z80, `LD r, (HL)` + `ADD A, r` can become `ADD A, (HL)` — folding
the load into the ALU consumer. This is exactly the same concept as O49's
M-operand ISel, but applied pre-RA on already-selected instructions.

## How jacobly0 Does It

A pre-RA `MachineFunctionPass` (~60 lines):

1. Scan each basic block for loads marked `canFoldAsLoad()`
2. For each load with a single use, call `TII.optimizeLoadInstr()` to attempt
   folding the load into the consumer
3. If successful, delete the load and update the consumer

## V6CLANG Adaptation

Implement `V6ClangInstrInfo::optimizeLoadInstr()` to fold memory loads into
their consumers when the consumer has an M-operand variant:

| Load + Consumer | Folded Form |
|----------------|-------------|
| `MOV r, M` + `ADD A, r` | `ADD M` |
| `MOV r, M` + `SUB r` | `SUB M` |
| `MOV r, M` + `ANA r` | `ANA M` |
| `MOV r, M` + `ORA r` | `ORA M` |
| `MOV r, M` + `XRA r` | `XRA M` |
| `MOV r, M` + `CMP r` | `CMP M` |

The load must have exactly one use, and HL must still point to the correct
address at the consumer.

```cpp
MachineInstr *V6ClangInstrInfo::optimizeLoadInstr(MachineInstr &MI,
    const MachineRegisterInfo *MRI, Register &FoldAsLoadDefReg,
    MachineInstr *&DefMI) const {
  // Check if MI is a MOV r, M with single use
  // Find the consumer and check for M-operand variant
  // Return the folded instruction or nullptr
}
```

## Before → After

```asm
; Before                    ; After
MOV  C, M    ;  8cc, 1B    ADD  M       ;  8cc, 1B
ADD  C       ;  4cc, 1B
; Total: 12cc, 2B           ; Total:  8cc, 1B
```

## Benefit

- **Savings per instance**: 4cc + 1B per folded load
- **Frequency**: Low-Medium — depends on how often loads feed directly into
  ALU. Partially covered by O49 at ISel time; this catches cases O49 misses.
- **Register benefit**: Frees one register, reducing spill pressure

## Complexity

Medium. ~60 lines for the pass + ~40 lines for `optimizeLoadInstr()` in
`V6ClangInstrInfo`. Must verify HL is still valid at the consumer.

## Risk

Low. Only folds single-use loads where the M-operand variant is semantically
identical. HL validity check prevents incorrect folding.

## Dependencies

Partially overlaps with O49 (direct memory ALU ISel). O49 catches patterns
at ISel time; O56 catches patterns that emerge after ISel (from register
allocation preparation, copy insertion, etc.). Both are complementary.
