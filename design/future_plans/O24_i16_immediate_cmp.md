# O24. MVI+SUB/SBB Immediate Ordering Comparison

*From plan_immediate_cmp.md Future Enhancements.*
*Extends the immediate CMP optimization to all ordering comparisons
(unsigned and signed) with constants.*

## Problem

The current V6CLANG_BR_CC16_IMM pseudo handles EQ/NE comparisons with
immediate RHS using `MVI A, const; CMP reg` (12cc per byte, no register
pair needed). For ordering comparisons (SETULT, SETUGE, SETULT, SETUGT,
SETULE, SETSLT, SETGE), the backend materializes the constant in a
register pair via LXI, then uses SUB/SBB with register operands:

### Current output (all ordering comparisons with constant):
```asm
; if (x < 1000) ...         ; ULT
    LXI  DE, 0x3e7          ; 12cc, 3B  ← constant in register pair
    MOV  A, E               ;  8cc, 1B
    SUB  L                  ;  4cc, 1B
    MOV  A, D               ;  8cc, 1B
    SBB  H                  ;  4cc, 1B
    RC                      ; 16cc/8cc, 1B
; Comparison: 36cc, 7B (wastes DE for the constant)
```

The compiler already transforms all six ordering conditions into
SUB/SBB + carry/sign test:

| Source condition  | Compiled as             | Branch |
|------------------|-------------------------|--------|
| `x < K`  (ULT)  | `(K-1) - x`, test CF   | RC/JC  |
| `x >= K` (UGE)  | `x - K`, test CF       | RNC/JNC |
| `x > K`  (UGT)  | `x - (K+1)`, test CF   | RNC/JNC |
| `x <= K` (ULE)  | `K - x`, test CF       | RNC/JNC |
| `x < K`  (SLT)  | `x - K`, test SF       | RM/JM  |
| `x >= K` (SGE)  | `x - K`, test SF       | RP/JP  |

In every case, the constant is loaded into DE via LXI just for the
SUB/SBB sequence.

### Key insight: MVI does not affect flags on 8080

Since MVI does not modify any flags, it can be placed between SUB and
SBB without breaking the borrow/carry chain. This eliminates the need
to pre-load the constant into a register pair.

### Expected output (MVI + SUB/SBB):
```asm
; if (x < 1000) ...         ; ULT: compute (999 - x), branch on carry
    MVI  A, 0xe7            ;  8cc, 2B  ← lo8(999), flags untouched
    SUB  L                  ;  4cc, 1B  ← A = lo8(999) - L, sets CF
    MVI  A, 0x03            ;  8cc, 2B  ← hi8(999), CF preserved!
    SBB  H                  ;  4cc, 1B  ← A = hi8(999) - H - CF
    RC                      ; 16cc/8cc, 1B
; Comparison: 24cc, 6B (no register pair needed)
```

### All six conditions with MVI+SUB/SBB:

```asm
; ULT: x < K  →  compute (K-1) - x, branch on CF
    MVI  A, lo8(K-1)       ;  8cc, 2B
    SUB  L                 ;  4cc, 1B
    MVI  A, hi8(K-1)       ;  8cc, 2B
    SBB  H                 ;  4cc, 1B
    RC                     ;     -, 1B   ← carry = x > K-1 = x >= K → false

; UGE: x >= K  →  compute x - K, branch on CF
    MVI  A, lo8(K)         ;  8cc, 2B
    SUB  L                 ;  4cc, 1B    ← NOTE: const - x, then invert
    MVI  A, hi8(K)         ;  8cc, 2B
    SBB  H                 ;  4cc, 1B
    RC                     ;     -, 1B   ← carry = K > x = x < K → false

; UGT: x > K  →  compute x - (K+1), branch on CF
    MVI  A, lo8(K)         ;  8cc, 2B
    SUB  L                 ;  4cc, 1B
    MVI  A, hi8(K)         ;  8cc, 2B
    SBB  H                 ;  4cc, 1B
    RNC                    ;     -, 1B

; ULE: x <= K  →  compute K - x, branch on CF
    MVI  A, lo8(K)         ;  8cc, 2B
    SUB  L                 ;  4cc, 1B
    MVI  A, hi8(K)         ;  8cc, 2B
    SBB  H                 ;  4cc, 1B
    RNC                    ;     -, 1B

; SLT: x < K (signed)  →  compute x - K, branch on SF
    MVI  A, lo8(K)         ;  8cc, 2B
    SUB  L                 ;  4cc, 1B    ← NOTE: const - x, then check sign
    MVI  A, hi8(K)         ;  8cc, 2B
    SBB  H                 ;  4cc, 1B
    RM                     ;     -, 1B

; SGE: x >= K (signed)  →  compute x - K, branch on SF
    MVI  A, lo8(K)         ;  8cc, 2B
    SUB  L                 ;  4cc, 1B
    MVI  A, hi8(K)         ;  8cc, 2B
    SBB  H                 ;  4cc, 1B
    RP                     ;     -, 1B
```

Note: the exact operand order (const-x vs x-const) and branch
condition (RC/RNC/RM/RP) depend on the existing ISel lowering —
the compiler already chooses the right SUB/SBB direction and
branch. This optimization only replaces how the constant reaches
the ALU (MVI A instead of LXI+MOV).

**Savings**: 12cc + 1B per instance. More importantly, **frees the
register pair** (DE in the example) which was only holding the
constant. This reduces register pressure, potentially avoiding
spills elsewhere on the register-starved 8080.

## Implementation

### Preferred: Extend V6CLANG_BR_CC16_IMM expansion

Reuse the existing pseudo but expand differently for ordering conditions
(ULT/UGE/UGT/ULE/SLT/SGE) versus EQ/NE conditions. The pseudo already
has a `$cc` operand.

For EQ/NE (unchanged):
```
MVI A, lo8(const); CMP regLo; [branch]; MVI A, hi8(const); CMP regHi
```

For ordering conditions (new):
```
MVI A, lo8(const); SUB regLo; MVI A, hi8(const); SBB regHi; [branch]
```

The key difference: EQ/NE can early-escape per byte (any mismatch is
decisive), while ordering must process both bytes via the borrow chain
before branching.

### ISel matching

In `V6ClangISelLowering.cpp` `LowerBR_CC()`, match `SETULT`/`SETUGE`/
`SETUGT`/`SETULE`/`SETLT`/`SETGE` with `ConstantSDNode` or
`V6ClangISD::Wrapper` RHS → emit `V6CLANG_BR_CC16_IMM` instead of the
register-based SUB/SBB path.

The pseudo expansion reads the `$cc` operand to decide:
- EQ/NE → existing MVI+CMP per-byte with early escape
- Ordering → MVI+SUB, MVI+SBB, then single conditional branch

### Why not SUI/SBI?

On standard 8080, `SUI D8` and `SBI D8` cost the same as `MVI+SUB r`
in bytes (2B each). But on Vector-06c, `SUB R` = 4cc while `SUI D8` =
8cc. The MVI+SUB/SBB approach saves 8cc over SUI/SBI for the same
code size (6B), because MVI loads A for free (no flag side effects)
and register ALU ops are the cheapest instruction class on V6CLANG.

| Approach          | Cycles | Bytes | Reg pair freed? |
|-------------------|--------|-------|-----------------|
| LXI + SUB/SBB    | 36cc   | 7B    | No (uses DE)    |
| SUI/SBI           | 32cc   | 6B    | Yes             |
| **MVI + SUB/SBB** | **24cc** | **6B** | **Yes**       |

### Why not early-escape for ordering?

The EQ/NE pattern uses one branch per byte (RNZ/JNZ) for early escape.
Ordering comparisons would need TWO branches per byte (e.g., JC + JNZ)
to distinguish the three outcomes (less/equal/greater) — costing 24cc
per byte vs 12cc for the flat SUB/SBB chain. The SBB borrow chain
achieves the cascade in 4cc, making it strictly better.

## Benefit

- **Savings**: 12cc + 1B per instance (vs current LXI+SUB/SBB)
- **Register pressure**: Frees one register pair per comparison — most
  impactful benefit on the register-starved 8080
- **Coverage**: All six ordering conditions (ULT, UGE, UGT, ULE, SLT, SGE)
- **Frequency**: High — ordering comparisons with constants appear in
  array bounds checks, loop limits, range validation, protocol parsing

## Complexity

Medium. ISel matching (~20 lines) + expansion (~15 lines) + lo8/hi8
MCExpr already exists from the immediate CMP work.

## Risk

Low. MVI not affecting flags is fundamental 8080 behavior. The SUB/SBB
borrow chain semantics are identical whether the constant comes from a
register or from A loaded via MVI.

## Dependencies

None. lo8/hi8 MCExpr infrastructure already exists.

## Testing

1. New lit test: `br-cc16-imm-ord.ll` — all six ordering conditions
   with constant RHS (ULT, UGE, UGT, ULE, SLT, SGE)
2. Golden test regression check
