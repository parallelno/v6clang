# llvm-mos Optimization Strategies — Applicability Report for V6CLANG

Analysis of https://github.com/llvm-mos/llvm-mos (`llvm/lib/Target/MOS/`)
targeting the MOS 6502 and its variants. Evaluated for adaptation to the
V6CLANG backend (Intel 8080 / Vector 06c).

---

## Architecture Comparison: 6502 vs 8080

| Property | MOS 6502 | Intel 8080 (V6CLANG) |
|----------|----------|-------------------|
| GPRs | A, X, Y (3 × 8-bit) | A, B, C, D, E, H, L (7 × 8-bit) |
| Register pairs | None (A is accumulator-only) | BC, DE, HL (3 × 16-bit) |
| Memory pointer | Zero page indirect via (ZP),Y | HL only (BC/DE for LDAX/STAX) |
| Indexed addressing | ZP,X / ZP,Y / abs,X / abs,Y / (ZP),Y | None |
| Stack addressing | Hardware stack at page 1, no random access | No stack-relative addressing |
| ALU | Accumulator-only, sets NZ flags | Accumulator-only, sets all flags |
| Zero Page | 256 bytes of fast-access memory (3cc vs 4cc) | No equivalent |
| Code model | 16-bit pointers, 64K address space | 16-bit pointers, 64K address space |

**Key insight**: The 8080 has *more* registers but *fewer* addressing modes.
The 6502 compensates for its tiny register file with zero-page "soft registers"
and indexed addressing. Many llvm-mos optimizations address the same
fundamental problems V6CLANG faces (accumulator bottleneck, expensive pointer
arithmetic, spilling costs), but through different mechanisms.

---

## llvm-mos Optimization Passes (Complete Inventory)

### Pass Pipeline Order (from MOSTargetMachine.cpp)

```
IR Passes:
  1. MOSNonReentrant        — Mark non-reentrant functions
  2. Standard IR passes + InstCombine cleanup

Pre-Legalize (GlobalISel):
  3. MOSCombiner            — Target-specific DAG combines
  4. MOSShiftRotateChain    — Chain constant shifts to build on each other

Post-Legalize:
  5. MOSCombiner (2nd run)
  6. MOSLowerSelect         — Lower G_SELECT to diamond CFG
  7. MOSInternalize         — Internalize libcalls for static linking
  8. MOSInsertCopies        — Widen regclasses around shifts/rotates

Machine SSA + RegAlloc:
  9. Double register coalescing (two-address + coalescer run twice)
 10. Standard optimized regalloc

Post-RA Late Optimization:
 11. MOSCopyOpt             — Global copy propagation + LdImm forwarding
 12. MOSZeroPageAlloc       — Whole-program zero-page allocation
 13. MOSPostRAScavenging    — Scavenge physical registers for pseudos
 14. FinalizeISel + ExpandPostRAPseudos
 15. MOSLateOptimization    — CmpZero elimination, LdImm combining, tail JMP
 16. MOSStaticStackAlloc    — Allocate non-recursive stacks to static memory

Pre-Emit:
 17. BranchRelaxation

Loop Optimization (via PassBuilder callbacks):
 18. MOSIndexIV             — Rewrite loop GEPs to use 8-bit index IVs
```

---

## Strategies Ranked by Impact × Feasibility for V6CLANG

### S1. Static Stack Allocation for Non-Reentrant Functions

**llvm-mos passes**: `MOSNonReentrant` + `MOSStaticStackAlloc`

**What it does**: Analyzes the whole-program call graph to find functions that
can never be active more than once simultaneously (non-reentrant). For those
functions, replaces the hardware stack frame with a statically-allocated global
memory region. SCCs share overlapping regions; functions with disjoint call
paths share the same static memory.

**How it works**:
1. `MOSNonReentrant` walks the call graph bottom-up, marks `norecurse` functions,
   then conservatively handles interrupts (all functions reachable from interrupts
   are marked reentrant; `interrupt-norecurse` gets special handling).
2. `MOSStaticStackAlloc` builds an SCC DAG from the call graph, assigns static
   stack offsets to each SCC based on caller/callee relationships (callers get
   lower offsets, callees higher), creates a single global `static_stack` array,
   and creates per-function aliases into it. All `TargetIndex` operands pointing
   to framework slots are rewritten to `GlobalAddress` operands.

**V6CLANG adaptation**:
- **Directly applicable and extremely high impact.** The 8080 has the same
  problem as the 6502: no stack-relative addressing, so every stack access
  costs ~52cc (LXI+DAD SP+MOV sequence). Static allocation turns these into
  direct `LDA`/`STA` or `LHLD`/`SHLD` (16-20cc) — a **3-5× speedup** per
  spill/reload.
- The `MOSNonReentrant` analysis is target-independent (call graph analysis).
  Can be reused almost verbatim for V6CLANG.
- `MOSStaticStackAlloc` would need adaptation for V6CLANG's frame lowering
  (different pseudo names, different `MachineFrameInfo` conventions), but the
  SCC-based offset assignment algorithm is directly reusable.
- **This subsumes and improves upon the planned V6CLANG O8 (Spill Optimization
  Tier 2)** — instead of per-slot global bss variables, you get a single
  optimally-packed static stack with automatic overlap analysis. The T1
  (PUSH/POP) strategy from O8 remains orthogonal and can work alongside it.

| Metric | Value |
|--------|-------|
| **Impact** | **Very High** — 3-5× faster spill/reload, affects every function with stack frames |
| **Complexity** | Medium — 2 new passes, call graph analysis is target-independent |
| **Risk** | Medium — must handle interrupts and recursion correctly |
| **V6CLANG prerequisites** | Linker must support global aliases; need LTO-like whole-program compilation |
| **Similar to** | O8 (Spill Optimization T2) — but more general and automatic |

---

### S2. Index Induction Variable Rewriting (8-bit Loop Indices)

**llvm-mos pass**: `MOSIndexIV`

**What it does**: An IR-level loop pass that finds GEP instructions with SCEV
add-recurrences of the form `Base + Index` where the index fits in an unsigned
8-bit integer. It splits these into a 16-bit base pointer and an 8-bit index
IV, connected by a zero-extension.

**How it works**:
1. For each GEP in a loop, checks if the SCEV is an `AddRecExpr`
2. Verifies both the step and the full index range fit in `[0, 255]`
3. Rewrites `GEP base, index_i16` → `GEP base_ptr, zext(index_i8)`
4. Uses `SCEVExpander` with canonical mode disabled for minimal expansion
5. Runs at `registerLateLoopOptimizationsEPCallback`, followed by `IndVarSimplify`

**V6CLANG adaptation**:
- **High impact for loops with bounded iteration counts** (very common in
  embedded 8080 code: `for (i = 0; i < 100; i++) array[i] = ...`).
- On the 8080, keeping the loop counter in 8 bits means using `DCR` (4cc)
  instead of 16-bit decrement (DCX + compare, ~18cc). The pointer base can
  stay in HL while the index increment is just `INR L` or `INX HL`.
- This pass operates entirely at the IR level using SCEV, so it's
  **target-independent** — can be reused with minimal changes (just the
  address space check on line `R->getType()->getPointerAddressSpace()`).
- **Complements the planned O7 (Loop Strength Reduction via TTI)** — IndexIV
  narrows the index to 8 bits; TTI-based LSR then decides whether to use
  pointer increments or indexed addressing.

| Metric | Value |
|--------|-------|
| **Impact** | **High** — 4-14cc saved per loop iteration from narrower counter |
| **Complexity** | Low — IR-level pass, almost entirely target-independent |
| **Risk** | Low — only rewrites when SCEV proves range fits in 8 bits |
| **V6CLANG prerequisites** | None (IR-level, uses SCEV) |
| **Similar to** | Complements O7 (Loop Strength Reduction) |

---

### S3. Global Copy Optimization with Cost Model

**llvm-mos pass**: `MOSCopyOpt`

**What it does**: A post-RA pass that performs three optimizations on COPY
instructions:
1. **Copy forwarding**: If `COPY dst, src` and all reaching definitions of
   `src` are themselves `COPY src, newSrc`, rewrite to `COPY dst, newSrc`
   (when cheaper according to the cost model).
2. **Load-immediate rematerialization**: If a COPY's source was always defined
   by the same `MoveImmediate` instruction, rematerialize the immediate load
   at the copy site (eliminating the copy chain).
3. **Dead copy elimination**: After the above, remove copies whose destinations
   are dead and recompute liveness.

**Key innovation**: Uses `MOSInstrCost` — a dual (Bytes, Cycles) cost model
that can prefer code size (`-Oz`), speed (`-O2`), or a balanced mix. Copy
forwarding only proceeds when `copyCost(dst, newSrc) ≤ copyCost(dst, src)`.

**V6CLANG adaptation**:
- **High impact.** Copy chains are extremely common on the 8080 because
  everything must flow through A. Example: `MOV A, L; MOV C, A` could
  become `MOV C, L` if the cost model says it's cheaper (it is: both are 8cc,
  but the chain is 16cc total vs 8cc).
- The `findReachingDefs` / `findForwardedCopy` / `isClobbered` infrastructure
  performs **inter-basic-block analysis** — much more powerful than V6CLANG's
  current single-BB peephole in `V6ClangPeephole.cpp`.
- **The dual cost model (`MOSInstrCost`)** is independently valuable. V6CLANG
  currently has no formal cost model; decisions in peephole/expansion passes
  are ad-hoc. Adopting Bytes+Cycles would improve all optimization decisions.
- **Subsumes and extends the planned V6CLANG O1 (Redundant MOV Elimination)** —
  O1 catches `MOV X, A; ... MOV A, X` within a BB; this catches it cross-BB
  and also handles immediate rematerialization.

| Metric | Value |
|--------|-------|
| **Impact** | **High** — eliminates redundant copies cross-BB, rematerializes immediates |
| **Complexity** | Medium — inter-BB reaching-def analysis, cost-model integration |
| **Risk** | Low — only rewrites when provably cheaper and not clobbered |
| **V6CLANG prerequisites** | Need a V6ClangInstrCost model (straightforward from timing tables) |
| **Similar to** | Supersedes O1 (Redundant MOV Elimination) |

---

### S4. Late Optimization: Load-Immediate Combining

**llvm-mos pass**: `MOSLateOptimization::combineLdImm`

**What it does**: A post-RA peephole that tracks the known values in registers
A, X, Y as it scans forward through a basic block. When it sees a
load-immediate (`LDA #imm`, `LDX #imm`, `LDY #imm`), it checks if any
register already holds that value and replaces the load with a register
transfer (e.g., `LDA #5` → `TXA` if X==5). If the value differs by ±1
from a known register, it uses `INX`/`DEX`/`INY`/`DEY` instead.

**V6CLANG adaptation**:
- **Directly applicable.** The 8080 has `MOV r, r'` (8cc, 1 byte) which is
  cheaper than `MVI r, imm` (8cc, 2 bytes) — same cycle count but saves 1
  byte. And `INR`/`DCR` (4cc, 1 byte) is cheaper than `MVI` for ±1 cases.
- Track known values in all 7 registers (A, B, C, D, E, H, L) and replace
  `MVI r, imm` with `MOV r, r'` when another register holds the same value,
  or `INR`/`DCR` when it differs by 1.
- **Extends O1** by also handling the ±1 case with INR/DCR.
- **Zero-constant optimization**: `MVI r, 0` is very common (used for zext).
  If any register already holds 0, `MOV r, known_zero_reg` saves 1 byte.

| Metric | Value |
|--------|-------|
| **Impact** | **Medium-High** — saves 1 byte per MVI replaced; INR/DCR saves 4cc+1B |
| **Complexity** | Low — single-BB forward scan tracking register values |
| **Risk** | Low — stateless, forward-only, local analysis |
| **V6CLANG prerequisites** | None |
| **Similar to** | Extension of O1, complements O5 (zero-byte detection) |

---

### S5. Compare-Zero Elimination

**llvm-mos pass**: `MOSLateOptimization::lowerCmpZeros`

**What it does**: Eliminates explicit compare-against-zero instructions by
finding a preceding instruction that already sets the NZ flags for the same
register. If such an instruction exists, the compare is deleted and the
flag-setting is marked as an implicit-def of NZ. When no preceding
flag-setter is found, it lowers the `CmpZero` pseudo to the cheapest
available sequence (transfer to dead register, or `INC; DEC` for zero-page
values).

**V6CLANG adaptation**:
- The 8080 already sets flags on most ALU operations (ADD, SUB, INR, DCR,
  ANA, ORA, XRA). V6CLANG already has `V6CLANG_ZERO_TEST` optimization. However,
  the llvm-mos approach is more thorough — it scans backward past
  instructions that are known *not* to clobber NZ (branches, stores, certain
  pseudos), finding flag-setters that V6CLANG might currently miss.
- **The "skip past known-safe instructions" approach** is the key takeaway.
  V6CLANG's current zero-test optimization likely stops at the first instruction
  that might affect flags. Extending it to skip over non-flag-affecting
  instructions (MOV, LXI, PUSH, POP without PSW) could find more
  elimination opportunities.

| Metric | Value |
|--------|-------|
| **Impact** | **Medium** — eliminates some redundant comparisons |
| **Complexity** | Low — backward scan in single BB |
| **Risk** | Low — conservative flag-liveness analysis |
| **V6CLANG prerequisites** | Accurate flag-liveness tracking in V6ClangInstrInfo |
| **Similar to** | Enhancement of existing V6CLANG ZERO_TEST pass |

---

### S6. Shift/Rotate Chaining

**llvm-mos pass**: `MOSShiftRotateChain`

**What it does**: When multiple shifts of the same base value by different
constant amounts exist (e.g., `x << 3` and `x << 5` both needed), the pass
chains them so the larger shift is computed as `(x << 3) << 2` instead of
`x << 5` from scratch. Since shifts on the 6502 are linear-time (one
rotate per bit), `3 + 2 = 5` rotates is the same as `5` rotates, but the
intermediate result `x << 3` is shared.

The pass uses dominance analysis to ensure the chained shift dominates all
its uses, moving instructions up the dominator tree as necessary.

**V6CLANG adaptation**:
- **Applicable but lower priority.** The 8080 has single-bit rotate
  instructions (RLC, RRC, RAL, RAR) that take 4cc each. Shifts by N bits
  require N rotates + masking. Chaining `x << 3` as `(x << 1) << 2` doesn't
  save rotates but can share intermediate results.
- More useful for multi-byte shifts (16-bit values) where each shift step
  involves 2-3 instructions per byte. Chaining `x << 3` and `x << 5` as
  16-bit operations could save significant work.
- **Lower priority than loop and spill optimizations** — shifts are less
  common in typical 8080 code than array access patterns.

| Metric | Value |
|--------|-------|
| **Impact** | **Low-Medium** — saves rotates only when multiple shifts of same value exist |
| **Complexity** | Medium — dominance-based instruction motion |
| **Risk** | Low — SSA-based, correctness guaranteed by dominance |
| **V6CLANG prerequisites** | None (operates on generic G_SHL/G_LSHR/etc.) |
| **Similar to** | No current V6CLANG equivalent |

---

### S7. Zero-Page Allocation (Whole-Program Soft Register File)

**llvm-mos pass**: `MOSZeroPageAlloc`

**What it does**: A sophisticated whole-program analysis that identifies the
most beneficial candidates for zero-page placement (the 6502's 256-byte
fast-access memory region). Candidates include:
- Callee-saved registers (CSRs) used in functions
- Stack frame objects (local variables)
- Global variables

The pass scores each candidate by frequency-weighted benefit (using block
frequency analysis), then allocates zero-page bytes round-robin across entry
points, respecting call graph constraints (non-overlapping allocations for
functions that can be active simultaneously).

**V6CLANG adaptation**:
- **The 8080 has no zero page**, but the *concept* maps to a V6CLANG-specific
  optimization: **dedicated fast-access memory regions**. The Vector 06c
  computer has RAM at specific addresses; if some addresses are faster or
  have special properties, the same allocation framework applies.
- **More practically, the algorithm is valuable for O8-style global bss spill
  allocation.** Instead of ad-hoc per-function global variables for spill
  slots, use the frequency-weighted call-graph-aware allocator to decide
  *which* spill slots get promoted to globals and ensure non-overlapping
  allocation. This is exactly what V6CLANG's T2 (global bss spill) strategy needs.
- The `collectCandidates` / `buildEntryGraphs` / `assignZPs` framework can
  be adapted for any "limited fast resource" allocation problem.

| Metric | Value |
|--------|-------|
| **Impact** | **Medium** — no direct 8080 zero page, but algorithm useful for spill allocation |
| **Complexity** | High — whole-program analysis with block frequency, call graph SCCs |
| **Risk** | Medium — complex analysis, but isolated allocation decisions |
| **V6CLANG prerequisites** | Whole-program compilation (LTO); identified "fast memory" regions |
| **Similar to** | Improves O8 (Spill Optimization T2 allocation strategy) |

---

### S8. Dual Cost Model (Bytes + Cycles)

**llvm-mos class**: `MOSInstrCost`

**What it does**: Provides a unified cost representation with separate byte
and cycle counts. The `value()` method composes them differently based on
optimization mode:
- `-Oz` (MinSize): Bytes dominate (shifted left 32 bits, cycles as tiebreaker)
- `-O2` (Speed): Cycles dominate (shifted left 32 bits, bytes as tiebreaker)
- Default: Sum of both (balanced)

Used throughout the backend — `MOSCopyOpt` queries `copyCost()` through this
model; register classes can report different copy costs for different pairs.

**V6CLANG adaptation**:
- **Easy to implement and immediately useful.** V6CLANG has detailed instruction
  timing data ([V6ClangInstructionTimings.md](../docs/V6ClangInstructionTimings.md)).
  Creating a `V6ClangInstrCost` class with the same interface would improve
  every optimization decision in the backend.
- Currently, V6CLANG peephole heuristics are ad-hoc (e.g., `findDefiningLXI`
  always replaces LXI with INX without considering whether it's actually
  cheaper in the specific context). A cost model prevents regressions.
- The `-Oz` vs `-O2` distinction is particularly relevant for embedded 8080
  code where ROM is limited (6502 cartridges and 8080 ROM chips share this
  constraint).

| Metric | Value |
|--------|-------|
| **Impact** | **Medium** — improves all optimization decisions, prevents regressions |
| **Complexity** | Low — simple data structure + function attribute check |
| **Risk** | Very Low — informational only, no code transformation |
| **V6CLANG prerequisites** | Timing data already documented |
| **Similar to** | No current V6CLANG equivalent; enables better O1-O6 decisions |

---

### S9. Tail-Call Optimization (JSR+RTS → JMP)

**llvm-mos pass**: `MOSLateOptimization::tailJMP`

**What it does**: Replaces `JSR target; RTS` with `JMP target` (tail call),
saving the return address push/pop overhead.

**V6CLANG adaptation**:
- **Directly applicable.** `CALL target; RET` → `JMP target` saves
  18cc (CALL=18cc + RET=12cc = 30cc → JMP=12cc). This is a well-known
  optimization that V6CLANG may or may not already implement.
- Trivial peephole: if the last non-debug instruction before RET is CALL,
  replace both with JMP.

| Metric | Value |
|--------|-------|
| **Impact** | **Low-Medium** — 18cc per tail call; frequency depends on coding patterns |
| **Complexity** | Very Low — 10-line peephole |
| **Risk** | Very Low — well-understood optimization |
| **V6CLANG prerequisites** | None |
| **Similar to** | No current V6CLANG equivalent |

---

### S10. Register Class Widening Around Shifts

**llvm-mos pass**: `MOSInsertCopies`

**What it does**: After register coalescing constrains register classes,
this pass inserts copies to widen them back for shift/rotate and inc/dec
operations. On the 6502, shifts can only operate on A or memory, so if
coalescing placed a value in X, a copy A←X is needed. The pass ensures the
widest possible register class is used for these operations.

**V6CLANG adaptation**:
- **Not directly applicable.** The 8080's shift situation is different —
  rotates only work on A (RLC, RRC, RAL, RAR), but this is already handled
  in ISel. There's no equivalent "widening" opportunity.
- The general concept of undoing over-constrained coalescing could apply
  to other V6CLANG patterns where coalescing forces values through suboptimal
  register pairs, but this is speculative.

| Metric | Value |
|--------|-------|
| **Impact** | **Low** — 8080 shift patterns are simpler than 6502 |
| **Complexity** | Medium |
| **Risk** | Low |
| **V6CLANG prerequisites** | N/A — limited applicability |

---

## Summary: Ranked by Impact/Complexity Ratio

| Rank | Strategy | Impact | Complexity | Priority |
|------|----------|--------|------------|----------|
| **1** | **S1. Static Stack Allocation** | Very High | Medium | **Implement first** |
| **2** | **S2. Index IV Rewriting** | High | Low | **Quick win** |
| **3** | **S3. Global Copy Optimization** | High | Medium | **High priority** |
| **4** | **S8. Dual Cost Model** | Medium | Low | **Quick win, enables others** |
| **5** | **S4. LdImm Combining** | Med-High | Low | **Quick win** |
| **6** | **S9. Tail Call Optimization** | Low-Med | Very Low | **Trivial win** |
| **7** | **S5. Compare-Zero Elimination** | Medium | Low | **Enhances existing pass** |
| **8** | **S6. Shift/Rotate Chaining** | Low-Med | Medium | Can defer |
| **9** | **S7. ZP Alloc (as spill allocator)** | Medium | High | Use algorithm for O8 |
| **10** | **S10. RegClass Widening** | Low | Medium | Skip for V6CLANG |

### Recommended Implementation Order

**Phase 1 — Quick wins (Low complexity)**:
1. S8 (Cost Model) — foundation for all other optimizations
2. S9 (Tail Calls) — trivial peephole, immediate benefit
3. S4 (LdImm Combining) — extends existing V6CLANG peephole infrastructure

**Phase 2 — High-impact passes (Medium complexity)**:
4. S2 (Index IV) — reusable IR pass, enables better loops
5. S3 (Global Copy Opt) — supersedes planned O1, cross-BB analysis
6. S5 (CmpZero enhancement) — improves existing V6CLANG ZERO_TEST

**Phase 3 — Major infrastructure (Medium-High complexity)**:
7. S1 (Static Stack Allocation) — highest total impact, needs call graph +
   frame lowering integration. Consider implementing `NonReentrant` analysis
   first (reusable for other purposes), then `StaticStackAlloc`.

---

## Mapping to Existing V6CLANG Plans

| llvm-mos Strategy | Existing V6CLANG Plan | Relationship |
|---|---|---|
| S1 Static Stack | O8 Spill Optimization | **Supersedes T2**, complements T1 |
| S2 Index IV | O7 Loop Strength Reduction | **Complements** — IV narrowing + TTI cost model |
| S3 Global Copy Opt | O1 Redundant MOV | **Supersedes** — cross-BB + cost-aware |
| S4 LdImm Combining | O5 BUILD_PAIR+ADD16 | **Related** — both detect known values in regs |
| S5 CmpZero | Existing ZERO_TEST | **Enhances** — skip-past-safe-instructions approach |
| S7 ZP Alloc | O8 Spill T2 | **Algorithmic improvement** for bss slot allocation |
| S8 Cost Model | (none) | **New infrastructure** — benefits all passes |
| S9 Tail Calls | (none) | **New optimization** |
