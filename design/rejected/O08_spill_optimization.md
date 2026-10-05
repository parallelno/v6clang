# O8. Spill Optimization (Tier 1/2 Strategy)

## Resolution
Superseeded by O10 (static stack), O61 (spill-patched reload).

## Problem

Stack-relative addressing on the 8080 costs **~52cc per spill or reload**
(104cc per pair, 16 bytes) because there are no stack-relative load/store
instructions. Every stack access requires:

```asm
PUSH HL               ; save scratch pair
LXI  HL, offset       ; load stack offset
DAD  SP               ; HL = SP + offset
MOV  M, lo / MOV lo,M ; store/load low byte
INX  HL               ; advance pointer
MOV  M, hi / MOV hi,M ; store/load high byte
POP  HL               ; restore scratch pair
```

This dominates inner loops whenever two 16-bit pointers are live simultaneously.

## Tiered Approach

| Tier | Mechanism | Cost | Constraints |
|------|-----------|------|-------------|
| **T1** | PUSH/POP | 28cc/pair | Same-BB, LIFO nesting, no intervening branches/calls |
| **T2** | SHLD/LHLD or STA/LDA (global bss slots) | 40cc/pair | Non-reentrant, same-BB or cross-BB |
| **T3** | Current stack-relative (fallback) | 104cc/pair | Always safe |

Selection priority: T1 → T2 → T3. Each tier's constraints checked statically.

## Implementation

A new `V6ClangSpillOpt` MachineFunction pass running **before** `eliminateFrameIndex()`:

1. **Inventory**: Scan for SPILL/RELOAD pseudos, classify by slot
2. **LIFO analysis**: Check bracket nesting for T1 eligibility
3. **Safety checks**: FLAGS liveness (for PUSH PSW), intervening control flow,
   stack mutations
4. **Rewrite**: Convert eligible slots to PUSH/POP (T1) or global symbols (T2),
   erase original pseudos
5. **Integration**: Mark converted slots so frame lowering skips stack allocation

**Detailed design**: [../design_improve_spilling.md](../design_improve_spilling.md)

## Benefit

- **T1 savings**: 28cc vs 104cc per pair = **3.7× faster** spill-reload
- **T2 savings**: 40cc vs 104cc per pair = **2.6× faster**
- **Cascading**: Freed stack space → smaller frame → fewer prologue/epilogue cycles
- **Frequency**: Very high in any code with >1 live pointer (loops, struct access)

## Complexity

High. Requires LIFO verification algorithm, global symbol management,
integration with frame lowering pipeline (`MachineFrameInfo` slot marking,
prologue size adjustment).

## Risk

Medium-high. T1 is dangerous if LIFO nesting is violated (silent corruption).
T2 breaks reentrancy. Both require careful analysis and extensive testing.
