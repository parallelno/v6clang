# O37. Deferred Zero-Load After Zero-Test

*Identified from O36 analysis of `test_cond_zero_return_zero`.*
*ISel scheduling / post-RA restructuring opportunity.*

## Problem

When both paths after a zero-test need HL=0, the compiler hoists
`LXI HL, 0` *before* the branch. This forces the zero-test to move
to DE, adding a register shuffle:

```c
int test_cond_zero_return_zero(int x) {
    if (x == 0) return bar(0);
    return 0;
}
```

Current output (11 bytes):
```asm
test_cond_zero_return_zero:
    MOV  D, H          ; 1B, 8cc — save x to DE
    MOV  E, L          ; 1B, 8cc
    LXI  HL, 0         ; 3B, 12cc — hoist: both paths need HL=0
    MOV  A, D          ; 1B, 8cc — zero-test via DE
    ORA  E             ; 1B, 4cc
    JZ   bar           ; 3B, 12cc
    RET                ; 1B, 12cc
```

### Desired output (7 bytes)

```asm
test_cond_zero_return_zero:
    MOV  A, H          ; 1B, 8cc — zero-test directly on HL
    ORA  L             ; 1B, 4cc
    JZ   bar           ; 3B, 12cc — HL already 0 (proven by branch)
    LXI  HL, 0         ; 3B, 12cc — only needed on NZ path (return 0)
    RET                ; 1B, 12cc
```

On the zero path, HL is already 0 (branch-proven), so `bar(0)` gets
HL=0 for free. On the non-zero path, `LXI HL, 0` covers `return 0`.

### Savings

**Direct savings:** 4 bytes, 16cc (11B → 7B) from eliminating
`MOV D,H; MOV E,L` and testing HL directly.

**Cascading savings (register pressure):** The direct savings
understate the true cost. The i8080 has only 3 register pairs
(HL, DE, BC). Hoisting a constant before a branch consumes **two**
of them — one for the constant (HL), one for the evicted value (DE).
This leaves only BC for everything else in the block.

In any non-trivial function with additional live values (loop counter,
pointer, second argument), RA has no choice but to spill. Each spill
on the i8080 costs:
- **PUSH/POP:** 2B, 24cc minimum
- **Stack store/load via HL:** clobbers HL → another eviction cascade

A single premature constant materialization can trigger 2-3 extra
spills, costing **50-150cc and 6-18B of cascading damage**. The real
optimization target is not the 4 bytes saved — it's preventing the
spill cascade by keeping DE free for RA.

## Root Cause

ISel sees that both successors of the `icmp eq i16 %x, 0` branch
use the constant `i16 0` (one as `bar(0)`, one as `return 0`).
It materializes the constant once in the common dominator (entry block)
before the branch. Since HL is needed for the constant, the live value
`x` in HL must first be saved to DE.

The compiler doesn't realize that on the zero-taken path, HL is
*already* 0 from the branch condition itself — it doesn't need the
hoisted `LXI HL, 0`.

## Key Constraint: Must Free DE Before RA

A post-RA fix cannot recover from the register pressure damage.
By the time RA runs, it sees `LXI HL, 0` clobbering HL before the
branch, allocates DE for the copy of `x`, and makes all spilling
decisions with DE occupied. Even though `LXI` and `MVI` are already
marked `isReMaterializable = 1, isAsCheapAsAMove = 1`, RA only
rematerializes to avoid spills — it won't remat just to free a pair
that isn't causing a spill.

The solution must act **before RA** to prevent the conflict.

## Implementation — Pre-RA Constant Sinking

A custom V6CLANG pass that runs **before RA**. For each constant
materialization (`LXI rp, imm` / `MVI r, imm`) in a block ending
with a conditional branch:

1. Check the def is used only in successor blocks (not between the
   def and the terminator, except by the branch condition pattern)
2. Clone the constant materialization into the start of each
   successor that uses it
3. Erase the original from the dominator

RA then sees two short live ranges (one per successor) instead of
one long range spanning the branch. HL stays live with `x` in the
dominator — DE is never allocated for the copy.

After RA, O36 eliminates the cloned `LXI HL, 0` on the zero-taken
path (branch-proven value).

**Iteration order: reverse post-order (RPO).** The same two-successor
problem can recur at deeper levels — if BB1 also ends with a branch
and both of BB1's successors use the constant, MachineSink won't
sink the clone either. RPO iteration (dominators before successors)
handles arbitrary depth in a single pass:

```
RPO iteration:
1. BB0: LXI used only in BB1, BB2 → clone into BB1, BB2; erase from BB0
2. BB1: clone used only in BB3, BB4 → clone into BB3, BB4; erase from BB1
3. BB2: clone used locally → keep; stop sinking
```

Each block is visited once. Each constant pushed one level deeper per
visit. The check at each block is the same: "is this constant def used
only in successor blocks, not locally?" If yes → clone and erase.
If used locally → stop.

Complexity: Medium. ~60-80 lines. Pre-RA on virtual registers.

**Frees DE: YES.** RA never sees the HL conflict.

## Scope

The optimization must cover **all registers**, not just HL pairs:
- **LXI**: HL, DE, BC (16-bit pairs)
- **MVI**: A, B, C, D, E, H, L (individual 8-bit registers)

The sinking logic should be register-agnostic — sink any constant
materialization (`LXI rp, imm` or `MVI r, imm`) past a branch when
it can be proven redundant on one path (via O36 branch-implied values).

**Testing note**: Create tests that verify sinking works for each
register individually (MVI A; MVI B; MVI C; MVI D; MVI E; MVI H;
MVI L) and each pair (LXI HL; LXI DE; LXI BC), not just the HL case.

## Frequency

Medium — occurs whenever both paths of a zero-test need the same
zero constant (e.g., `if (x==0) call(0); return 0;`).

---

## Rejected Approaches

### Post-RA Peephole (Sink LXI past branch)

Pattern-match `MOV D,H; MOV E,L; LXI HL,0; MOV A,D; ORA E; Jcc`
and rewrite to `MOV A,H; ORA L; Jcc; LXI HL,0`.

**Rejected:** Does NOT free DE. RA already allocated DE for the
copy. Spill damage is baked in. Cleans up the symptom, not the cause.

### ISel Constant Placement

Teach ISel to place the constant in each successor instead of
hoisting to the dominator. RA never sees HL conflict, DE stays free.

**Rejected:** Too complex. Requires branch-semantic reasoning at the
DAG level before register assignment. ISel doesn't normally reason
about whether a branch condition implies a constant's value.

### MachineSink (standard LLVM pass)

Standard MachineSink only sinks a def when exactly one successor
uses it. Here both successors use `HL = 0`, so it won't fire.
Would need to **clone** (duplicate) the materialization — an
operation MachineSink doesn't support.

**Rejected:** Won't fire at all for the two-successor case.

### Approach Comparison

| Approach | Frees DE? | Complexity | Notes |
|----------|-----------|------------|-------|
| Post-RA peephole | **No** | Medium | Register pressure damage already done |
| ISel placement | **Yes** | High | DAG-level, hard to reason about branches |
| MachineSink | **No** | — | Won't fire: both successors use constant |
| **Pre-RA sinking** | **Yes** | **Medium** | **Chosen.** Prevents HL conflict before RA |
