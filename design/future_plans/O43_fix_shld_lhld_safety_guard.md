# O43-fix. SHLD/LHLD→PUSH/POP Safety Guard (Uncovered Reader Check)

*Bug found while analyzing O16 (store-to-load forwarding) interaction with*
*O43 on the `interleaved_add` loop in static-stack mode.*

## Problem

O43 (`foldShldLhldToPushPop`) replaces adjacent `SHLD addr` / `LHLD addr`
pairs with `PUSH HL` / `POP HL` when they are in the same basic block with
SP delta == 0. This is sound when the SHLD/LHLD pair is the only
reader/writer of that address within the reachable code. However, it is
**unsound** when another `LHLD addr` elsewhere in the function depends on
the SHLD's writeback to the static slot.

### Example (interleaved_add loop, static stack)

```asm
.LBB0_2:                          ; loop header
        LHLD    __v6clang_ss+0        ; (B) reads src2 ptr from static slot
        ...
        INX     HL                ; advance src2 ptr
        SHLD    __v6clang_ss+0        ; (C) write back updated ptr → O43 folds to PUSH HL
        LHLD    __v6clang_ss+0        ; (D) reload (RA artifact) → O43 folds to POP HL
        ...
        JNZ     .LBB0_2           ; loop
```

O43 sees (C)→(D) as an adjacent pair within the same BB, SP delta == 0,
and folds them to `PUSH HL; POP HL`. But this removes the writeback to
`__v6clang_ss+0` — on the next iteration, (B) reads the stale original pointer.
The loop processes `src2[0]` every iteration instead of `src2[i]`.

### Root cause

`foldShldLhldToPushPop` only scans **forward** from each SHLD to find a
matching LHLD. It does not check whether any other LHLD of the same address
is reachable from the folded LHLD — either earlier in the same BB (via loop
back-edge) or in any other BB in the function.

### Scope of the bug

Any static-stack variable that has:
- A SHLD/LHLD pair that O43 folds (value written and immediately reloaded)
- Another LHLD of the same address reachable via a loop back-edge or
  cross-BB path without an intervening SHLD covering it

This is most common in single-BB loops where the RA emits a spill+reload
pair for a value that is also loaded at the top of the loop.

### Why it went undetected

Without O16: the PUSH/POP pair from the fold is harmless because the POP
restores HL to the same value, and the INX that follows advances the
in-register copy. The stale `__v6clang_ss+0` is masked if HL happens to be
re-stored by another path. In the specific `interleaved_add` case, the
bug has been present but the incorrect output wasn't verified against
expected values.

With O16: O16 eliminates the RELOAD16 before expansion, so only the SPILL16
remains. It expands to SHLD — with no adjacent LHLD, O43 can't fold it.
The SHLD correctly writes back. So O16 accidentally masks the O43 bug.

## Solution

Add a CFG-aware safety guard before committing the fold. Walk forward
from the folded LHLD through the CFG (using `MBB.successors()`) to check
if any other `LHLD addr` is reachable without passing through a covering
`SHLD addr` first.

### Algorithm: `isUncoveredLhldReachable`

Input: the MBB containing the fold, the position after the folded LHLD (D),
the address operand, and the position of the SHLD (C) being folded.

1. **Remainder of current BB (after D)**: scan instructions. Hit
   `SHLD addr` → path covered, return false. Hit `LHLD addr` → unsafe,
   return true.
2. **BFS through successor BBs**: for each unvisited successor, scan from
   top of BB. Hit `SHLD addr` first → don't follow successors (covered).
   Hit `LHLD addr` first → unsafe, return true. Neither → add successors
   to worklist.
3. **Self-loop** (successor == current BB): scan from BB top to SHLD(C)'s
   position (C is being folded, so it doesn't count as a covering store).
   Hit `LHLD addr` → unsafe.
4. **Worklist exhausted** → no uncovered reader → safe to fold.

### Correctness argument

The fold removes the write to `addr`. The only way this breaks is if some
LHLD is reachable from the fold point without passing through another SHLD
that re-establishes the value. The BFS explores every reachable path. Any
SHLD on a path kills propagation (that reader is covered). Any uncovered
LHLD is a stale reader — fold must be blocked.

Irreducible control flow is handled correctly because the BFS doesn't rely
on dominator trees or loop headers — it visits all reachable BBs.

### Cost

O(n) per candidate fold, where n = total instructions in reachable BBs.
Each BB visited at most once. 8080-sized functions have ~50-200 instructions
and ~1-3 SHLD/LHLD pairs — negligible compile-time cost.

### Conservatism

This is slightly conservative — it may block a fold when an LHLD is
reachable but actually covered by a different SHLD on every path. A fully
precise analysis would require reaching-definitions with full dataflow,
which is too heavy for a peephole. The conservative approach is correct
and loses very few fold opportunities in practice.

## Interaction with other optimizations

- **O16 (store-to-load forwarding)**: O16 removes the RELOAD16 pseudo
  before expansion, so the adjacent SHLD/LHLD pair never exists. O16
  masks this bug and composes correctly with the fix.
- **O42 (liveness-aware expansion)**: Unaffected — O42 operates on pseudo
  expansion, O43 operates on expanded SHLD/LHLD instructions.
- **O44 (XCHG cancellation)**: Unaffected — runs before O43.

## Testing

- **Positive test**: sumarray loop — the `ss+0` SHLD/LHLD pair should
  still fold to PUSH/POP (the LHLD at loop top has a covering SHLD at
  loop top, so BFS finds it covered).
- **Negative test**: interleaved_add loop in static-stack mode — the
  SHLD/LHLD pair for `ss+0` should NOT fold because the LHLD at the top
  of the loop body is reachable without a covering SHLD.
- **Regression**: existing lit test `shld-lhld-push-pop-peephole.ll`
  must still pass (sumarray uses `--enable-deferred-spilling`).
