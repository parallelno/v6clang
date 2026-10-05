# Plan: Source Debug Metadata and DAP Address Mapping

## Scope

This plan defines the shared debug-artifact contract for C and assembly,
enables the V6CLANG LLVM toolchain to produce that artifact, and defines how a
Debug Adapter Protocol (DAP) adapter resolves source locations before sending
numeric breakpoints to `v6emul`.

The v6asm implementation is developed in the external `parallelno/v6asm` Rust
project; its implementation plan is
`C:\Work\Programming\v6asm\design\plan_v6asm_dwarf_debug_metadata.md`.
The adapter may also live with the new emulator rather than in this repository;
its required behavior and integration tests remain part of this feature
contract.

## 1. Problem

### Current behavior

- DAP `setBreakpoints` supplies a source path, line, and optional column. It
  does not supply a Vector-06C CPU address.
- `v6emul` already accepts address-triggered breakpoints through its IPC debug
  commands (`DEBUG_BREAKPOINT_ADD`, delete, enable, disable, and query), but it
  has no source-file knowledge.
- The current V6CLANG Clang build does not produce usable debug sections. A local
  probe on 2026-07-28 using
  `clang -target i8080-unknown-v6clang -g -O0 -c` produced `.text`, relocation,
  `.symtab`, and string-table sections, but no `.debug_*` sections.
- `V6ClangMCAsmInfo` sets the 16-bit code-pointer size but does not advertise debug
  information support. The MC ELF writer maps 8-bit and 16-bit fixups only;
  DWARF section offsets may additionally require a 32-bit relocation.
- The normal Clang ROM path links a final ELF at runtime VMAs and then runs
  `llvm-objcopy -O binary`, but the ELF is registered as a temporary file and
  deleted. A `.rom` therefore loses its symbols and source metadata.
- Upstream v6asm now implements opt-in DWARF v4 object metadata and direct-ROM
  companion ELFs. Its 2026-07-29 implementation audit records the core writer,
  source provenance, symbols, CLI, and unit tests as implemented; LLVM
  interoperability and mixed-language end-to-end verification remain open.
- The packaged `tools/v6asm` release exposes `-g` / `--debug` and
  `--debug-elf`, matching the copied documentation. It is the rebuilt
  `2026.07.29-6dab24c` release; record its executable hash in integration
  results together with that version.
- No V6CLANG source-to-address reader or DAP breakpoint resolver exists in this
  workspace.

### Desired behavior

1. A debug build produces both `program.elf` and `program.rom` from the same
   final link. The ELF remains the authoritative debug companion.
2. The final ELF contains standard DWARF line information and ELF symbols:
   source file, line, column where available, instruction-start addresses,
   address ranges, compilation directory, and final linked symbol addresses.
3. C objects emitted by Clang and assembly objects emitted by v6asm follow one
   compatible DWARF/ELF contract and can be linked into one debuggable ELF.
4. The adapter indexes the final linked ELF once, resolves DAP source
   breakpoints to one or more 16-bit CPU addresses, installs those addresses in
   `v6emul`, and maps the current PC back to source for stack frames and line
   highlighting.
5. The adapter rejects stale or incompatible ELF/ROM pairs before installing
   source breakpoints.
6. Requested lines with no executable code produce an unverified DAP
   breakpoint or are moved to a documented next statement boundary; every move
   is reported in the returned DAP `Breakpoint.line`.

### Root cause

The emulator and DAP use different coordinate systems. The missing bridge is
not another emulator command or a custom source-map file; it is a retained
final ELF with valid line tables plus an adapter-side bidirectional index.

The initial agent proposal correctly selected ELF/DWARF and the final linked
artifact, but required these corrections after repository verification:

- v6asm already has relocatable ELF object output; it does not need a new
  object format.
- v6asm's documented `.symbols.json` path is stale: the current upstream source
  contains no generator or CLI option for it. It cannot be the compatibility
  path for this feature.
- Current Clang V6CLANG `-g` emits no DWARF, so this is not only a v6asm task.
- `.debug_line` plus `.symtab` is conceptually enough for a custom reader, but
  a standards-compatible artifact should also carry a minimal compile unit in
  `.debug_info` with `.debug_abbrev` and strings. This makes LLVM tooling and
  third-party DWARF readers reliable.
- Final ELF VMAs already equal CPU addresses under `v6clang.ld` (normally starting
  at `0x0100`). The adapter must not add the ROM load address a second time.
- Macro definition and invocation provenance cannot both be represented as one
  primary DWARF line row. Level 1 uses invocation rows as statement boundaries
  and may retain definition rows as non-statement provenance; full macro
  debugging is a later feature.

## 2. Strategy

### Approach: DWARF v4 line tables in the final linked ELF

Use a deliberately small, testable DWARF v4 contract first:

- `.debug_info`: one minimal `DW_TAG_compile_unit` per input object, including
  producer, language, source name, compilation directory, statement-list
  reference, and code ranges where practical.
- `.debug_abbrev`: abbreviations used by those compilation units.
- `.debug_line`: file table and line program with 16-bit code addresses,
  instruction-start rows, `is_stmt`, columns where known, and correct
  end-sequence ranges.
- `.debug_str`: shared strings where used by `.debug_info`.
- `.symtab` / `.strtab`: final global and local code/data labels that are useful
  to the debugger. Function symbols should have non-zero sizes when known.

Pin initial tests to DWARF v4 (`-gdwarf-4`). DWARF v5, typed variables,
location expressions, call-frame information, and macro sections are out of
scope for Level 1.

### Address and artifact contract

- The final linked ELF is authoritative. The adapter never resolves against a
  relocatable `.o`.
- For the default `v6clang.ld`, ELF virtual addresses are CPU addresses. Validate
  every executable address is in `0x0000..0xFFFF` and send it unchanged.
- A non-zero adapter relocation bias is allowed only as an explicit launch
  configuration for an image that is intentionally loaded somewhere other
  than its ELF VMA. Default bias is zero.
- Produce ROM bytes only from the retained ELF:

  ```powershell
  clang -target i8080-unknown-v6clang -g -gdwarf-4 app.c -o program.elf
  llvm-objcopy -O binary program.elf program.rom
  ```

- At launch, reconstruct the loadable byte image from the ELF using the same
  address/gap rules as `llvm-objcopy` and compare it byte-for-byte (or compare
  SHA-256 digests) with the configured ROM. Refuse source debugging on a
  mismatch. A build ID can be added later, but is not sufficient by itself to
  prove that an independently supplied ROM has the same bytes.

### Breakpoint resolution contract

Build immutable indexes when the ELF is loaded:

- canonical source identity -> sorted executable rows;
- `(source, line)` -> all statement addresses and columns;
- address interval -> source row;
- address -> nearest containing ELF symbol.

`setBreakpoints` is replace-all for the supplied DAP source:

1. Canonicalize the client path and match it against DWARF paths using exact
   canonical matches first, then configured `sourceFileMap` prefix mappings.
   Basename-only matching is forbidden when ambiguous.
2. Prefer exact-line `is_stmt` rows. If a column is supplied, prefer the first
   row at or after that column on the same line.
3. If the exact line has no statement, move to the next statement in the same
   file only when the configured policy permits it; otherwise return
   `verified: false` with a useful message.
4. Keep every distinct instruction-start address for a line. Macro/loop
   expansion may legitimately produce multiple addresses. Install all of them
   while returning one logical DAP breakpoint whose adapter data tracks all
   emulator breakpoint IDs.
5. Delete only the old emulator breakpoints owned by that source request, then
   add the new set. Roll back or return unverified breakpoints if IPC fails so
   adapter and emulator state cannot silently diverge.
6. Return the actual resolved source, line, column, and an adapter breakpoint
   ID. Never claim verification for an empty address set.

For PC-to-source mapping, use half-open line ranges `[row.address,
next_row.address)`, bounded by DWARF end-sequence. Exact instruction starts win;
gaps outside a sequence are disassembly-only locations.

### Why this works

- It uses the same standard metadata for C, LLVM assembly, and v6asm assembly.
- LLD applies section relocations and garbage collection before the adapter
  reads the file, so dead sections never create breakpoints and addresses are
  final.
- Source and address lookup become deterministic, unit-testable operations
  independent of the emulator transport.
- Keeping source interpretation in the adapter preserves `v6emul` as a small,
  address-based execution engine.

### Summary of changes

| Component | Change |
|-----------|--------|
| V6CLANG MC/AsmInfo | Enable debug emission; support all fixups required by minimal DWARF |
| V6CLANG ELF ABI + LLD | Add and apply a 32-bit absolute relocation if the probe proves DWARF section references require it |
| Clang/LLVM tests | Verify C `-g -gdwarf-4` objects and final linked ELF line mappings |
| Build workflow | Retain `program.elf`, derive `program.rom` from it, document both launch paths |
| v6asm | Packaged release emits the metadata; run mixed-language, relocation-name, and adapter verification |
| Debug adapter | Parse/index final ELF, validate ROM identity, resolve DAP breakpoints, map PC to source |
| v6emul | Keep numeric breakpoint IPC; add only missing protocol detail/tests, not DWARF parsing |

## 3. Implementation Steps

### Step 3.1 - Read and freeze the contracts [ ]

Read `docs/V6ClangBuildGuide.md`, `docs/V6ClangArchitecture.md`,
`docs/V6ClangUsage.md`, `tools/v6emul/docs/cli.md`,
`tools/v6emul/docs/ipc-protocol.md`, `clang/lib/Driver/ToolChains/V6Clang.cpp`,
`clang/lib/Driver/ToolChains/V6CLANG/v6clang.ld`, the V6CLANG MC assembler backend, and
the DAP `setBreakpoints`, `Breakpoint`, `Source`, and `sourceFileMap` semantics.

Record the Level 1 DWARF version, path policy, line-sliding policy, zero address
bias, and ELF/ROM comparison algorithm in adapter-facing documentation before
implementation.

> **Implementation Notes**:

### Step 3.2 - Add a failing C debug-metadata lit test [x]

Add a small multi-file C fixture with an included header and several distinct
statements. Compile with `-g -gdwarf-4`, then check with `llvm-readelf` and,
when added to the build, `llvm-dwarfdump` that the object contains the four
required debug sections and correct source rows.

The first version of this test must fail on the current absence of `.debug_*`.
Also add `llvm-dwarfdump` to the documented/build test targets if the local
build does not currently produce it.

> **Implementation Notes**: Added `llvm/test/CodeGen/V6CLANG/debug-line.ll` with
> a minimal debug compile unit and line location; it failed before MC debug
> support was enabled and now verifies the required DWARF sections. Added
> `clang/test/Driver/v6clang-debug-metadata.c`, a real C/header fixture compiled
> with `-g -gdwarf-4`, which checks emitted sections, source names, and decoded
> line-table rows.

### Step 3.3 - Enable V6CLANG MC debug information [x]

Set the appropriate `MCAsmInfo` debug-information capability in
`V6ClangMCAsmInfo.cpp`. Verify that `CodePointerSize = 2` produces DWARF address
size 2 and that generated `.loc` information survives instruction selection,
pseudo expansion, and assembly.

Do not assume this single switch completes the work. Re-run the failing test
immediately and inspect every generated relocation and malformed-section
diagnostic.

> **Implementation Notes**: Set `SupportsDebugInformation = true` in
> `llvm/lib/Target/V6CLANG/MCTargetDesc/V6ClangMCAsmInfo.cpp`. The resulting object
> emits DWARF v4 with address size 2.

### Step 3.4 - Complete the V6CLANG debug relocation ABI [x]

Inventory fixups generated by the Step 3.2 object. The current backend handles
`FK_Data_1`, `FK_Data_2`, and target 8/16-bit fixups; it applies `FK_Data_4`
locally but has no ELF relocation for an unresolved 32-bit value.

If DWARF section references emit unresolved `FK_Data_4`, add `R_V6CLANG_32` to the
shared V6CLANG relocation definitions, MC ELF writer, relocation-name support, and
`lld/ELF/Arch/V6Clang.cpp`. LLD must write a little-endian 32-bit absolute value.
Keep CPU addresses 16-bit; the 32-bit relocation exists for ELF/DWARF section
offsets, not for machine instructions.

Add MC relocation tests and LLD positive/overflow tests before enabling the
new relocation in production output.

> **Implementation Notes**: The debug object probe emitted unresolved
> `FK_Data_4` references as relocation type zero. Added `R_V6CLANG_32 = 5` in the
> MC writer and both LLD source trees; it writes 32-bit little-endian DWARF
> section references. The regression verifies its `00000505` encoding. Named
> V6CLANG relocations are accepted by `.reloc`, `llvm-readelf` reports their names,
> and `R_V6CLANG_32` preserves the `0xffffffff` boundary value. ELF32 relocation
> fields cannot represent a wider value; malformed relocation names are
> rejected before object creation.

### Step 3.5 - Verify linked DWARF preservation and GC [x]

Link at least two `-g` objects with the default script and `--gc-sections`.
Verify:

- debug sections are non-allocating and do not appear in ROM bytes;
- debug relocations resolve to final VMAs;
- line rows for live functions remain valid;
- rows for discarded function sections are absent or ignored by consumers;
- final `.symtab` values equal disassembly addresses;
- no stripping occurs unless explicitly requested.

Add a V6CLANG linker lit test that correlates `llvm-dwarfdump --debug-line`,
`llvm-readelf -s`, and `llvm-objdump -d` for the same final ELF.

> **Implementation Notes**: `debug-line.ll` links its debug object through the
> LLD GNU dispatcher and checks that all DWARF sections survive with no
> remaining relocations. A manual final-ELF probe also confirmed that
> `.debug_line` contains the linked `.text` address. The planned two-object
> `--gc-sections` live/discarded-function coverage now exists in
> `llvm/test/Linker/V6CLANG/debug-gc-sections.test`: live code and symbols remain,
> while `.text.dead` and its symbol are removed. LLD keeps a non-allocating
> `dead.c` line-program contribution with a zero address after collection, so
> an adapter must aggregate only rows that fall in a final executable section.

### Step 3.6 - Establish the retained-ELF build workflow [x]

Document and test the explicit `program.elf` then `llvm-objcopy` flow. Update
sample launch configurations to name both `program` (ROM) and `debugProgram`
(ELF).

Add a Clang-driver convenience mode only after the explicit flow passes: for a
debug flat-ROM link, preserve a deterministic sibling ELF or accept an
explicit debug-companion output path. Do not silently change release builds or
make `-save-temps` the public debug-artifact contract.

> **Implementation Notes**: Debug flat-ROM links now retain `<output>.elf` in
> `clang/lib/Driver/ToolChains/V6Clang.cpp`; the normal `llvm-objcopy` stage still
> derives `<output>.rom` from it. Non-debug flat-ROM links still use a temporary
> ELF. `clang/test/Driver/v6clang-debug-companion.c` and the V6CLANG build guides cover
> the behavior.

### Step 3.7 - Implement the adapter ELF/DWARF reader [ ]

Use a maintained structured ELF/DWARF library in the adapter's implementation
language. Do not parse `llvm-dwarfdump`, map files, listings, or `readelf` text.

Implement strict validation for ELF32 little-endian `EM_V6Clang`, address size 2,
supported DWARF version, line-program bounds, executable-section membership,
and 16-bit addresses. Expose a small `DebugIndex` API for source-to-address,
address-to-source, and address-to-symbol queries.

Measure load/index time and memory on a representative large program. Cache by
canonical ELF path, size, modification time, and content digest; invalidate on
any change.

> **Implementation Notes**: No DAP adapter implementation is present in this
> workspace. The reader and index remain pending in the repository that owns
> the new emulator/adapter.

### Step 3.8 - Validate ELF/ROM identity [ ]

Implement byte reconstruction and SHA-256 comparison before debug attach.
Cover section gaps, non-zero lowest VMA, NOBITS sections, non-alloc debug
sections, and custom linker scripts. Report both paths and digests on mismatch
without exposing misleading verified breakpoints.

> **Implementation Notes**:

### Step 3.9 - Implement DAP `setBreakpoints` [ ]

Implement the resolution contract above, including replace-all semantics per
source, duplicate-address elimination, one-to-many logical breakpoint state,
line/column reporting, source path mapping, conditions supported by v6emul,
and IPC failure cleanup.

Add adapter unit tests using tiny checked-in ELF fixtures and a fake v6emul
transport. Include exact line, column selection, non-emitting line, included
file, same basename in two directories, several addresses for one source line,
duplicate addresses, stale ELF, reconnect, and repeated replacement requests.

> **Implementation Notes**:

### Step 3.10 - Implement PC-to-source and symbol lookup [ ]

Use the reverse index for stopped events, stack-frame source/line, current-line
highlighting, and synthetic frame names. Use `.symtab` only for names; line
ranges remain authoritative for source display. Return a disassembly frame
when the PC is outside all valid line sequences.

> **Implementation Notes**:

### Step 3.11 - Integrate v6asm metadata [x]

The upstream v6asm implementation is available at
`C:\Work\Programming\v6asm\design\plan_v6asm_dwarf_debug_metadata.md`.
The packaged `tools/v6asm/v6asm.exe` is the corresponding
`2026.07.29-6dab24c` release and its help exposes `-g` / `--debug` and
`--debug-elf`. Pin its hash in the feature result, then link a debug v6asm
object with a debug Clang object. The adapter must consume the mixed final ELF
without identifying which producer emitted each line table.

> **Implementation Notes**: Upstream v6asm implemented the DWARF writer,
> source attribution, local debug symbols, `-g`, and direct-ROM companion ELF
> support on 2026-07-29. The copied `2026.07.29-6dab24c` package exposes `-g`
> / `--debug` and `--debug-elf`; capture its executable hash in integration
> results. A local `-g -f obj` probe emitted
> `.debug_info`, `.debug_abbrev`, `.debug_line`, `.debug_str`, and
> `.rela.debug_line` with two code-section relocations. `llvm-readelf` and
> `llvm-readobj` now print named V6CLANG relocations after the LLVM-side
> relocation-name registration. A direct-ROM probe emitted
> a 3-byte ROM plus an ELF32 `ET_EXEC` companion with `.text` at `0x0100` and
> all four DWARF sections. The packaged executable SHA-256 is
> `4C41C67DD24E3F8BEC186A040401A1A862A50D7E3E3231F216F773D1EC1158BC`.
> `llvm/test/Linker/V6CLANG/debug-v6asm-mixed.test` compiles a Clang `-g -gdwarf-4`
> object and a v6asm `-g -f obj` object, links them into one ELF, and verifies
> both symbols, both source file names in `.debug_line`, all required DWARF
> sections, and complete relocation resolution. Adapter consumption remains
> pending outside this repository.

### Step 3.12 - Build (local V6CLANG workspace) [x]

Run `pwsh scripts/build.ps1 -SkipTests`, build the adapter/emulator with their
documented presets, and build the upstream v6asm workspace. Ensure
`llvm-dwarfdump`, `llvm-readelf`, `llvm-objdump`, `ld.lld`, and
`llvm-objcopy` are available in the test build.

> **Implementation Notes**: Ran `pwsh scripts/build.ps1 -SkipTests`. CMake
> configured LLVM with the experimental V6CLANG target, then Ninja rebuilt Clang,
> LLD, LLc, object tools, FileCheck, and `not`; the
> script also assembled `crt0.o`. The requested adapter/emulator and upstream
> v6asm workspace builds are outside this repository and were intentionally
> not run.

### Step 3.13 - Lit tests: debug metadata and relocation [x]

Run focused MC, CodeGen, and Linker V6CLANG tests covering debug sections,
`R_V6CLANG_32` if added, linked addresses, GC, include paths, optimized repeated
lines, and malformed/overflow relocation rejection.

> **Implementation Notes**: Focused `llvm-lit` runs cover LLVM IR and C/header
> debug metadata, named `R_V6CLANG_32`, its complete ELF32 boundary value,
> malformed relocation-name rejection, final linked addresses, live/dead
> `--gc-sections` behavior, named LO8/HI8 relocations, and mixed Clang/v6asm
> linkage. The final local run passed all 170 lit tests. Optimized
> repeated-line coverage remains future test expansion, not a blocker for the
> Level 1 `-O0` contract.

### Step 3.14 - End-to-end source breakpoint test [ ]

Build a multi-file C/assembly program to final ELF and ROM, launch `v6emul`,
send a DAP `setBreakpoints` request for a known line, and verify:

- the adapter returns a verified breakpoint at the expected line;
- the emulator receives the address shown by `llvm-objdump`;
- execution stops at that PC;
- the stopped DAP frame maps back to the same source line and function;
- replacing and clearing the source breakpoint removes every underlying
  emulator breakpoint.

Repeat for a v6asm include and for a macro/loop line that maps to more than one
address.

> **Implementation Notes**:

### Step 3.15 - Run regression tests [ ]

Run `python tests/run_all.py`, the v6emul unit/IPC/e2e suites, the adapter test
suite, and `cargo test --workspace` in upstream v6asm. Confirm non-debug builds
remain byte-identical and debug sections do not change ROM bytes.

> **Implementation Notes**:

### Step 3.16 - Verification assembly steps from `tests/features/README.md` [ ]

Add or select a feature case that records the expected source lines, final
addresses, symbols, ROM digest, and breakpoint stop PC. Follow the compile,
assemble/link, emulate, and comparison steps in `tests/features/README.md`.

> **Implementation Notes**:

### Step 3.17 - Make sure `result.txt` is created [ ]

Create `result.txt` for the feature case according to
`tests/features/README.md`. Include debug-section presence, resolved
source/address pairs, ELF/ROM identity result, actual stopped PC, and emulator
observable output.

> **Implementation Notes**:

### Step 3.18 - Documentation [ ]

Update the V6CLANG build/Clang guides, v6emul IPC docs, adapter launch
configuration reference, and v6asm docs. Document path mapping, line movement,
multi-address breakpoints, optimized-code limitations, runtime address rules,
artifact mismatch errors, and stripping behavior.

Mark every completed plan step `[x]` and fill its Implementation Notes with
files changed, tests run, and deviations from this design.

> **Implementation Notes**:

### Step 3.19 - Sync mirror [x]

Run `pwsh scripts/sync_llvm_mirror.ps1`. Ensure V6CLANG target, LLD, Clang, and lit
test changes are present in both canonical and tracked mirror locations, with
no unrelated generated changes.

> **Implementation Notes**: Ran `pwsh scripts/sync_llvm_mirror.ps1` after the
> canonical LLVM, LLD, Clang, and test updates. The modified V6CLANG source files
> match their tracked mirror copies byte-for-byte.

## 4. Expected Results

### Example 1 - C source breakpoint

A request for `src/main.c:42` resolves from the final ELF to `0x137A`; the
adapter installs numeric breakpoint `0x137A`, execution stops there, and the
stack frame reports `main.c:42`.

### Example 2 - Included assembly file

A breakpoint in `lib/sprites.asm` resolves independently from the including
file because the DWARF file table contains its normalized path.

### Example 3 - Repeated expansion

One v6asm loop source line emits instructions at `0x2100`, `0x2104`, and
`0x2108`. One DAP breakpoint owns three emulator breakpoints and is reported
verified when all are installed.

### Example 4 - Stale debug artifact

The configured ELF's reconstructed load image does not match `program.rom`.
The adapter stops launch/source-debug setup with a precise mismatch error
instead of placing a breakpoint at an unrelated address.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Enabling MC debug support exposes a missing relocation | Start with a failing object test; inventory fixups; add `R_V6CLANG_32` only when demonstrated |
| LLD GC leaves stale debug rows | Linker test live and discarded function sections; validate every indexed row belongs to executable output |
| Adapter adds `0x0100` twice | Default to zero bias and assert final ELF VMA equals disassembly/emulator PC |
| Windows and DWARF paths differ | Canonical matching plus explicit `sourceFileMap`; reject ambiguous basename matches |
| One source line maps to many addresses | Model one logical DAP breakpoint owning a set of emulator IDs |
| Macro invocation and definition compete for one address | Invocation is the Level 1 statement row; retain definition only as non-statement provenance and document the policy |
| Optimizations coalesce or remove lines | Return actual resolved lines, support unverified results, and test `-O0` plus representative `-O2` code |
| Debug parsing slows launch | Parse once, build compact indexes, cache by digest, and set a representative performance budget |
| Debug sections accidentally enter ROM | Keep them non-allocating and compare debug/non-debug ROM bytes in tests |
| Packaged v6asm diverges from upstream | Pin the `2026.07.29-6dab24c` executable hash in results; verify `--version`, `--help`, object output, and ROM companion output before each integration run |

## 6. Relationship to Other Improvements

- Builds on the completed native LLD and `llvm-objcopy` flow in
  `design/plan_O_LLD_native_linker.md`.
- Builds on v6asm relocatable ELF object output; it does not replace that
  format.
- Complements v6emul's existing numeric breakpoint and debug-attach IPC.
- Establishes the base needed for symbol watches and named synthetic frames,
  but not typed variables or semantic unwinding.

## 7. Future Enhancements

- DWARF v5 after all chosen adapter libraries pass equivalent fixtures.
- `.debug_info` subprograms, variables, types, scopes, and location lists.
- `.debug_frame` or `.eh_frame` and a defined V6CLANG unwind ABI.
- `.debug_macro` or equivalent macro definition/invocation views.
- Build-ID notes as a fast precheck in addition to ROM-byte verification.
- DAP function breakpoints, data breakpoints from symbols, and source-aware
  stepping over multi-instruction expansions.
- Split DWARF or compressed debug sections if artifact size becomes material.

## 8. References

* [Debug Adapter Protocol - setBreakpoints](https://microsoft.github.io/debug-adapter-protocol/specification#Requests_SetBreakpoints)
* [DWARF Debugging Information Format](https://dwarfstd.org/)
* `docs/V6ClangBuildGuide.md`
* `docs/V6ClangArchitecture.md`
* `docs/V6ClangUsage.md`
* `tools/v6emul/docs/cli.md`
* `tools/v6emul/docs/ipc-protocol.md`
* `tools/v6asm/docs/object-output.md`
* `C:\Work\Programming\v6asm\design\plan_v6asm_dwarf_debug_metadata.md`
* `design/future_plans/README.md`
