# Plan: v6clang C Debug Metadata

**Status:** Proposed
**Date:** 2026-08-15
**Design source:** [v6clang-c-debug-metadata-plan.md](future_plans/v6clang-c-debug-metadata-plan.md)
**Consumer roadmap:** `C:\Work\Programming\v6vscode\design\features\c-debugging-and-call-stack-plan.md`

> **Execution rule:** Implement the milestones below in order. Each milestone is
> an independently reviewed subplan and must pass all of its acceptance gates
> before the next begins. This document is an index, not an authorization to
> implement multiple milestones in one change.

## 1. Problem

### Current behavior

V6CLANG final ELFs contain valid DWARF v5 line, symbol, type, range, string, and
address-index sections. They do not yet provide reliable C parameter/local
locations, optimized location lists, or call-frame information. A minimal
probe showed that Clang emits `llvm.dbg.declare` and `llvm.dbg.value`, but V6CLANG
code generation does not produce corresponding local locations.

### Desired behavior

Final linked V6CLANG ELF companions must describe recoverable C variables, scopes,
inline calls, and physical unwind state without v6vscode inferring values from
instruction patterns or arbitrary stack words.

### Root cause

The target lacks a frozen DWARF register contract, complete target/MC debug
plumbing, CFI generation, and verified preservation of debug values through
V6CLANG-specific IR and machine passes.

## 2. Strategy

### Approach: dependency-ordered producer milestones

Establish the stable ABI and register vocabulary first, add physical unwind
rules next, then add baseline and optimized variable locations. Validate
semantic DIEs after location infrastructure is sound, and finish by freezing
the producer/consumer compatibility contract against final linked ELFs and
real emulator state.

### Why this works

LLVM's generic DWARF emitter already supplies most DIE, type, range, inline,
and location-list machinery. The staged approach adds the target facts that
machinery requires and proves each layer before downstream consumers depend on
it.

### Non-negotiable optimization and performance invariants

These apply to every milestone:

- Do not disable, bypass, weaken, or delete any existing optimization.
- Debug correctness must be integrated with static-stack allocation, O61
  patched reloads, and every other active V6CLANG pass.
- Non-debug (`-g0`) code generation must remain byte-for-byte unchanged unless
  the milestone documents and obtains approval for an unavoidable correctness
  fix.
- Debug builds may differ from non-debug builds because preserving source
  variables can affect register allocation, stack layout, and optimization
  decisions. They must remain correct and must not disable or remove existing
  optimizations merely to simplify metadata emission.
- Before implementation, capture the current benchmark baseline with
  `python tests/benchmarks_c/run_benchmarks.py`.
- After every milestone, every v6clang benchmark at every tested optimization
  level must retain its checksum and have cycle count and executable code size
  less than or equal to that captured baseline. Any increase blocks completion.
- `python tests/run_all.py` must pass without `--no-benchmarks`.

## 3. Milestones

1. [x] [Milestone 1: ABI, DWARF register map, and ELF integrity](plan_v6clang_c_debug_metadata_milestone1.md)
2. [x] [Milestone 2: Call-frame information and physical unwinding](plan_v6clang_c_debug_metadata_milestone2.md)
3. [x] [Milestone 3: Baseline parameter and local locations](plan_v6clang_c_debug_metadata_milestone3.md)
4. [x] [Milestone 4: Optimized lifetimes and location lists](plan_v6clang_c_debug_metadata_milestone4.md)
5. [x] [Milestone 5: Lexical scopes, types, and inline metadata](plan_v6clang_c_debug_metadata_milestone5.md)
6. [x] [Milestone 6: Final-link producer contract](plan_v6clang_c_debug_metadata_milestone6.md)
   (producer gate complete; the v6vscode consumer gate is tracked externally in
   `c-debugging-and-call-stack-plan.md`)

Dependencies are strict: milestone $n$ may rely only on completed milestones
$1..n-1$. A milestone may add tests for later work, but must not partially
implement a later milestone. Milestone 6's consumer-integration acceptance is
owned by v6vscode and does not block the v6clang producer prerequisite.

## 4. Expected Results

- v6vscode receives standard, bounded DWARF v5 data instead of target-specific
  prologue or stack heuristics.
- Release/non-debug builds retain their established executable behavior and
  benchmark performance.
- Each delivery has a small, falsifiable acceptance surface and can be reverted
  independently if its metadata is incorrect.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Debug support regresses release code | Require `.text`, ROM, cycle, and size identity for `-g0` versus the captured baseline. |
| Custom passes invalidate debug locations | Add pass-specific before/after MIR or IR tests; update debug records without changing optimization decisions. |
| CFI does not model dynamic prologue choices | Emit CFI beside each actual SP/register mutation and test every selected prologue/epilogue tier. |
| Static-stack or O61 locations are unusual | Model their real memory/instruction-byte locations; never disable either optimization. |
| Link GC leaves invalid metadata | Verify final linked ELFs containing runtime helpers and discarded sections. |

## 6. Relationship to Other Improvements

This plan extends `plan_source_debug_metadata.md`. It is the producer
prerequisite for v6vscode's DWARF reader, semantic Call Stack, Variables,
expressions, and source-stepping plans. It must coexist with all completed and
future optimization work listed in `future_plans/README.md`.

## 7. Future Enhancements

After all six milestones, optional work may add richer call-site parameter
metadata, split-value representations beyond the frozen contract, and
additional DWARF operations. Each addition requires producer and consumer
tests and the same benchmark gates.

## 8. References

- [Feature Development Pipeline](pipeline_feature.md)
- [Feature Plan Prompt](feature_plan_prompt.md)
- [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
- [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md)
- [C Benchmarks](../tests/benchmarks_c/README.md)
- [Feature Result Format](../tests/features/result.md)
- [Future Improvements](future_plans/README.md)
