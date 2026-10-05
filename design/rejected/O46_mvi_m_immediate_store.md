# O46. MVI M, imm8 Immediate Store via ISel

*Identified while inspecting `main` in `v6clang_leaf_o16fix.asm`. The*
*compiler emits `MVI A, 4; MOV M, A` (3B/14cc) instead of the direct*
*`MVI M, 4` (2B/10cc) because `MVIM` has no ISel pattern.*

## Problem

When storing an 8-bit immediate to memory via HL, the compiler goes
through a register:

```asm
MVI   A, 4           ; 2B, 7cc  — load imm into A
MOV   M, A           ; 1B, 7cc  — store A to [HL]
; Total: 3B, 14cc
```

The 8080 has a direct `MVI M, imm8` instruction:

```asm
MVI   M, 4           ; 2B, 10cc — store imm directly to [HL]
```

Savings: **1B, 4cc** per instance.

### Root cause

`MVIM` is defined in `V6ClangInstrInfo.td` with an empty ISel pattern (`[]`).
ISel doesn't know it can use `MVI M, imm8` for storing an immediate to
an HL-addressed memory location. Instead, ISel materializes the immediate
into a register (`MVIr`) and then stores via `V6CLANG_STORE8_P`.

## Approach

ISel pattern via a new pseudo `V6CLANG_STORE8_IMM_P` that matches
`(store (i8 imm), i16:$addr)`. The pseudo is expanded post-RA:
- If `$addr` is HL → emit `MVIM imm8` directly.
- If `$addr` is DE/BC → emit `XCHG` or `PUSH HL` + `MOV H,D; MOV L,E` +
  `MVIM` + restore, same as `V6CLANG_STORE8_P` but with immediate source.

This is the safe approach: ISel selects `MVIM` at the DAG level (no
register is ever allocated for the immediate), and expansion handles the
pointer-in-wrong-pair case correctly.

### Why not a peephole?

A post-RA peephole that deletes `MVI r, imm; MOV M, r` is fragile:
- Kill flags can be stale — deleting `MVI A, imm` when A is still live
  elsewhere causes silent correctness bugs.
- Cross-BB liveness isn't visible from a local scan.

ISel avoids these problems entirely: no register is allocated, so there's
nothing to delete and no liveness concern.

### Why not a pattern directly on `MVIM`?

`MVIM` hardcodes HL as the pointer source (`Uses = [HL]`). At ISel time,
the pointer hasn't been assigned to a physical register yet — it's in a
virtual register. A pseudo absorbs any `GR16` register pair and expands
to the right instruction sequence after RA.

## Implementation

### Step 1 — Define the pseudo in `V6ClangInstrInfo.td`

```tablegen
let mayStore = 1 in
def V6CLANG_STORE8_IMM_P : V6ClangPseudo<(outs), (ins imm8:$imm, GR16:$addr),
    "# STORE8_IMM_P $imm, ($addr)",
    [(store (i8 imm:$imm), i16:$addr)]>;
```

### Step 2 — Expand in `V6ClangInstrInfo::expandPostRAPseudo`

Add a case for `V6CLANG_STORE8_IMM_P`:

```cpp
case V6CLANG::V6CLANG_STORE8_IMM_P: {
  Register Addr = MI.getOperand(1).getReg();
  int64_t Imm = MI.getOperand(0).getImm();
  if (Addr == V6CLANG::HL) {
    // Direct: MVI M, imm
    BuildMI(MBB, MI, DL, TII.get(V6CLANG::MVIM)).addImm(Imm);
  } else {
    // Need HL for MVI M — move pointer to HL, store, restore.
    // Same PUSH/POP/XCHG strategy as V6CLANG_STORE8_P expansion.
    // ... (see V6CLANG_STORE8_P expansion for reference)
    BuildMI(MBB, MI, DL, TII.get(V6CLANG::MVIM)).addImm(Imm);
    // ... restore HL
  }
  MI.eraseFromParent();
  return true;
}
```

### Step 3 — Priority

ISel prefers the more specific pattern. `V6CLANG_STORE8_IMM_P` matches
`(store (i8 imm), i16:$addr)` while `V6CLANG_STORE8_P` matches
`(store i8:$src, i16:$addr)`. LLVM's pattern specificity ranking should
prefer the immediate variant automatically. If not, `AddedComplexity`
can be used on the pseudo.

## Costs

| Metric | Before | After | Savings |
|--------|--------|-------|---------|
| Bytes  | 3B     | 2B    | 1B      |
| Cycles | 14cc   | 10cc  | 4cc     |

Savings apply only when `$addr` is already in HL (no extra XCHG cost).
When `$addr` is in DE/BC, the expansion may break even or lose slightly
vs the register path. `AddedComplexity` or a cost check can limit the
pattern to HL-only if needed.

## Risks

| Risk | Mitigation |
|------|------------|
| Pointer not in HL at expansion time | Expansion falls back to XCHG/PUSH strategy, same as V6CLANG_STORE8_P |
| Pattern priority conflict with V6CLANG_STORE8_P | ISel prefers more specific (immediate) pattern; AddedComplexity if needed |
| Rare pattern | Low frequency, but zero risk — ISel approach is fully safe |

## Complexity

Low — ~10 lines TableGen + ~20 lines expansion in `expandPostRAPseudo`.
