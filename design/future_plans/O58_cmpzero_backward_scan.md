# O58. CmpZero Backward Scan Enhancement

## Rejected
**it's already done**
The optimization is no longer valid as a separate plan — it's already implemented in V6ClangRedundantFlagElim.cpp.


*Inspired by llvm-mos `MOSLateOptimization::lowerCmpZeros`.*
*Detailed analysis: [llvm_mos_analysis.md](llvm_mos_analysis.md) §S5.*

## Problem

V6CLANG's existing `V6ClangEliminateZeroTest` pass (O17) eliminates redundant
`ORA A` instructions when the preceding ALU instruction already set the
zero flag. However, it stops at the first potentially flag-affecting
instruction — it cannot "see through" intervening instructions that don't
affect flags.

```asm
ADD  B          ; sets Z flag correctly
MOV  D, A       ; does NOT affect flags — but O17 may stop here
ORA  A          ; redundant, but not eliminated
JZ   label
```

The llvm-mos approach scans backward past **known-safe instructions** (those
that provably don't affect flags), finding flag-setting instructions that are
further back in the basic block.

## Known-Safe Instructions (Don't Affect Flags)

| Instruction | Flags affected | Safe to skip? |
|-------------|---------------|---------------|
| MOV r, r' | None | Yes |
| MVI r, imm | None | Yes |
| LXI rr, imm | None | Yes |
| PUSH rr | None | Yes |
| POP rr (not PSW) | None | Yes |
| STAX rr | None | Yes |
| LDAX rr | None | Yes |
| LDA addr | None | Yes |
| STA addr | None | Yes |
| LHLD addr | None | Yes |
| SHLD addr | None | Yes |
| XCHG | None | Yes |
| XTHL | None | Yes |
| SPHL | None | Yes |
| PCHL | N/A (control flow) | **No** — terminates scan |
| POP PSW | **Restores flags** | **No** — stops scan |
| INX/DCX rr | None | Yes |
| NOP | None | Yes |

## Implementation

Extend the backward scan in the redundant flag elimination pass:

```cpp
bool canSkipForFlagScan(const MachineInstr &MI) {
  switch (MI.getOpcode()) {
  case V6CLANG::MOV_rr: case V6CLANG::MVI: case V6CLANG::LXI:
  case V6CLANG::PUSH_BC: case V6CLANG::PUSH_DE: case V6CLANG::PUSH_HL:
  case V6CLANG::POP_BC: case V6CLANG::POP_DE: case V6CLANG::POP_HL:
  case V6CLANG::STAX_BC: case V6CLANG::STAX_DE:
  case V6CLANG::LDAX_BC: case V6CLANG::LDAX_DE:
  case V6CLANG::LDA: case V6CLANG::STA:
  case V6CLANG::LHLD: case V6CLANG::SHLD:
  case V6CLANG::XCHG: case V6CLANG::XTHL: case V6CLANG::SPHL:
  case V6CLANG::INX: case V6CLANG::DCX: case V6CLANG::NOP:
    return true;
  default:
    return false;
  }
}

// In flag elimination pass:
// Instead of checking only the immediately preceding instruction,
// scan backward past safe instructions until finding a flag-setter or
// an unsafe instruction.
MachineBasicBlock::iterator Scan = std::prev(ORA_iter);
while (Scan != MBB.begin() && canSkipForFlagScan(*Scan)) {
  --Scan;
}
if (setsFlagsForA(*Scan)) {
  // ORA A is redundant — delete it
}
```

## Before → After

```asm
; Before                        ; After
ADD  B          ;  4cc          ADD  B          ;  4cc
MOV  D, A       ;  8cc          MOV  D, A       ;  8cc
LXI  HL, 1234  ; 12cc          LXI  HL, 1234  ; 12cc
ORA  A          ;  4cc, 1B     JZ   label      ; 12cc
JZ   label      ; 12cc         ; (ORA A deleted — ADD B set flags,
                                ;  MOV and LXI don't affect them)
```

## Benefit

- **Savings per instance**: 4cc + 1B per eliminated `ORA A`
- **Frequency**: Medium — depends on how often non-flag instructions
  intervene between flag-setter and conditional branch
- **Incremental over O17**: Catches cases where 1-3 safe instructions
  separate the flag-setter from the compare-zero

## Complexity

Low. ~30 lines extending the existing O17 backward scan. The
`canSkipForFlagScan` whitelist is straightforward from the ISA manual.

## Risk

Very Low. Conservative whitelist — only skips instructions that provably
don't touch flags. Any unknown instruction stops the scan. Must also verify
that A is not modified between the flag-setter and the `ORA A` (the flag
must still reflect A's current value).

## Dependencies

O17 (done) — extends the existing redundant flag elimination pass.
Benefits from O53 (enhanced value tracking) for more precise flag state.
