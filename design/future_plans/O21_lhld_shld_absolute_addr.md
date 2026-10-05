# O21. LHLD/SHLD 16-bit Absolute Address Patterns

*From plan_lda_sta_absolute_addr.md Future Enhancements.*
*Extension of O6 (LDA/STA for 8-bit absolute address) to 16-bit.*

## Problem

16-bit loads/stores from global variables use `LXI HL, addr; MOV r, M;
INX HL; MOV r, M` (or the store equivalent). The 8080 has dedicated
instructions for 16-bit absolute access:

- **LHLD addr** — Load HL from [addr] and [addr+1] (16cc, 3B)
- **SHLD addr** — Store HL to [addr] and [addr+1] (16cc, 3B)

These are single instructions that replace multi-instruction sequences.

### Current output (i16 global load):
```asm
LXI  HL, global_var     ; 10cc, 3B
MOV  E, M               ;  7cc, 1B
INX  HL                  ;  6cc, 1B
MOV  D, M               ;  7cc, 1B
; Total: 30cc, 6B (value in DE)
```

Or when loading into HL:
```asm
LXI  HL, global_var     ; 10cc, 3B
MOV  C, M               ;  7cc, 1B  (save low byte)
INX  HL                  ;  6cc, 1B
MOV  H, M               ;  7cc, 1B
MOV  L, C               ;  8cc, 1B
; Total: 38cc, 7B (value in HL, clobbers C)
```

### Expected output:
```asm
LHLD global_var          ; 16cc, 3B (value in HL)
```

## Implementation

ISel patterns in `V6ClangInstrInfo.td` matching `(load globaladdr)` for i16
when destination is HL, and `(store HL, globaladdr)` for SHLD.

```tablegen
def : Pat<(i16 (load (V6ClangWrapper tglobaladdr:$addr))),
          (LHLD tglobaladdr:$addr)>;

def : Pat<(store GR16Ptr:$src, (V6ClangWrapper tglobaladdr:$addr)),
          (SHLD tglobaladdr:$addr)>;
```

**Constraint**: LHLD always loads into HL, SHLD always stores from HL.
The register allocator must be aware that the result/source is fixed to HL.
This is already the case for `GR16Ptr`.

If the i16 value is needed in DE or BC, the RA will insert a copy from HL.
Even with the copy, LHLD+MOV D,H+MOV E,L (32cc, 5B) is still faster than
the current LXI+MOV+INX+MOV sequence (30cc, 6B) — similar cycles but saves
1 byte. The real win is when HL is the natural destination.

## Benefit

- **Savings**: 14-22cc + 3-4B per instance (depending on current sequence)
- **Frequency**: Medium — every i16 global variable access
- **Size**: Always saves bytes (3B vs 6-7B)

## Complexity

Low. ISel patterns only — no new pseudo, no expansion code.
Similar to O6 (LDA/STA) which is already implemented.

## Risk

Very Low. LHLD/SHLD are well-defined 8080 instructions.
Only concern: HL is the fixed register, which may increase HL pressure.

## Dependencies

None. Independent of all other optimizations. O6 is the 8-bit counterpart.

## Testing

1. New lit test: `lhld-shld.ll` — global i16 load/store patterns
2. Golden test regression check
