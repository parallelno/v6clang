# O16. Post-RA Store-to-Load Forwarding (Spill/Reload)

*Inspired by llvm-z80 `Z80LateOptimization` IX-indexed and SM83 SP-relative forwarding.*
*Detailed analysis: [llvm_z80_analysis.md](llvm_z80_analysis.md) §S5, §S6.*

## Problem

After register allocation, V6CLANG inserts spill/reload sequences for stack access
costing ~52cc each (see [O08](O08_spill_optimization.md)). Often, the register being reloaded still holds
the same value that was spilled — the register was not clobbered between the
spill and reload. In these cases, the reload is completely redundant.

Even when the original register was clobbered, another register might still
hold the spilled value (from a copy chain), enabling a cheap register-to-register
transfer (8cc) instead of a full stack reload (52cc).

## How the Z80 Backends Do It

**jacobly0**: Tracks `DenseMap<int, MCPhysReg> AvailValues` mapping IX+d offsets
to physical registers. On spill: record. On reload: forward or eliminate.
On register clobber: invalidate affected entries. On call: clear all.

**llvm-z80**: Extended version for SM83 (which lacks IX, like the 8080):
- Tracks both register values and immediate constants at each SP-relative offset
- Handles 16-bit store/load patterns (two adjacent 8-bit slots)
- Detects and eliminates redundant stores (same value already in slot)
- Manages SP delta tracking through PUSH/POP/ADD SP,e

## V6CLANG Adaptation

V6CLANG's stack access uses the pattern:
```asm
PUSH HL; LXI HL, offset; DAD SP; MOV M, r; POP HL   ; spill
PUSH HL; LXI HL, offset; DAD SP; MOV r, M; POP HL   ; reload
```

The pass would track `offset → register` mappings and:
1. **Eliminate redundant reloads**: If `r` still holds the spilled value, erase
   the entire 5-instruction reload sequence (saves 52cc + 5 bytes)
2. **Forward via MOV**: If `r` was clobbered but `r'` holds the value, replace
   the reload with `MOV r, r'` (saves 44cc + 4 bytes)
3. **Eliminate redundant stores**: If the slot already holds the value being
   stored, erase the entire spill sequence

## Before → After

```asm
; Before                                    ; After
PUSH HL; LXI HL,4; DAD SP; MOV M,C; POP HL ; spill C at SP+4
; ... C not clobbered ...                    ; ... C not clobbered ...
PUSH HL; LXI HL,4; DAD SP; MOV E,M; POP HL ; reload → E   MOV E,C  ; 8cc, 1B
; Saves: 52cc – 8cc = 44cc per forwarded reload
```

## Benefit

- **Savings per instance**: 44-52cc per forwarded/eliminated reload
- **Frequency**: Very high — spill/reload pairs are pervasive in any function
  with >1 live pointer
- **Compound effect**: Eliminated reloads free HL for other uses → further
  reducing spill pressure

## Complexity

Medium. ~100-150 lines. The offset tracking is straightforward. Main
complexity: correctly invalidating entries on register clobber (must check
all tracked registers, not just the instruction's explicit defs) and handling
calls/side effects.

## Risk

Low-Medium. Only replaces when provably correct (register value matches
what's in the stack slot). Conservative: clear all on call/unknown side
effects.
