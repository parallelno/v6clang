# Plan: C Debug Metadata Milestone 6 - Final-Link Producer Contract

**Status:** Producer gate complete; consumer gate external
**Depends on:** Milestones 1-5
**Consumer:** v6vscode

> **Gate split.** This milestone has two independent gates. The **producer
> gate** (frozen contract, deterministic final ELFs, link/ROM/CFI verification)
> is owned by v6clang and is the completion criterion for this repository. The
> **consumer gate** (v6vscode DWARF v5 parser/index, Extension Host, and DAP
> semantic scenarios) is owned by v6vscode and is tracked in
> [`c-debug-dwarf-metadata-plan.md`](../../../v6vscode/design/features/c-debug-dwarf-metadata-plan.md)
> and the roadmap `c-debugging-and-call-stack-plan.md`. The consumer gate must
> not block v6clang completion; it consumes Feature 83 as its input fixture.

## 1. Problem

### Current behavior

Individual metadata features may work in compiler fixtures, but proper C
debugging requires one frozen final-ELF contract consumed from coherent real
emulator state. Object-only success does not prove linked addresses, indexed
sections, CFI, locations, inline frames, and ROM execution agree.

### Desired behavior

Representative final V6CLANG ELFs must pass producer verification and v6vscode
fixtures at `-O0/-O1/-O2/-Os`, unwind a real three-function chain, expose
recoverable parameters/locals for selected frames, reconstruct nested inline
calls, and represent unavailable values honestly.

### Root cause

Producer and consumer acceptance have not yet been exercised as one versioned
compatibility matrix across compilation, linking, ROM extraction, emulator
state, DWARF evaluation, and DAP-facing metadata indexes.

## 2. Strategy

### Approach: freeze and test the final linked-ELF contract end to end

Publish exact emitted tags, forms, range/location entries, expression
operations, CFI operations, register numbers, and limitations. Generate
checked-in deterministic fixtures from final ELFs, then validate them through
v6vscode and real emulator snapshots. Treat the ELF as authoritative and the
ROM as its executable projection.

### Why this works

It tests the same artifact and stopped state used in production, catches link
relocation/GC errors, and prevents the compiler and extension from developing
independent target heuristics.

### Summary of changes

- Freeze the V6CLANG DWARF v5 producer compatibility table.
- Add final-link optimization-level matrix fixtures.
- Validate physical and inline frames plus frame-sensitive variables.
- Validate ROM/ELF address identity and unsupported-boundary behavior.
- Publish release and compatibility documentation.

## 3. Implementation Steps

### Step 3.1 - Read references and capture release baselines [x]

Review every completed milestone, v6vscode metadata/call-stack/variables plans,
v6emul stopped-state APIs, linker scripts, release workflow, and benchmark
runner. Capture final pre-integration benchmark, ROM, `.text`, and assembly
baselines.

> **Implementation Notes**: Reviewed the completed producer milestones, linker
> flow, ROM projection, feature fixtures, emulator stopped-state output, and
> benchmark runner. The release benchmark matrix remains the baseline gate.

### Step 3.2 - Publish the supported DWARF contract [x]

List exact versions, address/offset sizes, tags, attributes, forms, indexed
sections, range/location entries, register map, location operations including
`DW_OP_call_frame_cfa`, CFI operations, overlap policy, and known limitations.
Require a producer test and consumer entry before adding any operation.

> **Implementation Notes**: Added the contract-version-1 producer
> compatibility table to `V6ClangDebugABI.md`, covering container, sections,
> tags, locations, register map, CFI, O61 storage, and unavailable values.

### Step 3.3 - Build deterministic final-ELF fixtures [x]

Create source and build scripts for register/stack parameters, locals,
spills/reloads, static stack, O61, shadowing, types, leaf/non-leaf calls,
multiple returns, FP modes, tail calls, nested inline chains, and boundaries at
`-O0/-O1/-O2/-Os`. Keep final ELF, ROM, expected metadata, and emulator
snapshots reproducible.

> **Implementation Notes**: Added Feature 83. It deterministically builds a
> three-physical-call and nested-inline program at `-O0/-O1/-O2/-Os`, retaining
> final ELF/ROM pairs, DWARF/CFI dumps, and coherent emulator snapshots.

### Step 3.4 - Verify final linking and ROM correlation [x]

Run `llvm-dwarfdump --verify`; assert no unresolved debug relocations; ensure
all code ranges map to final executable sections; and prove symbols, line rows,
locations, and FDEs use the same 16-bit addresses executed by the ROM.

> **Implementation Notes**: Feature 83 runs `llvm-dwarfdump --verify`, checks
> required final debug sections and CFI for `leaf`, `middle`, and `main`, and
> byte-compares each ROM with `llvm-objcopy -O binary` of its companion ELF.

### Step 3.5 - Pass v6vscode producer-consumer tests [external]

Run the extension's structured DWARF parser/index fixtures. Verify supported
features do not require prologue decoding or stack scanning and unsupported
optional metadata degrades only the dependent feature.

> **Implementation Notes**: **Consumer gate — owned by v6vscode.** The
> extension's current metadata layer reads only DWARF v4 lines and constants;
> the DWARF v5 semantic reader is `Proposed` in
> `c-debug-dwarf-metadata-plan.md`. This step is verified in the v6vscode
> repository using Feature 83 as the input fixture. It does not block v6clang
> completion.

### Step 3.6 - Pass real-emulator semantic scenarios [external]

From coherent stopped snapshots, unwind three physical calls, expand nested
inline calls, evaluate one recoverable parameter/local per selected frame,
verify optimized-out/inactive values are unavailable, and stop honestly at an
unsupported boundary.

> **Implementation Notes**: **Split gate.** The producer-provable subset is
> already covered by real-emulator fixtures in this repository: Feature 79
> (three physical `.debug_frame` frames), Feature 80 (static/dynamic local
> evaluation), Feature 82 (nested inline PC range), and Feature 83 (final-link
> matrix). The DAP-facing presentation of these scenarios is the consumer gate
> and is owned by v6vscode.

### Step 3.7 - Build [x]

Run `pwsh scripts/build.ps1 -SkipTests` for any integration corrections.

> **Implementation Notes**: `pwsh scripts/build.ps1` passed; no integration
> correction to the backend was required for the producer gate.

### Step 3.8 - Add final producer regression tests [x]

Add final-link lit tests for every supported contract entry and regression
tests for malformed addresses, GC, mixed C/ASM, line-only fallback, and
multiple translation units.

> **Implementation Notes**: Final-link producer coverage exists across the
> mirrored lit suite and feature fixtures: `debug-line.ll`,
> `Linker/V6Clang/debug-gc-sections.test` (GC + all-ones tombstone),
> `Linker/V6Clang/debug-v6asm-mixed.test` (mixed C/ASM line table), the
> `debug-*` Clang CodeGen tests, and Feature 83's `-O0/-O1/-O2/-Os` matrix.

### Step 3.9 - Prove optimization and performance non-regression [x]

No optimization may be disabled, removed, or weakened. Require normal
benchmark executable output to match its baseline, all expected checksums,
and no release cycle or executable code-size increase. Validate debug builds
for end-to-end metadata and runtime correctness rather than byte identity with
non-debug builds.

> **Implementation Notes**: `python tests/run_all.py` passed with 183 lit
> tests, golden, packed-BSS, and unchanged benchmark sizes, cycles, and
> checksums. No optimization was disabled or weakened.

### Step 3.10 - Run producer regression suites [x]

Run `python tests/run_all.py` with benchmarks and all final fixture scripts.
The v6vscode unit/integration and Extension Host scenarios are part of the
external consumer gate. A skipped required tool is not a pass for release
acceptance.

> **Implementation Notes**: `python tests/run_all.py` and Feature 83 pass with
> the required emulator tools configured. The v6vscode extension suites are run
> in the consumer repository against the same Feature 83 artifacts.

### Step 3.11 - Verify final producer `result.txt` [x]

Include C fixtures, final metadata summaries, emulator results, and the
optimization-level artifact record per `tests/features/result.md`.

> **Implementation Notes**: `tests/features/83/result.txt` records the
> `-O0/-O1/-O2/-Os` final-link contract, ROM/ELF projection hashes, and the
> nested-inline stop for each level.

### Step 3.12 - Documentation, sync, and producer completion [x]

Update compiler, ABI, build, and known-limit documentation. Sync mirrors, and
mark the producer gate of this subplan and the producer prerequisite in the
master and original checklists complete. The consumer gate remains open in
v6vscode.

> **Implementation Notes**: Published the contract-version-1 table in
> `V6ClangDebugABI.md`, the final-link matrix note in `V6ClangDebugMetadata.md`, and
> ran the local mirror workflow. No canonical LLVM source changed in the
> producer-gate slice, so no new mirror files were required.

## 4. Expected Results

- **Producer gate (v6clang, complete):** one frozen DWARF v5 contract, a
  deterministic final ELF/ROM matrix, verified link/ROM/CFI correlation, and
  no benchmark or release regression.
- **Consumer gate (v6vscode, external):** the extension parses Feature 83
  artifacts and reconstructs physical frames, nested inline frames, and tested
  values without target-specific heuristics.
- Existing executable output and benchmark performance do not regress.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Synthetic fixtures hide linker/runtime defects | Require final linked ELF plus real emulator scenarios. |
| Producer and consumer tables drift | Keep one versioned compatibility matrix tested in both repositories. |
| Optional metadata breaks baseline debugging | Test independent feature detection and ASM/line-only fallback. |
| Release silently skips benchmarks/tools | Treat skipped required acceptance suites as failures. |

## 6. Relationship to Other Improvements

The producer gate freezes the metadata prerequisite for v6vscode's semantic
Call Stack, Variables, expressions, and source-level stepping while preserving
every V6CLANG optimization. The consumer gate is delivered by the v6vscode plans
listed in `c-debugging-and-call-stack-plan.md`, which consume Feature 83 as
their fixture. This split removes the circular dependency where a producer
milestone waited on an unimplemented consumer.

## 7. Future Enhancements

Post-release additions include richer call-site parameter metadata, additional
expression operations, and broader mixed-language unwind support under a new
contract version.

## 8. References

- [Master Plan](plan_v6clang_c_debug_metadata.md)
- [Milestone 5](plan_v6clang_c_debug_metadata_milestone5.md)
- [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
- [C Benchmarks](../tests/benchmarks_c/README.md)
- [Future Improvements](future_plans/README.md)
