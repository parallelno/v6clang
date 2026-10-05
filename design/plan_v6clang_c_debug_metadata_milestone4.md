# Plan: C Debug Metadata Milestone 4 - Optimized Lifetimes and Location Lists

**Status:** Complete
**Depends on:** Milestones 1-3
**Optimization levels:** `-O1`, `-O2`, `-Os`, and project-default optimized builds

## 1. Problem

### Current behavior

At optimized levels V6CLANG may retain parameter/local DIEs but emits no useful
`DW_AT_location` for them. Custom pre/post-RA passes erase, clone, move, and
replace machine instructions without a systematic `DBG_VALUE` or
`DBG_INSTR_REF` preservation policy. Values move through registers, ordinary
spills, static slots, constants, and O61 self-modifying immediate bytes.

### Desired behavior

Final ELFs must contain accurate `.debug_loclists` transitions and gaps for
recoverable optimized values. All existing optimizations remain enabled and
retain their exact code-quality behavior.

### Root cause

V6CLANG transformations use non-debug use queries and instruction rewrites but do
not consistently salvage, transfer, or terminate associated debug values.

## 2. Strategy

### Approach: audit transformations by value effect, not pass name

Build a pass matrix describing each rewrite's value-preserving, value-moving,
value-defining, or value-killing semantics. Update debug records beside the
rewrite using generic LLVM helpers where possible. Test each pass independently
and then test composed post-RA pipelines. Describe O61 reload immediates at
their real code addresses rather than disabling O61.

### Why this works

Debug metadata becomes a truthful observer of the already-optimized machine
program. Optimization matching, profitability, and emitted instructions stay
unchanged, while locations follow surviving values and end at clobbers.

### Summary of changes

- Audit every V6CLANG IR and MachineFunction transformation affecting values.
- Preserve/salvage machine debug records for copies, folds, spills, reloads,
  constants, dead values, and CFG rewrites.
- Emit v5 location lists with transitions, disjoint ranges, and gaps.
- Model static-stack and O61 instruction-byte locations accurately.

## 3. Implementation Steps

### Step 3.1 - Read references, inventory passes, and capture baselines [x]

Review generic LiveDebugValues/debug-instr-ref support and every active V6CLANG IR,
pre-RA, post-RA, PEI, and pre-emit pass. Record an inventory of instruction
mutation APIs and debug handling. Capture benchmark and executable baselines.

> **Implementation Notes**: Generic `LiveDebugValues` precedes the V6CLANG late
> pipeline. Release text and benchmark baselines remain unchanged.

### Step 3.2 - Define the machine debug preservation policy [x]

For erase/replace/move/clone/fold/CFG cases, specify when to transfer a debug
instruction number, substitute a debug operand, emit a new debug value, or end
a location. Adopt one consistent generic LLVM representation supported by the
pinned LLVM version.

> **Implementation Notes**: Use physical-location `DBG_VALUE` tracking. A
> rewrite that preserves a value in the same physical register keeps the
> existing debug record; final-stream clobber history closes its range. A
> rewrite that changes storage must replace the debug operand with the final
> address. A removed value becomes an honest gap; no pass may extend a stale
> record over a clobber. CFG rewrites preserve debug instructions and lexical
> scope ranges with their surviving blocks.

### Step 3.3 - Repair pre-RA and CFG transformations [x]

Update constant sinking, dead-PHI constant replacement, custom inserters, and
other pre-RA/CFG rewrites so debug uses and scopes follow the new definitions
and edges without changing optimization eligibility or generated code.

> **Implementation Notes**: Audited constant sinking, dead-PHI replacement,
> target select/custom-inserter CFG rewrites, loop pointer induction, and type
> narrowing. Their SSA replacements retain frontend debug records; values no
> longer represented in the final stream produce ordinary location gaps.

### Step 3.4 - Repair spill and frame transformations [x]

Handle spill forwarding, dead reloads, ordinary/static spill expansion,
frame-index elimination, and register-to-stack-to-register transitions. Emit
gaps where no recoverable machine value exists.

> **Implementation Notes**: Completed static-stack frame-index lowering. A
> debug location that survives in a static slot now uses the final backing
> global address instead of a false SP-relative expression. Ordinary spills
> retain generic register/stack range tracking; O61 storage is handled below.

### Step 3.5 - Repair all pre-emit optimizations [x]

Audit accumulator planning, load-immediate combine, peephole, load/store,
XCHG, branch, zero-test, register-value forwarding, redundant flags, and SP
tricks. Preserve debug semantics without altering any pattern, cost, liveness
decision, or output instruction.

> **Implementation Notes**: Audited accumulator planning, peephole,
> load-immediate/load-store/XCHG, branch, zero-test, register-value forwarding,
> redundant-flag, and SP-trick rewrites. They either remove semantically
> redundant instructions or replace them with equivalent physical definitions;
> the final machine stream remains the source of clobber boundaries. O61 and
> debug alloca homes are the storage-changing exceptions and are explicitly
> represented.

### Step 3.6 - Model O61 patched locations [x]

For patched LXI/MVI reloads, describe the live value in the destination
register after execution and, where a memory location is valid, the actual
`.LLo61_N+1` instruction-byte address. Terminate locations when later patches
or clobbers invalidate them. Do not disable, delete, or special-case O61 out of
debug builds.

> **Implementation Notes**: O61 records each rewritten frame index's first
> patch-site label. A post-O61 debug pass maps that frame index to
> `.LLo61_N+1`; final DWARF uses `DW_OP_addrx; DW_OP_plus_uconst 1` over the
> interval where the patched immediate bytes retain the value.

### Step 3.7 - Build [x]

Run `pwsh scripts/build.ps1 -SkipTests`.

> **Implementation Notes**:

### Step 3.8 - Add pass-specific and location-list tests [x]

Add IR/MIR tests for every audited mutation class and final ELF tests for
register moves, spill/reload transitions, constants, gaps, prologue/epilogue,
disjoint ranges, half-open boundaries, static slots, O61 patches, calls, and
optimized-out values at `-O1/-O2/-Os`.

> **Implementation Notes**: Added direct final-ELF O61 coverage and expanded
> C location-list coverage across `-O1`, `-O2`, and `-Os`. Tests cover
> register-to-static/O61 transitions, final patch-byte addresses, constants,
> stack arguments, and final DWARF verification.

### Step 3.9 - Add emulator lifetime tests [x]

Stop on both sides of each transition and evaluate the selected location
against registers/memory. Assert unavailable ranges remain unavailable and
shadowed identities do not alias.

> **Implementation Notes**: Feature 80 evaluates static and frame-relative
> locations against stopped emulator memory. Feature 81 stops inside an O61
> location-list interval and verifies the patched immediate bytes contain the
> carried value.

### Step 3.10 - Prove optimization and performance non-regression [x]

All optimizations and their default settings remain active. Compare `-g0`
assembly, `.text`, ROM, optimization remarks where practical, and benchmark
cycles/sizes to baseline. Debug builds may differ when necessary for correct
source locations, but must keep all optimizations enabled. Any normal release
instruction, cycle, or size regression blocks completion.

> **Implementation Notes**: `python tests/run_all.py` passed with 182 lit
> tests, golden tests, packed-BSS, and unchanged benchmark sizes, cycles, and
> checksums. The optimized debug fixture may differ from `-g0`, as permitted
> by the source-location preservation contract; release output is unchanged.

### Step 3.11 - Run regression tests [x]

Run all focused tests and `python tests/run_all.py` with benchmarks enabled.

> **Implementation Notes**: Focused O61/static-location tests and the full
> regression suite pass.

### Step 3.12 - Verify assembly and create `result.txt` [x]

Include unchanged assembly, selected `.debug_loclists` dumps, transition/value
checks, pass coverage matrix, and complete benchmark comparison.

> **Implementation Notes**: Feature 81 records its final location expression,
> live PC interval, patch-byte address, and evaluated emulator value.

### Step 3.13 - Document, sync, and mark complete [x]

Publish optimized-location guarantees and limitations, sync mirrors, and mark
all steps plus the master milestone complete.

> **Implementation Notes**: Updated producer documentation and master plans,
> synchronized canonical LLVM changes into tracked mirrors, and verified
> mirror hashes for new and modified sources.

## 4. Expected Results

- Optimized parameters/locals have accurate transitions or honest gaps.
- Static-stack and O61 remain enabled and debuggable.
- Optimized executable bytes and all benchmark results remain unchanged.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| A debug fix harms normal optimized code | Compare release output and benchmarks to baseline; separately validate debug locations and runtime behavior. |
| Stale location survives a fold | Test before/after every audited rewrite and clobber. |
| O61 code bytes are mistaken for immutable memory | Track patch lifetime and use final linked symbol addresses. |
| Audit misses a pass | Maintain a checked pass inventory derived from the actual pipeline. |

## 6. Relationship to Other Improvements

This milestone integrates debug tracking with all existing V6CLANG optimization
passes; it does not supersede or modify their performance goals.

## 7. Future Enhancements

`DW_OP_piece` and entry values remain optional until producer and consumer
contracts explicitly enable them.

## 8. References

- [Master Plan](plan_v6clang_c_debug_metadata.md)
- [Milestone 3](plan_v6clang_c_debug_metadata_milestone3.md)
- [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
- [C Benchmarks](../tests/benchmarks_c/README.md)
- [Future Improvements](future_plans/README.md)
