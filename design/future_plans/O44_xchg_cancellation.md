# O44. Adjacent XCHG Cancellation Peephole

*Identified while fixing the O42 SPILL16-DE trailing XCHG bug. After*
*correcting the condition to `!(IsKill && HLDead)`, consecutive SPILL16-DE*
*and LOAD16_P-DE expansions each emit their own XCHG, producing adjacent*
*`XCHG; XCHG` pairs that cancel out (swap HL↔DE twice = no-op). Costs*
*8cc and 2B per pair for zero effect.*

## Problem

Multiple pseudo expansions independently emit XCHG instructions to
temporarily swap HL↔DE. When two such expansions are adjacent in the MIR,
their trailing/leading XCHGs become consecutive in the final instruction
stream:

```asm
; From SPILL16 DE expansion (trailing XCHG):
XCHG                ; 4cc 1B — restore DE/HL after SHLD
; From LOAD16_P DE expansion (leading XCHG):
XCHG                ; 4cc 1B — put DE into HL for pointer deref
```

These two XCHGs cancel: `XCHG; XCHG` ≡ no-op. Removing both saves 8cc, 2B.

### Example (sumarray loop with `--enable-deferred-spilling`)

```asm
; Current (after O42 fix):
SHLD  __v6clang_ss.sumarray+2    ; spill arr1_ptr (DE via XCHG+SHLD+XCHG)
XCHG                          ; ← trailing from SPILL16 DE
XCHG                          ; ← leading from LOAD16_P DE
MOV   E, M                    ; load arr1[i] lo
INX   HL
MOV   D, M                    ; load arr1[i] hi
XCHG                          ; trailing from LOAD16_P DE

; Optimized:
SHLD  __v6clang_ss.sumarray+2    ; spill arr1_ptr
                               ; (two XCHGs removed — 8cc, 2B saved)
MOV   E, M
INX   HL
MOV   D, M
XCHG
```

## Approach

Post-expansion peephole in `V6ClangPeepholePass` (runs in `addPreEmitPass`).
Single linear scan over each MBB looking for consecutive XCHG instructions.

### Pattern

```
XCHG
XCHG
```

Two adjacent `V6CLANG::XCHG` instructions with no intervening labels, branches,
or other instructions. Delete both.

### Safety conditions

1. **Both are plain XCHG** — opcode `V6CLANG::XCHG`, no operands, no implicit
   defs/uses beyond the standard DE↔HL swap.
2. **Truly adjacent** — no debug values, labels, or other instructions
   between them. Skip over `DBG_VALUE` / `CFI_INSTRUCTION` if present.
3. **No flags dependency** — XCHG does not affect flags on the 8080, so
   there's no flag state to preserve. Safe to remove unconditionally.

### Why not fix in `eliminateFrameIndex`?

Making the SPILL16 expansion aware of the next pseudo would create fragile
coupling between independent expansions (same issue that caused the O42
XCHG bug). The peephole approach operates on the final instruction stream
with no coupling risk.

## Implementation

### Location

`V6ClangPeepholePass::runOnMachineFunction` in `V6ClangPeephole.cpp`.
Add as an early scan before other peephole patterns (so later patterns
see cleaner code).

### Algorithm

```
for each MBB:
  I = MBB.begin()
  while I != MBB.end():
    if I->getOpcode() == V6CLANG::XCHG:
      J = skipDebugValues(next(I))
      if J != MBB.end() && J->getOpcode() == V6CLANG::XCHG:
        // Adjacent XCHG pair — delete both
        J = MBB.erase(J)   // erase second XCHG
        I = MBB.erase(I)   // erase first XCHG, I now points to next
        Changed = true
        continue            // re-check from new I (may be another XCHG)
    ++I
```

### Estimated size

~15 lines in `V6ClangPeephole.cpp`.

## Cost analysis

| Metric | Value |
|--------|-------|
| Savings per instance | 8cc, 2B |
| Frequency | Medium (wherever SPILL16-DE or RELOAD16-DE abuts another XCHG-based expansion) |
| Complexity | Very Low (~15 lines) |
| Risk | Very Low (XCHG has no flags side effects, safe to cancel) |
| Dependencies | None (benefits increase when O42 trailing-XCHG fix is active) |

## Testing

- Existing lit tests should not regress — consecutive XCHGs are pure waste,
  so removing them never changes semantics.
- New lit test: `xchg-cancel-peephole.ll` with a function that produces
  adjacent XCHG pairs from consecutive DE spill/reload expansions.
- Verify the sumarray example with `--enable-deferred-spilling` has no
  adjacent XCHG pairs in the output.

## Interaction with other optimizations

- **O42 (liveness-aware expansion)**: O42's fix for the SPILL16-DE trailing
  XCHG is what *creates* these adjacent pairs. O44 cleans them up.
- **O43 (SHLD/LHLD→PUSH/POP)**: O44 should run *before* O43 so that
  cancelled XCHGs expose more direct SHLD/LHLD HL pairs for O43 to match.
- **XchgOpt pass**: XchgOpt replaces MOV pairs with XCHG. It doesn't
  detect or remove adjacent XCHGs. O44 is complementary.
- **V6ClangAccumulatorPlanning**: Runs before peephole. May introduce XCHG
  in some paths, but adjacent pairs from accumulator planning are unlikely.
