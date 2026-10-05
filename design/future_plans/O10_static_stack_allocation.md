# O10. Static Stack Allocation for Non-Reentrant Functions

*Inspired by llvm-mos `MOSNonReentrant` + `MOSStaticStackAlloc`.*
*Detailed analysis: [llvm_mos_analysis.md](llvm_mos_analysis.md) §S1.*

## Problem

Stack-relative addressing costs ~52cc per access (see [O08](O08_spill_optimization.md)). For functions
that are provably non-reentrant (at most one active invocation at any time),
the entire stack frame can be replaced with a statically-allocated global
memory region — turning every spill/reload into a direct `LDA`/`STA` or
`LHLD`/`SHLD` (16-20cc).

## How llvm-mos Does It

Two passes working together:
1. **NonReentrant analysis** (IR-level, `ModulePass`): Walks the call graph
   bottom-up via SCC iteration. Single-node SCCs that don't call themselves
   are marked `norecurse`. Functions reachable from interrupts are marked
   reentrant. All remaining `norecurse` functions get the `nonreentrant`
   attribute.
2. **StaticStackAlloc** (`ModulePass`, runs post-RA): Builds an SCC DAG from
   the call graph, assigns static stack offsets per SCC (callers lower,
   callees higher — enabling memory overlap for disjoint call paths). Creates
   a single global `static_stack` array and per-function aliases into it.
   Rewrites all `TargetIndex` operands to `GlobalAddress`.

## V6CLANG Adaptation

- The NonReentrant analysis is **target-independent** — reusable as-is.
- StaticStackAlloc needs adaptation for V6CLANG frame lowering (different pseudo
  names, `MachineFrameInfo` conventions), but the SCC offset algorithm is
  directly reusable.
- **Supersedes O8 T2** (ad-hoc global bss variables) with automatic,
  optimally-packed static allocation with overlap analysis.
- O8 T1 (PUSH/POP) remains orthogonal and complementary — T1 for LIFO-safe
  slots within a BB, static stack for everything else.
- **Requires whole-program visibility** (LTO or single-TU compilation, which
  is the norm for 8080 programs).

## Benefit

- **Savings**: 52cc → 16-20cc per spill/reload access = **3-5× faster**
- **Frequency**: Every function with a stack frame (most non-trivial functions)
- **Cascading**: Eliminated stack frames → no prologue/epilogue overhead →
  smaller code

## Complexity

Medium. Two new passes. Call graph analysis is robust (borrowed from llvm-mos
who have battle-tested it). Frame lowering integration is the main work.

## Risk

Medium. Must correctly identify reentrant functions (interrupt handlers,
recursive calls). Conservative fallback (T3 stack-relative) is always safe.
