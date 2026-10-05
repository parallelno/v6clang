# O43. SHLD/LHLD to PUSH/POP Peephole (Static Stack Spill Shortening)

*Identified while analyzing `--enable-deferred-spilling` output for the*
*two-array summation loop. The RA places SPILL16-HL and RELOAD16-HL close*
*together with only non-SP-affecting instructions between them. The static*
*stack expansion emits `SHLD addr` (20cc, 3B) + `LHLD addr` (20cc, 3B) =*
*40cc, 6B — but `PUSH HL` (16cc, 1B) + `POP HL` (12cc, 1B) = 28cc, 2B*
*achieves the same effect when the pair is close and no SP changes occur*
*between them.*

## Problem

In static stack mode, every `V6CLANG_SPILL16 $hl` expands to `SHLD addr` and
every `V6CLANG_RELOAD16 $hl` expands to `LHLD addr`. These are absolute-address
memory operations — correct but expensive.

When a spill and its matching reload are nearby with no SP-affecting
instructions between them, the hardware stack (PUSH/POP) is cheaper:

| Sequence | Cycles | Bytes |
|----------|--------|-------|
| SHLD addr + LHLD addr | 40cc | 6B |
| PUSH HL + POP HL | 28cc | 2B |
| **Savings** | **12cc** | **4B** |

This pattern is common in loops where the RA spills HL (the accumulator)
across a few pointer-dereferencing instructions, then immediately reloads it.

### Example (sumarray inner loop with `--enable-deferred-spilling`)

```asm
; Current:
SHLD  __v6clang_ss.sumarray    ; 20cc 3B — spill sum (HL)
MOV   H, B                 ; \
MOV   L, C                 ;  | load arr2[i]
MOV   E, M                 ;  | no SP changes
INX   HL                   ;  |
MOV   D, M                 ; /
LHLD  __v6clang_ss.sumarray    ; 20cc 3B — reload sum (HL)
                            ; total: 40cc 6B for spill+reload

; Optimized:
PUSH  HL                    ; 16cc 1B — spill sum (HL)
MOV   H, B                 ; \
MOV   L, C                 ;  | load arr2[i]
MOV   E, M                 ;  | no SP changes
INX   HL                   ;  |
MOV   D, M                 ; /
POP   HL                    ; 12cc 1B — reload sum (HL)
                            ; total: 28cc 2B for spill+reload
```

## Approach

Post-expansion peephole in `V6ClangPeepholePass` (runs in `addPreEmitPass`).
Pattern-match on the final instruction stream after all pseudos have been
expanded.

### Pattern

```
SHLD addr₁
... (0 or more instructions, with SP delta tracked — see below)
LHLD addr₂
```

where `addr₁ == addr₂` (same GlobalAddress + offset) and the SP delta
is zero at the LHLD and never goes positive during the scan.

Replace with:
```
PUSH HL
... (unchanged)
POP  HL
```

### Safety conditions

All must hold:

1. **Same address** — SHLD and LHLD reference the same global symbol and offset.
2. **SP delta is zero at match** — track an SP delta starting at 0 after
   the PUSH HL. PUSH decrements by 2, POP increments by 2. The delta
   must be exactly 0 when the matching LHLD is reached, and must never
   go positive during the scan (positive means something popped past our
   saved value).
3. **No unpredictable SP changes** — abort on SPHL, LXI SP, INX SP, or
   DCX SP (these make the SP delta unpredictable or misaligned).
4. **Same basic block** — both instructions are in the same MBB (no branches
   between them). RET/Rcc are BB terminators so this is implicit.
5. **No aliased reads** — the address is not read by any instruction between
   the SHLD and LHLD (no other LHLD to the same addr, no LXI HL,addr +
   MOV r,M sequence targeting the same slot). In practice, static stack
   slots are only accessed via SHLD/LHLD/LXI sequences, so checking for
   another LHLD/SHLD to the same address is sufficient.
6. **LIFO nesting** — if multiple SHLD→LHLD pairs are converted, they must
   nest properly (inner pairs converted first, or pairs don't overlap).
   In practice, HL can only be spilled once at a time, so overlapping
   pairs don't occur for the same register.

## Implementation

### Location

`V6ClangPeepholePass::runOnMachineFunction` in `V6ClangPeephole.cpp`.
Add a new scan after existing peephole patterns.

### Algorithm

```
for each MBB:
  for each SHLD instruction I:
    addr = I.getOperand(1)  // GlobalAddress + offset
    sp_delta = 0
    scan forward from I+1:
      if instruction is LHLD with same addr:
        if sp_delta == 0 → MATCH
        else → abort
      if instruction is SHLD with same addr → abort (re-spill)
      if MI.modifiesRegister(V6CLANG::SP, TRI):
        if opcode is PUSH   → sp_delta -= 2
        if opcode is POP    → sp_delta += 2; if sp_delta > 0 → abort
        if MI.isCall()      → skip (CALL/Ccc/RST are net-zero)
        else                → abort (unknown SP modifier — conservative)
      if end of BB → abort
    if MATCH:
      replace SHLD with PUSH HL
      replace LHLD with POP HL
```

Use `MI.modifiesRegister(V6CLANG::SP, TRI)` as the primary filter for
SP-affecting instructions. This catches all instructions with
`Defs = [SP]` in the .td file (PUSH, POP, CALL, Ccc, RST, SPHL,
RET/Rcc, and INX/DCX/LXI with SP operand). The `else → abort`
fallthrough ensures any unrecognized SP modifier is handled
conservatively — no hand-maintained list can go stale.

Note: `DAD SP` reads SP but does not define it, so
`modifiesRegister(SP)` returns false — no special case needed.
RET/Rcc are BB terminators and never appear mid-block, so they
are caught by the end-of-BB check.

### Estimated size

~50 lines in `V6ClangPeephole.cpp`.

## Cost analysis

| Metric | Value |
|--------|-------|
| Savings per instance | 12cc, 4B |
| Frequency | Medium-high (every short-lived HL spill in static stack mode) |
| Complexity | Low (~50 lines) |
| Risk | Very Low (post-expansion peephole, no coupling) |
| Dependencies | O10 (static stack) must be active |

## Testing

- Existing lit tests should not regress (SHLD/LHLD pairs that span SP
  changes or cross BBs are left unchanged).
- New lit test: `spill-push-pop-peephole.ll` with a function that has
  a short-lived HL spill between non-SP instructions.
- Negative cases in the same lit test — verify SHLD/LHLD are **not**
  converted when an SP-modifying instruction appears between them
  (e.g. SPHL, LXI SP, INX SP, DCX SP, or unbalanced PUSH/POP).
- Verify the sumarray example with `--enable-deferred-spilling` produces
  PUSH/POP instead of SHLD/LHLD for the close pairs.

## Interaction with other optimizations

- **O42 (liveness-aware expansion)**: O42 eliminates PUSH/POP around
  *scratch register saves* in pseudo expansion. O43 converts *primary
  spill/reload* SHLD/LHLD to PUSH/POP. Complementary, no conflict.
- **O16 (store-to-load forwarding)**: O16 eliminates redundant reloads
  entirely. When O16 removes the LHLD, there's no pair for O43 to match.
  O43 handles the cases O16 can't eliminate.
- **XCHG-XCHG cancellation**: Should run before O43 so that cancelled
  XCHGs expose more SHLD/LHLD HL pairs.
