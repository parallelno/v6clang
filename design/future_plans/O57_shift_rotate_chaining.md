# O57. Shift/Rotate Chaining

*Inspired by llvm-mos `MOSShiftRotateChain` / llvm-z80 `Z80ShiftRotateChain`.*
*Detailed analysis: [llvm_mos_analysis.md](llvm_mos_analysis.md) §S6,
[llvm_z80_analysis.md](llvm_z80_analysis.md) §S12.*

## Problem

When multiple shifts of the same base value by different constant amounts
exist in the same function (e.g., `x << 3` and `x << 5`), each is computed
independently from scratch. On the 8080, shifts are linear-time (one
RLC/RRC/RAL/RAR per bit), so `x << 5` requires 5 rotates + masking.

If `x << 3` already exists and dominates the `x << 5` use, we can compute
`x << 5` as `(x << 3) << 2` — reusing the intermediate result and saving
3 rotates.

## How llvm-mos Does It

A pre-legalize `MachineFunctionPass` (~120 lines) operating on GlobalISel
`G_SHL`, `G_LSHR`, `G_ASHR`:

1. Collect all constant shifts of RSA (register-shifted-by-amount) form
2. Group by base value (same SSA def)
3. For each group, sort by shift amount
4. Chain: rewrite `SHL x, 5` as `SHL (SHL x, 3), 2` when `SHL x, 3` exists
5. Use dominance analysis to verify the shorter shift dominates the longer
6. If not, hoist the shorter shift up to the common dominator

## V6CLANG Adaptation

The 8080's shift situation:
- **8-bit shifts**: RLC/RRC (4cc each), RAL/RAR (4cc each, through carry)
- **16-bit shifts**: Multi-instruction (shift low byte, rotate high byte)
- Each bit position costs 4-8cc depending on width

Chaining is most valuable for **16-bit shifts**, where each bit costs
~12cc (shift L, rotate carry into H). Saving 3 bit positions saves ~36cc.

Since V6CLANG uses SelectionDAG (not GlobalISel), the pass would operate on
`ISD::SHL`, `ISD::SRL`, `ISD::SRA` nodes during DAGCombine, or as a
post-ISel MachineFunction pass on the expanded shift sequences.

## Before → After

```asm
; x << 3 (already computed, in DE)
; x << 5 computed from scratch:
; Before                              ; After
MOV  A, x_lo                         MOV  A, E       ; reuse x<<3 low
RAL          ; ×5 iterations          RAL             ; ×2 iterations
MOV  L, A                            RAL
MOV  A, x_hi                         MOV  L, A
RAL          ; ×5 iterations          MOV  A, D       ; reuse x<<3 high
...                                   RAL
; ~60cc for 16-bit << 5               RAL
                                      ...
                                      ; ~24cc for 16-bit << 2
```

## Benefit

- **Savings per instance**: 4-12cc per eliminated bit position (8-bit),
  8-24cc per position (16-bit)
- **Frequency**: Low — multiple shifts of the same value are uncommon in
  typical 8080 embedded code
- **Best use case**: Bit manipulation code, protocol parsers, graphics routines

## Complexity

Medium. ~120 lines. Requires dominance analysis for hoisting decisions.

## Risk

Low. SSA-based correctness guaranteed by dominance relationship. Only
rewrites when provably profitable (fewer total shift operations).

## Dependencies

None. Operates independently. Lower priority than loop and spill optimizations.
