# O29. Cross-BB Immediate Value Propagation

*Identified from analysis of temp/compare/07/v6clang.c output.*
*Extension of O13 (register value tracking) across basic block boundaries.*

## Problem

The existing `V6ClangLoadImmCombine` (O13) and `V6ClangAccumulatorPlanning` (M8)
passes track register values within a single basic block. When
`V6CLANG_BR_CC16_IMM` splits an MBB into two blocks for the high-byte
comparison, the second block starts with no knowledge of register values
from the first block. This causes redundant immediate loads.

### Example: comparing i16 against 0 (NE condition)

```asm
; BB0 (original MBB):
    MVI  A, 0           ; 7cc, 2B — A is now known to be 0
    CMP  L              ; 4cc, 1B — CMP does NOT modify A
    JNZ  Target         ; 10cc, 3B

; BB1 (CompareHiMBB, created by MBB split):
    MVI  A, 0           ; 7cc, 2B — REDUNDANT! A is still 0 from BB0
    CMP  H              ; 4cc, 1B
    JNZ  Target         ; 10cc, 3B
    JMP  Fallthrough    ; 10cc, 3B
```

The second `MVI A, 0` is redundant because:
1. `CMP` does not modify the accumulator (only FLAGS)
2. `JNZ` does not modify any registers
3. BB1 has exactly one predecessor (BB0)
4. A is known to hold 0 at the end of BB0

### After optimization:
```asm
; BB0:
    MVI  A, 0           ; 7cc, 2B
    CMP  L              ; 4cc, 1B
    JNZ  Target         ; 10cc, 3B

; BB1 (CompareHiMBB):
    ; (MVI A, 0 removed — A already holds 0)
    CMP  H              ; 4cc, 1B
    JNZ  Target         ; 10cc, 3B
    JMP  Fallthrough    ; 10cc, 3B
```

Saves **1B + 7cc** per instance.

### Broader applicability

This pattern appears beyond just BR_CC16_IMM zero comparisons:

1. **BR_CC16_IMM with any repeated immediate**: When lo8 == hi8 (e.g.,
   comparing against 0x0101, 0x4242), the second MVI is redundant.
2. **Sequential basic blocks with known register values**: Any case where
   a single-predecessor block starts with `MVI r, imm` and the predecessor
   exits with that register holding the same value. Applies to **all 7 GPRs**
   (A, B, C, D, E, H, L), not just the accumulator.
3. **LXI pair propagation**: When a predecessor block ends with a known
   pair value (e.g., `LXI DE, 0x0000`), a successor starting with
   `LXI DE, 0x0000` (or `MVI D, 0` / `MVI E, 0`) is redundant.
4. **Loop headers**: A loop body ending with known register constants, and
   the loop header re-loading the same constants.

### Tracked state (inherited from O13)

The cross-BB propagation uses the same per-register tracking as O13:

| Register | Tracked? | Set by | Propagated by | Invalidated by |
|----------|----------|--------|---------------|----------------|
| **A** | Yes | MVI, MOV, LDA, LDAX | MOV | ALU ops, LDA, LDAX, POP PSW, CALL |
| **B** | Yes | MVI, MOV, POP BC (hi) | MOV | POP BC, CALL, any def |
| **C** | Yes | MVI, MOV, POP BC (lo) | MOV | POP BC, CALL, any def |
| **D** | Yes | MVI, MOV, POP DE (hi) | MOV, XCHG (↔H) | POP DE, XCHG, CALL, any def |
| **E** | Yes | MVI, MOV, POP DE (lo) | MOV, XCHG (↔L) | POP DE, XCHG, CALL, any def |
| **H** | Yes | MVI, MOV, POP HL (hi) | MOV, XCHG (↔D) | POP HL, XCHG, INX/DCX HL, CALL, any def |
| **L** | Yes | MVI, MOV, POP HL (lo) | MOV, XCHG (↔E) | POP HL, XCHG, INX/DCX HL, CALL, any def |
| **BC** | Implicit | LXI BC | — | INX/DCX BC, POP BC, CALL |
| **DE** | Implicit | LXI DE | — | INX/DCX DE, POP DE, XCHG, CALL |
| **HL** | Implicit | LXI HL | — | INX/DCX HL, POP HL, XCHG, DAD, LHLD, CALL |

**Not tracked**: SP (not GPR), FLAGS (not addressable), PSW (only via PUSH/POP).

### Cross-BB examples beyond accumulator

**Example 2: Redundant MVI for non-A register**
```asm
; BB0:
    MVI  D, 0           ; D is now known to be 0
    ...                  ; no instruction modifies D
    JNZ  BB2
; BB1 (single predecessor = BB0):
    MVI  D, 0           ; REDUNDANT — D still holds 0
    ...
```

**Example 3: Redundant LXI for register pair**
```asm
; BB0:
    LXI  DE, 0x1234     ; D=0x12, E=0x34
    ...                  ; no instruction modifies D or E
    JZ   BB2
; BB1 (single predecessor = BB0):
    LXI  DE, 0x1234     ; REDUNDANT — DE still holds 0x1234
    ...
```
The LXI case fires when both sub-registers match. If only one matches,
the individual MVI for that sub-register can still be eliminated.

**Example 4: XCHG-aware propagation**
```asm
; BB0:
    LXI  HL, 0x0000     ; H=0, L=0
    XCHG                 ; now D=0, E=0 (H,L unknown unless DE was known)
    JNZ  BB2
; BB1 (single predecessor = BB0):
    MVI  D, 0           ; REDUNDANT — D=0 after XCHG
    MVI  E, 0           ; REDUNDANT — E=0 after XCHG
```

## Implementation

### Approach: Extend V6ClangLoadImmCombine with cross-BB propagation

Add an optional cross-BB propagation phase to `V6ClangLoadImmCombine.cpp`.
The existing `KnownVal[NumTracked]` array (A, B, C, D, E, H, L — 7 entries)
is reused; we just change how it is initialized at block entry.

```cpp
/// For blocks with a single predecessor, initialize KnownVal[] from
/// the predecessor's exit state (if available).
/// Covers all 7 GPRs: A, B, C, D, E, H, L.
void V6ClangLoadImmCombine::initFromPredecessor(MachineBasicBlock &MBB) {
  if (MBB.pred_size() != 1)
    return;  // Only single-predecessor blocks (safe, conservative)

  MachineBasicBlock *Pred = *MBB.pred_begin();

  // Reset all KnownVal[0..6] to std::nullopt.
  invalidateAll();

  // Forward-scan the predecessor using existing updateKnownValues(MI)
  // to compute exit state for all tracked registers.
  for (MachineInstr &MI : *Pred) {
    updateKnownValues(MI);  // handles MVI, MOV, LXI, INR, DCR,
                            // XCHG, POP, ALU ops, CALL, etc.
  }

  // Now KnownVal[] reflects the predecessor's exit state for all 7 GPRs.
  // The per-BB forward scan in the current block will use these as
  // initial values and can eliminate redundant MVI/LXI for any register.
}
```

This leverages the full O13 tracking (MVI→set, MOV→propagate, LXI→set pair,
INR/DCR→±1, XCHG→swap DE↔HL, POP/CALL→invalidate) without any new logic.

### Alternative: Fix at the source (V6CLANG_BR_CC16_IMM expansion)

Instead of general cross-BB propagation, the expansion code in
`V6ClangInstrInfo.cpp` that creates CompareHiMBB could check whether lo8 == hi8
and skip the second MVI:

```cpp
// In V6CLANG_BR_CC16_IMM expansion, NE path:
{
  auto MIB = BuildMI(CompareHiMBB, DL, get(V6CLANG::MVIr), V6CLANG::A);
  addImmHi(MIB);
}

// Could become:
if (lo8 != hi8) {
  auto MIB = BuildMI(CompareHiMBB, DL, get(V6CLANG::MVIr), V6CLANG::A);
  addImmHi(MIB);
}
// When lo8 == hi8, A already holds the correct value from BB0.
```

This is simpler but less general. The first approach (cross-BB propagation)
handles more cases.

### Recommended approach

Implement both:
1. **Quick fix**: Check lo8 == hi8 in BR_CC16_IMM expansion (~5 lines)
2. **General**: Cross-BB propagation in LoadImmCombine for single-predecessor
   blocks (~30-40 lines)

### Note on O27 interaction

If O27 (i16 zero-test) is implemented first, the main motivating case
(comparing against 0) is eliminated entirely — there's no MBB split and
no second MVI at all. O29 remains valuable for:
- Non-zero immediate comparisons where lo8 == hi8
- Other cross-BB patterns unrelated to comparisons
- Comparisons against global addresses (where MBB split still occurs)

## Benefit

- **1B + 7cc** per eliminated `MVI r, imm` (any of A, B, C, D, E, H, L)
- **2B + 10cc** per eliminated `LXI rp, imm16` (when both sub-regs match)
- **Frequency**: Medium — fires for:
  - BR_CC16_IMM when lo8(rhs) == hi8(rhs) (A register)
  - Cross-BB patterns with known values in B, C, D, E, H, or L
  - Redundant LXI reloads for BC, DE, or HL after linear fallthrough
- Partially subsumed by O27 for the zero case

## Complexity

Low (quick fix in expansion: ~5 lines) to Medium (general cross-BB
propagation: ~30-40 lines in LoadImmCombine).

## Risk

Low. The quick fix is trivially correct (CMP doesn't modify A). The general
approach is conservative: only propagates through single-predecessor edges,
using the same value-tracking logic already proven in O13.

## Dependencies

- O13 (Load-Immediate Combining) — already complete; provides the tracking
  infrastructure to extend.
- O27 (i16 zero-test) — if implemented, subsumes the main motivating case
  but O29 remains useful for non-zero comparisons.
