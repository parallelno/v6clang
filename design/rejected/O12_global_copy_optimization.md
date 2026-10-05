# O12. Global Copy Optimization (Cross-BB)

*Inspired by llvm-mos `MOSCopyOpt`.*
*Detailed analysis: [llvm_mos_analysis.md](llvm_mos_analysis.md) §S3.*

## Problem

V6CLANG's current peephole (`V6ClangPeephole.cpp`) only analyzes within a single
basic block. Copy chains that span basic blocks — common after register
allocation when values flow through multiple blocks via copies — are missed.

## How llvm-mos Does It

`MOSCopyOpt` performs three inter-BB optimizations on COPY instructions:

1. **Copy forwarding**: For `COPY dst, src`, finds all reaching definitions
   of `src` across BBs. If all are `COPY src, newSrc` with the same `newSrc`,
   rewrites to `COPY dst, newSrc` (when `copyCost(dst, newSrc) ≤ copyCost(dst, src)`).
2. **Load-immediate rematerialization**: If all reaching defs of a COPY source
   are the same `MoveImmediate`, rematerializes the immediate at the use site.
3. **Dead copy elimination**: Removes copies with dead destinations, then
   recomputes basic block liveness.

Uses `findReachingDefs()` — backward walk through predecessor blocks with
visited-set tracking — and `isClobbered()` — forward walk from each reaching
def to verify the new source isn't modified along any path.

## V6CLANG Adaptation

- Replace the COPY-centric logic with `MOV`-centric logic for V6CLANG physical
  registers (post-RA, all registers are physical).
- Use `V6ClangInstrCost` ([O11](O11_dual_cost_model.md)) for copy cost comparisons.
- The reaching-def infrastructure translates directly — `modifiesRegister()`
  with TRI works the same way.
- **Supersedes O1** (single-BB redundant MOV elimination) — O12 catches
  everything O1 catches plus cross-BB patterns and immediate rematerialization.

## Before → After

```asm
; BB1:                              ; BB1:
  MOV  A, M      ;  8cc              MOV  A, M      ;  8cc
  MOV  C, A       ;  8cc             MOV  C, A       ;  8cc
  JNZ  BB2                           JNZ  BB2
; BB2:                              ; BB2:
  MOV  A, C       ;  8cc  ← elim    ADD  E          ;  4cc  (A already == C's value)
  ADD  E          ;  4cc
```

## Benefit

- **Savings per instance**: 8cc + 1 byte per eliminated copy
- **Frequency**: Very high — copy chains after regalloc are pervasive
- **Compound effect**: Fewer live ranges → less register pressure → fewer spills

## Complexity

Medium. ~200 lines. Inter-BB analysis requires careful handling of loop
back-edges and entry block boundaries.

## Risk

Low. Only rewrites when provably cheaper and not clobbered along any path.

## Conclusion

After eight C variants and four hand-written `.ll` variants, **no test
case produced a redundant cross-BB MVI/MOV that would benefit from O12**.
Every "obvious" pattern was already collapsed by either LLVM's stock
SSA + regalloc + branch-folder + sink, or by an existing V6CLANG pass.

The original O12 plan (drafted before O11/O17/O27/O28/O29/O36/O17 etc.
were implemented) cited "very high frequency" of cross-BB copy chains.
That assessment was based on llvm-mos's pre-existing pipeline, which
lacks several of the passes V6CLANG now has. On the current V6CLANG pipeline,
the residual opportunity is empirically near zero.

**Recommendation:** Move `O12_global_copy_optimization.md` to
`design/rejected/` with a note explaining that the optimization was
made redundant by the cumulative effect of O1, O11, O17, O29, O36, and
LLVM's stock `branch-folder` / `tail-duplication` / `MachineSink`
passes. If a future workload exposes a real instance, revisit then.
