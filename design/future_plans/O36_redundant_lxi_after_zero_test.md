# O36. Redundant Immediate Load After Branch-Proven Value

*Identified from analysis of temp/test_o28.asm `test_cond_zero_tailcall`.*
*Extends V6ClangLoadImmCombine — adds branch-implied value seeding.*

## Problem

After a conditional branch/return proves something about register values,
immediate loads on the fallthrough path may be redundant. The compiler
does not exploit the value information implied by branch outcomes.

### Primary Example: Zero-test + LXI 0

```c
int test_cond_zero_tailcall(int x) {
    if (x == 0) return bar(0);
    return x;
}
```

Current output:
```asm
test_cond_zero_tailcall:
    MOV  A, H
    ORA  L           ; zero-test x (HL)
    RNZ              ; return x if x != 0 (HL already holds x)
    LXI  HL, 0       ; ← REDUNDANT — HL is already 0 here
    JMP  bar          ; tail call bar(0)
```

The `ORA L` + `RNZ` path means: we reach `LXI HL, 0` only when
`H|L == 0`, so HL is guaranteed to be 0 already. Three registers
are proven zero: **H == 0, L == 0, A == 0**.

### Desired output

```asm
test_cond_zero_tailcall:
    MOV  A, H
    ORA  L
    RNZ
    JMP  bar          ; HL is already 0 — no LXI needed
```

### Savings

- Eliminates: `LXI HL, 0` (3 bytes, 12cc)
- **Net savings: 3 bytes, 12cc per instance.**

## Expanded Scope

The same principle applies to several related patterns:

### Pattern 1: Zero-test + LXI rp, 0 (primary case)

`MOV A, H; ORA L; RNZ` → fallthrough proves H=0, L=0, A=0.
Redundant: `LXI HL, 0`, `MVI H, 0`, `MVI L, 0`, `MVI A, 0`, `XRA A`.

### Pattern 2: 8-bit zero-test + MVI 0

`ORA A; RNZ` or `ANA A; RNZ` → fallthrough proves A=0.
Redundant: `MVI A, 0`, `XRA A`.

### Pattern 3: CPI imm + JZ/RZ (exact-value match)

`CPI 5; RZ` → fallthrough (NZ path) knows only that A ≠ 5 (not useful).
But the **taken path / target block** knows A == 5, so `MVI A, 5` is
redundant there. More useful for intra-block: `CPI imm; JNZ skip` →
fallthrough proves A == imm.

### Pattern 4: Cross-block zero-test propagation

If a predecessor block ends with a zero-test + Jcc, and this block is
the single-predecessor fallthrough, seed known values at block entry.

| Pattern | Proven values (fallthrough) | Eliminations | Frequency |
|---------|---------------------------|--------------|-----------|
| `MOV A,H; ORA L; RNZ/JNZ` | H=0, L=0, A=0 | LXI HL,0; MVI H/L/A,0 | Medium |
| `MOV A,D; ORA E; RNZ/JNZ` | D=0, E=0, A=0 | LXI DE,0; MVI D/E/A,0 | Low-Med |
| `ORA A; RNZ/JNZ` | A=0 | MVI A,0; XRA A | Low-Med |
| `ANA A; RNZ/JNZ` | A=0 | MVI A,0; XRA A | Low |
| `CPI imm; JNZ skip` | A=imm (fallthrough) | MVI A,imm | Low |

### Where these patterns appear

- Early-return guards: `if (x==0) return bar(0);`
- Null-pointer checks: `if (ptr==NULL) return handler(NULL);`
- Switch-like dispatch: `if (cmd==5) send(5);`
- After O35 (Rcc over RET): creates Rcc + LXI + JMP sequences

## Implementation

### Recommended: Extend V6ClangLoadImmCombine (Approach B)

V6ClangLoadImmCombine already tracks known register values per-BB via a
forward scan. The extension:

1. **At BB entry**, check if the block has a **single predecessor**
   whose terminator implies known values on the fallthrough path.
2. Recognize the zero-test idiom: look backwards from the predecessor's
   terminator for `MOV A, rHi; ORA rLo` + conditional branch/return on
   Z flag (JNZ/RNZ skip the fallthrough).
3. **Seed the value map**: `rHi=0, rLo=0, A=0`.
4. Recognize `CPI imm` + `JNZ` → seed `A=imm` on fallthrough.
5. The existing MVI/LXI elimination logic handles the rest automatically,
   including MOV propagation and INR/DCR ±1 matching.

This approach is superior to a standalone peephole because:
- Composes with all existing LoadImmCombine optimizations.
- Handles both LXI and MVI uniformly.
- Cross-block propagation comes naturally (single-predecessor check).
- No new pass infrastructure needed.

### Pass ordering

V6ClangLoadImmCombine already runs in the pipeline. The only change is
seeding known values at block entry for single-predecessor fallthroughs.
No pass ordering change needed.

### Affected tests

- `test_cond_zero_tailcall` — should emit `RNZ; JMP bar` instead of
  `RNZ; LXI HL, 0; JMP bar`.
- Any function with `if (x==0) return f(0);` pattern.

## Complexity & Risk

- **Complexity:** Low (~40-50 lines in V6ClangLoadImmCombine)
- **Risk:** Low — value seeding only activates for single-predecessor
  blocks with a recognized zero-test/CPI terminator pattern. Must
  verify that the zero-test truly covers the exact registers being
  seeded (e.g., `MOV A, H; ORA L` proves HL==0, not DE==0).
- **Dependencies:** Benefits from O27 (zero-test), O35 (Rcc over RET),
  O13 (LoadImmCombine infrastructure).
