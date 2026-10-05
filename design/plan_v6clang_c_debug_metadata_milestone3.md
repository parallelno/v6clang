# Plan: C Debug Metadata Milestone 3 - Baseline C Variable Locations

**Status:** Complete
**Depends on:** Milestones 1-2
**Primary level:** `-O0` with all normally active V6CLANG passes

## 1. Problem

### Current behavior

Clang emits `llvm.dbg.declare` for `-O0`, but final V6CLANG ELFs omit formal
parameter and local-variable DIEs or their locations. Register allocation,
frame-index elimination, static alloca promotion, static-stack allocation, and
spill expansion do not yet provide a tested path from frontend debug records
to final locations.

### Desired behavior

At `-O0`, recoverable parameters and locals must have accurate register,
constant, global/static, stack, or frame-relative locations over valid PC
ranges. `DW_AT_frame_base` and `DW_OP_call_frame_cfa`/`DW_OP_fbreg` must agree
with milestone 2 CFI.

### Root cause

V6CLANG previously lacked DWARF register mappings, and target-specific alloca/frame
rewrites have not been audited for debug-record salvage and final expression
lowering.

## 2. Strategy

### Approach: make simple locations correct before optimizing lifetimes

Trace one parameter and one local through IR, SelectionDAG, machine debug
instructions, RA, PEI, and final DWARF. Repair target hooks and transformations
at the point where the record becomes invalid. Represent static-stack-promoted
allocas as their real global addresses; do not disable promotion.

### Why this works

LLVM's generic debug pipeline can lower register and frame-index locations once
the target exposes register numbers and preserves/salvages debug records. A
small set of `-O0` cases gives a deterministic foundation for location lists.

### Summary of changes

- Enable target register and frame-index expression lowering.
- Preserve/salvage `dbg.declare` through V6CLANG alloca and frame transforms.
- Emit formal parameters, locals, constants, static/global addresses, frame
  base, and honest gaps.
- Support static-stack allocation as an addressable location.

## 3. Implementation Steps

### Step 3.1 - Read references and capture baselines [x]

Review completed contracts, generic LLVM debug-value lowering, V6CLANG alloca
promotion, static stack, spill pseudos, frame-index elimination, and AsmPrinter.
Capture benchmarks and executable hashes before editing.

> **Implementation Notes**: Captured and preserved the release benchmark
> matrix; all v6clang size, cycle, and checksum results are unchanged.

### Step 3.2 - Add diagnostic IR/MIR probes [x]

Add minimal tests for i8/i16/pointer register parameters, stack parameters,
register locals, allocas, constants, and spills. Check debug records after
ISel, RA, PEI, and final assembly to identify each exact loss point.

> **Implementation Notes**: Added focused C CodeGen probes for static/global,
> register, constant, and stack-frame locations.

### Step 3.3 - Preserve alloca debug records [x]

When `V6ClangAllocaPromote` replaces an alloca with a per-function global GEP,
salvage or rewrite attached declarations to the actual address expression.
Do not disable, gate, or weaken alloca promotion or static-stack allocation.

> **Implementation Notes**: `V6ClangStaticDebugValues` converts promoted alloca
> declarations to final global-address locations. Debug promoted homes remain
> materialized without changing non-debug alloca promotion.

### Step 3.4 - Lower register and frame locations [x]

Implement the required target hooks/metadata so physical byte and pair
registers use milestone 1 numbers and frame indices become CFA/FB-relative
expressions consistent with milestone 2. Emit pieces only if the frozen
producer/consumer contract enables them.

> **Implementation Notes**: Validated byte/pair register locations, constants,
> CFA-derived frame bases, and `DW_OP_fbreg` stack locations.

### Step 3.5 - Preserve locations through spills and FI elimination [x]

Ensure ordinary stack spills, static-stack slots, reloads, and pseudo expansion
update debug locations to the real surviving register or memory location.
Represent unavailable intervals as gaps, never by extending a stale value.

> **Implementation Notes**: Baseline stack locations use the final frame base;
> optimized lifetime transitions and O61 locations remain Milestone 4 work.

### Step 3.6 - Build [x]

Run `pwsh scripts/build.ps1 -SkipTests`.

> **Implementation Notes**: `pwsh scripts/build.ps1 -SkipTests` passed.

### Step 3.7 - Add IR, MIR, CodeGen, and linked-ELF tests [x]

Assert `DW_TAG_formal_parameter`, `DW_TAG_variable`, `DW_AT_location`,
`DW_AT_frame_base`, register/base-register ops, `DW_OP_call_frame_cfa`,
`DW_OP_fbreg`, constants, static addresses, stack spills, and 16-bit final
addresses. Run `llvm-dwarfdump --verify` on every final fixture.

> **Implementation Notes**: Added `debug-baseline-locations.c`,
> `debug-register-constant-locations.c`, and `debug-stack-parameters.c`.

### Step 3.8 - Add emulator value tests [x]

Stop at selected PCs in leaf/non-leaf functions and evaluate locations against
real registers/memory. Include parameters and locals backed by registers,
ordinary stack, and static storage.

> **Implementation Notes**: Feature 80 validates final DWARF against stopped
> emulator state for static and dynamic homes.

### Step 3.9 - Prove optimization and performance non-regression [x]

Keep every optimization active. Require unchanged normal optimized
assembly/`.text`/ROM, correct benchmark checksums, and no release benchmark
cycle or code-size increase. Validate debug builds for correct locations and
runtime values; they need not match non-debug executable bytes.

> **Implementation Notes**: The O43 release regression passes; full benchmark
> results retain their prior v6clang sizes, cycles, and checksums.

### Step 3.10 - Run regression tests [x]

Run focused tests and `python tests/run_all.py` with benchmarks enabled.

> **Implementation Notes**: `python tests/run_all.py` passed: 180 lit tests,
> golden tests, packed-BSS tests, and benchmarks.

### Step 3.11 - Verify assembly and create `result.txt` [x]

Record source, unchanged assembly, DIE/location dumps, evaluated values versus
emulator state, and old/new benchmark tables according to
`tests/features/result.md`.

> **Implementation Notes**: Feature 80 records final DWARF, emulator state,
> evaluated values, and matching release assembly.

### Step 3.12 - Document, sync, and mark complete [x]

Document supported baseline locations and unavailable cases, sync mirrors, and
mark all steps plus the master milestone complete.

> **Implementation Notes**: Debug ABI/metadata documentation, the master plan,
> and the tracked mirror are updated.

## 4. Expected Results

- `-O0` final ELFs expose tested parameters and locals where recoverable.
- Static-stack locals are described at their real addresses.
- No optimization or benchmark result changes.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Debug salvage keeps old alloca address | Test final address against symbol and emulator memory. |
| Pair location byte order is wrong | Test known asymmetric i16 values and byte pieces. |
| Location crosses a clobber | Stop immediately before/after spill, call, and reload. |
| Debug records influence RA | Accept debug-specific allocation while testing location accuracy and preserving normal optimized output. |

## 6. Relationship to Other Improvements

This milestone integrates with O10/static-stack and ordinary spill lowering.
Optimized movement and O61 transitions are completed in milestone 4.

## 7. Future Enhancements

Complex optimized lifetimes, split values, scopes, and inline origins are
deferred to milestones 4-5.

## 8. References

- [Master Plan](plan_v6clang_c_debug_metadata.md)
- [Milestone 2](plan_v6clang_c_debug_metadata_milestone2.md)
- [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
- [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md)
- [Future Improvements](future_plans/README.md)
