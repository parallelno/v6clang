# Plan: C Debug Metadata Milestone 5 - Scopes, Types, and Inline Metadata

**Status:** Complete
**Depends on:** Milestones 1-4

## 1. Problem

### Current behavior

V6CLANG already emits some generic type and subprogram DIEs, but there is no
complete final-ELF matrix proving lexical blocks, shadowing, discontinuous
ranges, C type layout, inline origins, inline parameters/locals, and nested
inline chains against V6CLANG's 16-bit data layout.

### Desired behavior

Final ELFs must accurately describe active lexical scopes, visible variable
identities, supported C types, and logical inline frames at all tested
optimization levels.

### Root cause

Generic LLVM emission exists, but target-specific layout, custom CFG/value
transformations, final relocation/GC behavior, and consumer expectations have
not been tested as one contract.

## 2. Strategy

### Approach: validate generic emission, add target code only for proven gaps

Construct a compact C matrix that forces every required type, scope, range,
and inline form. Inspect IR metadata first, then object and final ELF. Repair
the earliest layer that loses or corrupts information; avoid target-specific
reimplementation of generic DWARF generation.

### Why this works

Clang and LLVM already own C type and inline semantics. V6CLANG should supply data
layout and preserve ranges/locations, minimizing custom code and long-term
maintenance.

### Summary of changes

- Verify scalar, pointer, function-pointer, array, struct, union, enum,
  typedef, qualifier, subroutine, member, and subrange DIEs.
- Verify lexical blocks, shadowing, discontinuous ranges, and final addresses.
- Verify abstract origins and nested inline chains with variables/parameters.
- Correct only demonstrated frontend/backend/linker gaps.

## 3. Implementation Steps

### Step 3.1 - Read references and capture baselines [x]

Review completed location contracts, V6CLANG data layout, Clang type metadata,
generic DwarfDebug range/inline emission, linker GC, and v6vscode's supported
forms/tags. Capture benchmark and executable baselines.

> **Implementation Notes**: Reviewed the V6CLANG 16-bit data layout, generic
> DwarfDebug emission, final-link GC coverage, and prior location contracts.

### Step 3.2 - Define the semantic metadata matrix [x]

Specify source fixtures and exact expected tags/attributes for signed/unsigned
integers, `_Bool`, chars, enums, pointers, function pointers, arrays,
structures, unions, members, bit sizes/offsets, typedefs, qualifiers,
subroutine types, shadowed blocks, and discontinuous ranges.

> **Implementation Notes**: Added a C matrix for enum, typedef, pointer,
> function pointer, array, structure, union, const, volatile, lexical scope,
> shadowing, and nested inline metadata.

### Step 3.3 - Validate and repair lexical/function ranges [x]

Check `DW_TAG_subprogram` and `DW_TAG_lexical_block` ranges at
`-O0/-O1/-O2/-Os`, including GC and discontinuous code. Ensure variables are
associated with the right scope identity and final 16-bit executable ranges.

> **Implementation Notes**: Final ELFs contain lexical-block and nested inline
> ranges with 16-bit executable PCs. Existing linker GC tests retain only live
> executable ranges and use the V6CLANG discarded-address tombstone for dead rows.

### Step 3.4 - Validate and repair C type metadata [x]

Compare DIE byte sizes, encodings, member offsets, array counts, and qualifiers
to the V6CLANG data layout and runtime memory representation. Prefer fixes in data
layout/frontend hooks over post-emission rewriting.

> **Implementation Notes**: Final DWARF reports the tested 11-byte layout
> with member offsets 0, 1, 3, and 9; Feature 82 verifies those offsets against
> asymmetric live emulator memory. No target data-layout repair was required.

### Step 3.5 - Validate and repair inline metadata [x]

Cover `DW_TAG_inlined_subroutine`, `DW_AT_abstract_origin`, call
file/line/column, abstract parameters/locals, nested chains, optimized-out
arguments, and discontinuous inline ranges.

> **Implementation Notes**: Final `DW_TAG_inlined_subroutine` DIEs retain
> abstract origins and call coordinates. Feature 82 stops at a PC covered by
> both the outer and nested inline ranges.

### Step 3.6 - Build [x]

Run `pwsh scripts/build.ps1 -SkipTests`.

> **Implementation Notes**: `pwsh scripts/build.ps1 -SkipTests` passed.

### Step 3.7 - Add Clang, IR, CodeGen, and linked-ELF tests [x]

Assert each matrix entry and run `llvm-dwarfdump --verify`. Include malformed
or absent optional metadata only in consumer fixtures, not as accepted producer
output.

> **Implementation Notes**: Added canonical `debug-scopes-types-inline.c` and
> retained final-ELF `llvm-dwarfdump --verify` checks.

### Step 3.8 - Add emulator layout and inline-range tests [x]

Write asymmetric field/array/enum values, stop in nested inline code, and
confirm DIE layout and active inline chain against actual memory and PC.

> **Implementation Notes**: Feature 82 validates aggregate bytes, member
> offsets, enum storage, and nested inline PC coverage.

### Step 3.9 - Prove optimization and performance non-regression [x]

Do not disable or delete optimizations. Require unchanged normal optimized
executable output, identical benchmark checksums, and no release benchmark
cycle or code-size increase. Validate debug builds for correct scopes, types,
inline metadata, and runtime behavior rather than non-debug byte identity.

> **Implementation Notes**: Release benchmark sizes, cycles, and checksums
> remain unchanged. Debug builds are validated for metadata correctness rather
> than byte identity with non-debug builds.

### Step 3.10 - Run regression tests [x]

Run focused matrices and `python tests/run_all.py` with benchmarks enabled.

> **Implementation Notes**: Focused matrix and Feature 82 pass, followed by
> `python tests/run_all.py` with benchmarks.

### Step 3.11 - Verify assembly and create `result.txt` [x]

Record unchanged assembly, type/scope/inline dumps, emulator comparisons, and
benchmark tables according to `tests/features/result.md`.

> **Implementation Notes**: Feature 82 records final DWARF, stopped emulator
> state, layout values, and active nested-inline ranges.

### Step 3.12 - Document, sync, and mark complete [x]

Publish supported tags/types/inline forms and limitations, sync mirrors, and
mark all steps plus the master milestone complete.

> **Implementation Notes**: Updated debug metadata documentation and master
> plans; canonical tests are synchronized into tracked mirrors.

## 4. Expected Results

- C type layouts match actual V6CLANG memory.
- Shadowed variables and nested inline frames have distinct, correct identity.
- No generated-code or benchmark regression occurs.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Tests merely restate frontend IR | Validate final ELF and emulator memory/PC. |
| Recursive types cause unbounded consumers | Use stable DIE references; consumer limits remain downstream. |
| Inline debug metadata is inaccurate after optimization | Test emitted metadata against actual debug-build PCs and runtime state. |
| Link GC leaves stale ranges | Correlate every accepted range with final executable sections. |

## 6. Relationship to Other Improvements

This milestone consumes optimized locations from milestone 4 and supplies
logical frames/types to v6vscode without changing inlining or other
optimization policies.

## 7. Future Enhancements

Advanced C extensions and richer call-site metadata can be added after the
core compatibility table is frozen.

## 8. References

- [Master Plan](plan_v6clang_c_debug_metadata.md)
- [Milestone 4](plan_v6clang_c_debug_metadata_milestone4.md)
- [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
- [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md)
- [Future Improvements](future_plans/README.md)
