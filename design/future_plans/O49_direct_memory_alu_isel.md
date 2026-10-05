# O49 — Direct Memory ALU/Store ISel Patterns (M-Operand Instructions)

*Supersedes O4 (ADD M / SUB M peephole) and O46 (MVI M ISel).*

## Problem

The 8080 has 11 instructions that operate directly on memory at `[HL]`
without going through a register. The compiler never generates any of them —
all have empty ISel patterns (`[]`) in `V6ClangInstrInfo.td`. Instead, ISel
materializes values into registers and operates on registers.

### All unused M-operand instructions

| Instruction | Opcode | Current codegen | Savings |
|---|---|---|---|
| `ADD M` | 0x86 | `MOV r, M; ADD r` (12cc, 2B) | 4cc, 1B |
| `ADC M` | 0x8E | `MOV r, M; ADC r` (12cc, 2B) | 4cc, 1B |
| `SUB M` | 0x96 | `MOV r, M; SUB r` (12cc, 2B) | 4cc, 1B |
| `SBB M` | 0x9E | `MOV r, M; SBB r` (12cc, 2B) | 4cc, 1B |
| `ANA M` | 0xA6 | `MOV r, M; ANA r` (12cc, 2B) | 4cc, 1B |
| `ORA M` | 0xB6 | `MOV r, M; ORA r` (12cc, 2B) | 4cc, 1B |
| `XRA M` | 0xAE | `MOV r, M; XRA r` (12cc, 2B) | 4cc, 1B |
| `CMP M` | 0xBE | `MOV r, M; CMP r` (12cc, 2B) | 4cc, 1B |
| `MVI M, imm` | 0x36 | `MVI A, imm; MOV M, A` (15cc, 3B) | 5cc, 1B |
| `INR M` | 0x34 | `MOV A, M; INR A; MOV M, A` (20cc, 3B) | 8cc, 2B |
| `DCR M` | 0x35 | `MOV A, M; DCR A; MOV M, A` (20cc, 3B) | 8cc, 2B |

### Example: `multi_live`

```asm
; Current:
LXI   HL, __v6clang_ss.multi_live
MOV   L, M        ; load *HL into L
ADD   L            ; A += L (12cc, 2B)

; With O49:
LXI   HL, __v6clang_ss.multi_live
ADD   M            ; A += *HL directly (8cc, 1B)
```

## Why not a peephole?

A post-RA peephole that detects `MOV r, M; OP r` → `OP M` is fragile:
- Kill flags on the MOV destination can be stale — deleting the MOV when
  the register is still live elsewhere causes silent correctness bugs.
- Cross-BB liveness isn't visible from a local scan.
- The register freed by eliminating the MOV may already have been allocated
  for something else by the RA.

ISel avoids these problems entirely: the load is folded into the ALU
operation at the DAG level, so no intermediate register is ever allocated.

## Solution: ISel pseudos with post-RA expansion

### Step 1 — Define pseudos in `V6ClangInstrInfo.td`

Each M-operand instruction gets a pseudo that takes a virtual `GR16`
address register:

**ALU read group** (ADD, ADC, SUB, SBB, ANA, ORA, XRA):
```tablegen
let mayLoad = 1 in {
  def V6CLANG_ADD_M_P : V6ClangPseudo<(outs Acc:$dst), (ins Acc:$lhs, GR16:$addr),
      "# ADD_M_P ($addr)",
      [(set Acc:$dst, (add Acc:$lhs, (i8 (load i16:$addr))))]>;
  // ... same pattern for ADC, SUB, SBB, ANA, ORA, XRA
}
```

**CMP M:**
```tablegen
let mayLoad = 1 in
def V6CLANG_CMP_M_P : V6ClangPseudo<(outs), (ins Acc:$lhs, GR16:$addr),
    "# CMP_M_P ($addr)",
    [(V6Clangcmp Acc:$lhs, (i8 (load i16:$addr)))]>;
```

**MVI M:**
```tablegen
let mayStore = 1 in
def V6CLANG_STORE8_IMM_P : V6ClangPseudo<(outs), (ins imm8:$imm, GR16:$addr),
    "# STORE8_IMM_P $imm, ($addr)",
    [(store (i8 imm:$imm), i16:$addr)]>;
```

**INR M / DCR M:**
```tablegen
let mayLoad = 1, mayStore = 1 in {
  def V6CLANG_INR_M_P : V6ClangPseudo<(outs), (ins GR16:$addr),
      "# INR_M_P ($addr)",
      [(store (add (i8 (load i16:$addr)), 1), i16:$addr)]>;
  def V6CLANG_DCR_M_P : V6ClangPseudo<(outs), (ins GR16:$addr),
      "# DCR_M_P ($addr)",
      [(store (add (i8 (load i16:$addr)), -1), i16:$addr)]>;
}
```

### Step 2 — Shared expansion helper

One function handles all 11 pseudos:

```cpp
/// Expand a pseudo that needs HL as pointer for an M-operand instruction.
/// Emits XCHG wrapper for DE, MOV L,C; MOV H,B for BC.
/// HL preservation (PUSH/POP) is handled by the scavenger (O48),
/// NOT by this function.
static bool expandMemOpM(MachineBasicBlock &MBB, MachineInstr &MI,
                         const V6ClangInstrInfo &TII, unsigned MOpcode,
                         Register AddrReg) {
  DebugLoc DL = MI.getDebugLoc();
  if (AddrReg == V6CLANG::HL) {
    // Direct
    BuildMI(MBB, MI, DL, TII.get(MOpcode));
  } else if (AddrReg == V6CLANG::DE) {
    // XCHG; OP M; XCHG — 8cc + 2B overhead
    BuildMI(MBB, MI, DL, TII.get(V6CLANG::XCHG));
    BuildMI(MBB, MI, DL, TII.get(MOpcode));
    BuildMI(MBB, MI, DL, TII.get(V6CLANG::XCHG));
  } else {
    // BC — no swap instruction. MOV L,C; MOV H,B; OP M
    // HL preservation is the scavenger's responsibility (O48).
    BuildMI(MBB, MI, DL, TII.get(V6CLANG::MOVrr), V6CLANG::L).addReg(V6CLANG::C);
    BuildMI(MBB, MI, DL, TII.get(V6CLANG::MOVrr), V6CLANG::H).addReg(V6CLANG::B);
    BuildMI(MBB, MI, DL, TII.get(MOpcode));
  }
  MI.eraseFromParent();
  return true;
}
```

Each pseudo's `expandPostRAPseudo` case is a one-liner:

```cpp
case V6CLANG::V6CLANG_ADD_M_P:
  return expandMemOpM(MBB, MI, *this, V6CLANG::ADDM, MI.getOperand(2).getReg());
case V6CLANG::V6CLANG_SUB_M_P:
  return expandMemOpM(MBB, MI, *this, V6CLANG::SUBM, MI.getOperand(2).getReg());
// ... etc.
```

### Step 3 — ISel priority

These pseudos match more specific patterns (load folded into ALU op) than
the separate load + register-ALU patterns. LLVM's pattern specificity
ranking should prefer them automatically. If not, use `AddedComplexity`.

## Note on HL preservation (scavenger interaction)

The BC case clobbers HL. Current approach (O42) would require each pseudo
to check HL liveness and emit PUSH/POP internally. With the scavenger (O48),
this logic is centralized:

- **Without O48**: Each expansion must include `isRegDeadBefore(HL)` check
  and conditional PUSH/POP — duplicating 5-8 lines per pseudo × 11 = ~70
  extra lines.
- **With O48**: Pseudos declare `let Defs = [HL]` (for BC case), scavenger
  handles preservation. Expansion code is trivial.

O49 can be implemented before O48 (with per-pseudo PUSH/POP logic), but
the code is much cleaner after O48 is done.

For the DE case, XCHG clobbers both HL and DE, but since we restore both
with the second XCHG, no preservation is needed — the values are swapped
back. This is always safe regardless of liveness.

## Savings

| Category | Instructions | Savings/instance | Frequency |
|---|---|---|---|
| ALU read | ADD/SUB/ADC/SBB/ANA/ORA/XRA M | 4cc, 1B | High |
| Compare | CMP M | 4cc, 1B | Medium |
| Store imm | MVI M, imm8 | 5cc, 1B | Low-Med |
| RMW | INR M, DCR M | 8cc, 2B | Low |

**Aggregate**: In reduction loops and accumulator-heavy code, multiple ALU M
patterns fire per iteration — cumulative savings of 10-20cc per loop body.

## Complexity

Low-Medium — ~80 lines total:
- ~40 lines TableGen (11 pseudo definitions)
- ~30 lines shared expansion helper
- ~10 lines expansion case dispatching

## Risk

Very Low — ISel approach is fully safe. No register liveness concerns.
The expansion fallback paths (XCHG for DE, MOV for BC) are mechanical.

## Dependencies

- O48 (scavenger) — makes BC-case expansion much cleaner (optional, not
  required)
- Supersedes O4 (ADD M / SUB M peephole) — unsafe approach replaced by ISel
- Supersedes O46 (MVI M ISel) — MVI M is one of the 11 instructions covered
