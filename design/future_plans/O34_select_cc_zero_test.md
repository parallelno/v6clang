# O34. SELECT_CC Zero-Test ISel Gap

*Identified from investigation of `select_second` in O32 feature test.*

## Problem

When `SELECT_CC` is lowered with an i16 comparison against zero, ISel
produces `V6ClangISD::CMP` (register-register) instead of using the
`V6CLANG_BR_CC16_IMM` path that has O27's zero-test fast path.

This forces the register allocator to materialize the constant `0` into a
register pair (`LXI BC, 0`), wasting a register and 3 bytes + 12 cycles.
The comparison then expands to `SUB C; SBB B` (2B, 8cc) instead of the
optimal `MOV A, H; ORA L` (2B, 12cc — but no `LXI BC, 0` needed, net
savings of 3B + 12cc).

### Current code path

`LowerSELECT_CC()` always emits:
```
V6ClangISD::CMP lhs, rhs   →   (register-register compare)
V6ClangISD::SELECT_CC true, false, cc, flags
```

The `V6CLANG_BR_CC16_IMM` with its `imm=0` fast path is only reachable from
the `BR_CC` lowering path — direct `br(icmp eq %x, 0)` patterns.

### Example: `select_second`

```c
int select_second(int a, int b, int c) {
    if (a) return b;
    return c;
}
```

After ISel the comparison becomes:
```
$bc = LXI 0                    ; 3B 12cc — waste: materializes 0
V6CLANG_CMP16 $hl, $bc             ; register-register compare
JZ  ...
```

With the zero-test path it would be:
```
MOV  A, H                      ; 1B  8cc
ORA  L                          ; 1B  4cc
JZ   ...                        ; (no LXI, no register pair consumed)
```

### Impact

- **Saves 3B + 12cc** per i16 `select_cc` against zero (the `LXI` is
  eliminated entirely)
- **Frees one register pair** — BC is no longer consumed by the constant,
  which avoids spilling `c` (the 3rd argument) in the example above
- The spill cascade in `select_second` costs an additional ~50B / ~150cc
  that would mostly disappear if BC weren't occupied

### Frequency

Medium — `select(icmp eq/ne %x, 0, ...)` patterns appear in null checks,
boolean selects, and conditional returns with zero-tested conditions.

## Implementation

### Approach

In `LowerSELECT_CC()`, detect when the RHS is a known zero constant and
the condition is EQ/NE. In that case, split into a `V6ClangISD::BR_CC16_IMM`
(which has the zero fast path) + phi-based select, or alternatively add
a new `V6ClangISD::CMP16_IMM` node that the post-RA expansion can recognize
and expand with the `MOV A, H; ORA L` pattern.

The simpler approach may be to add a zero-test check directly in the
`V6CLANG_CMP16` expansion: if the RHS register pair holds a known zero (both
sub-registers are `0`), emit `MOV A, LhsHi; ORA LhsLo` instead of
`SUB RhsLo; SBB RhsHi`. However, this requires tracking the constant
value through the register allocator, which is non-trivial.

The cleanest approach is likely:
1. In `LowerSELECT_CC()`, when RHS is `ConstantSDNode(0)` and CC is
   EQ/NE, emit `V6ClangISD::BR_CC16_IMM` with `imm=0` into an
   if-diamond instead of `V6ClangISD::CMP` + `V6ClangISD::SELECT_CC`.
2. Or add a `V6ClangISD::CMP16_IMM` node paralleling `V6ClangISD::BR_CC16_IMM`
   that expands in `expandPostRAPseudo` with the same zero fast path.

### Risks

- **Low**: ISel-level change, well-contained.
- Need to ensure the diamond MBB expansion for SELECT_CC still works
  correctly with the new compare node.

### Dependencies

- O27 (i16 zero-test) — already complete, provides the fast-path expansion
- May benefit from O31 (dead PHI-constant elimination) — already complete
