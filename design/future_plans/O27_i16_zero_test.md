# O27. i16 Zero-Test Optimization

*Identified from analysis of temp/compare/07/v6clang.c output.*
*Replaces full CMP-based 16-bit zero comparison with `MOV A, Hi; ORA Lo`.*

## Problem

The most common i16 comparison in C is testing against zero: `if (x)`,
`if (!ptr)`, `while (n)`, etc. Currently, `V6CLANG_BR_CC16_IMM` with RHS=0
generates a full two-byte CMP expansion with MBB splitting:

### Current output (comparing i16 HL against 0, EQ):
```asm
; BB0:
    MVI  A, 0           ; 7cc, 2B — lo8(0) = 0
    CMP  L              ; 4cc, 1B
    JNZ  .Lhi_cmp       ; 10cc, 3B — early-exit to second block
; BB1 (CompareHiMBB):
    MVI  A, 0           ; 7cc, 2B — hi8(0) = 0
    CMP  H              ; 4cc, 1B
    JZ   Target         ; 10cc, 3B
    JMP  Fallthrough    ; 10cc, 3B — explicit JMP for analyzeBranch
; Total: 42cc worst-case, 15B (+ MBB split overhead)
```

This has multiple problems:
1. **12 bytes** of comparison code for a trivial zero test
2. **MBB split** required — creates a new basic block, disrupts layout
3. **A register clobbered** with `MVI A, 0` — prevents use of A for other
   purposes
4. **HL not preserved** — when comparing and HL holds the value, subsequent
   code that needs the value must save/restore through DE (adds 2 MOVs)

### Optimal output:
```asm
    MOV  A, H           ; 4cc, 1B
    ORA  L              ; 4cc, 1B — A = H | L, Z set iff HL == 0
    JZ   Target         ; 10cc, 3B (or JNZ for NE)
; Total: 18cc, 5B, NO MBB split, HL preserved
```

The `ORA` instruction ORs the two bytes together: the result is zero if and
only if both bytes are zero. The Z flag is set accordingly. This is a
well-known 8080 idiom for 16-bit zero testing.

## Savings

| Metric | Current (BR_CC16_IMM, RHS=0) | After O27 | Savings |
|--------|------------------------------|-----------|---------|
| Bytes | 15B (both blocks) | 5B | **10B (67%)** |
| Cycles | 42cc worst-case | 18cc | **24cc (57%)** |
| MBB splits | 1 new block | 0 | **1 block** |
| Registers clobbered | A (via MVI) | A (via MOV) | HL preserved |

### Cascade savings (indirect)

Because O27 preserves HL and avoids the MBB split:
- **No DE save/restore**: When the compared value is needed after the branch
  (e.g., `if (x) return bar(x)`), HL stays intact. Currently the compiler
  moves HL→DE before the LXI/comparison, then DE→HL afterward. O27 saves
  an additional **2-4 MOVs (8-16cc, 2-4B)** in these cases.
- **Branch inversion enabled**: Single-block code allows V6ClangBranchOpt's
  Jcc+JMP inversion to fire (see O28), potentially saving another 3B+10cc.

### Real-world example: `if (x) return bar(x); return 0;`

| Version | Code | Size |
|---------|------|------|
| Current | MOV D,H; MOV E,L; LXI HL,0; MVI A,0; CMP E; JNZ .L1; MVI A,0; CMP D; JZ .L2; .L1: MOV H,D; MOV L,E; JMP bar; .L2: RET | 22B |
| After O27+O28 | MOV A,H; ORA L; JNZ bar; LXI HL,0; RET | **8B** |

## Implementation

### Approach: Special case in `V6CLANG_BR_CC16_IMM` expansion

In `V6ClangInstrInfo.cpp`, `expandPostRAPseudo()` case `V6CLANG::V6CLANG_BR_CC16_IMM`:

1. Before the existing MBB-splitting code, add a check for immediate == 0
2. If `RhsOp.isImm() && RhsOp.getImm() == 0`:
   - Emit `MOV A, LhsHi` + `ORA LhsLo` + `Jcc Target`
   - Do NOT split the MBB — just insert before the pseudo and erase it
3. Fall through to existing code for non-zero immediates

### Pseudocode:
```cpp
case V6CLANG::V6CLANG_BR_CC16_IMM: {
  Register LhsReg = MI.getOperand(0).getReg();
  MachineOperand &RhsOp = MI.getOperand(1);
  int64_t CC = MI.getOperand(2).getImm();
  MachineBasicBlock *Target = MI.getOperand(3).getMBB();

  assert((CC == V6ClangCC::COND_Z || CC == V6ClangCC::COND_NZ) && "EQ/NE only");

  MCRegister LhsLo = RI.getSubReg(LhsReg, V6CLANG::sub_lo);
  MCRegister LhsHi = RI.getSubReg(LhsReg, V6CLANG::sub_hi);

  // --- O27: Fast zero-test path ---
  if (RhsOp.isImm() && RhsOp.getImm() == 0) {
    unsigned JccOpc = (CC == V6ClangCC::COND_Z) ? V6CLANG::JZ : V6CLANG::JNZ;
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::A).addReg(LhsHi);
    BuildMI(MBB, MI, DL, get(V6CLANG::ORAr), V6CLANG::A)
        .addReg(V6CLANG::A).addReg(LhsLo);
    BuildMI(MBB, MI, DL, get(JccOpc)).addMBB(Target);
    MI.eraseFromParent();
    return true;
  }

  // ... existing MBB-splitting code for non-zero immediates ...
}
```

### Key properties:
- **No MBB split**: The three instructions replace the pseudo in place
- **HL preserved**: Only A is modified (MOV A,H copies, ORA modifies A)
- **FLAGS correct**: ORA sets Z flag = (H|L == 0), which is (HL == 0)
- **Single conditional branch**: No early-exit pattern needed

## Testing

### Lit tests:
- `br-cc16-zero.ll`: Test i16 EQ/NE comparison with 0 (both conditions)
- `br-cc16-zero-pattern.ll`: Full C-level patterns (`if (x)`, `if (!x)`,
  `while (x)`)
- Verify that non-zero immediates still use the existing MBB-split path

### Golden test regression:
- All 15 golden tests must pass
- All existing lit tests must pass (no regressions)

### Integration test:
- Compile `temp/compare/07/v6clang.c` and verify output matches expected
  assembly

## Benefit

- **10B + 24cc** per i16 zero comparison (direct savings)
- **2-4B + 8-16cc** additional from preserved HL (indirect savings)
- **Frequency**: Very high — zero tests are the most common i16 comparison
  in C code (null pointer checks, loop conditions, boolean tests)

## Complexity

Low-Medium. ~15 lines added to existing `V6CLANG_BR_CC16_IMM` expansion in
`V6ClangInstrInfo.cpp`. No new pseudo instructions, no new passes, no ISel
changes.

## Risk

Low. The ORA-based zero test is a well-known 8080 idiom. The change is
isolated to one case in `expandPostRAPseudo`. Conservative: only fires
for `isImm() && getImm() == 0`, all other cases use existing code.

## Dependencies

None. This is a standalone improvement to the existing BR_CC16_IMM
expansion.

## Future Enhancements

- **V6CLANG_BR_CC16 (register-register)**: Could also detect when RHS register
  is known to be zero (via O13 value tracking), but this is rare enough to
  defer.
- **SELECT_CC with 0**: Similar optimization for `x ? a : b` when x is i16.
  The SELECT_CC16 expansion could use the same ORA pattern.
