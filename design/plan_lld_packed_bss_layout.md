# Plan: LLD Packing for Page-Constrained BSS Blocks

## Goal

Teach the V6CLANG `ld.lld` target to pack independently garbage-collectable,
runtime-only data blocks into the smallest practical contiguous BSS arena while
respecting the Vector-06c 256-byte page constraints.

The feature replaces the failed assembler-side arena packer described in
`C:/Work/Programming/v6asm/design/plan_pack_blocks.md`. Packing belongs in the
linker because only the linker can see all surviving blocks across object files
after `--gc-sections` has removed unreferenced blocks.

The three input-section kinds are:

| Input section | Kind | Placement rule |
|---|---|---|
| `.bss.pack` | Filler | May start anywhere and may cross a 256-byte boundary. |
| `.bss.pack.align` | Anchor | Must start at an absolute address divisible by 256. |
| `.bss.pack.window` | Windowed | Must fit entirely within one 256-byte page; size must be at most 256 bytes. |

All three kinds are `SHT_NOBITS`, `SHF_ALLOC | SHF_WRITE` input sections. They
reserve runtime address space, but contribute no bytes to the ROM/COM file.
Their final addresses may move freely because V6CLANG relocations are absolute.

## Repository and Mirror Workflow

This project builds against `llvm-project/`, a gitignored clone pinned to
`llvmorg-18.1.0`. Development edits are made and tested in that build tree, but
they are not durable until synchronized to the git-tracked mirrors:

| Build-tree path | Git-tracked mirror | Sync policy |
|---|---|---|
| `llvm-project/lld/ELF/...` | `lld/ELF/...` | Individual `xcopy` entries for every modified or new upstream LLD file. |
| `llvm-project/clang/lib/Driver/ToolChains/V6CLANG/v6clang.ld` | `clang/lib/Driver/ToolChains/V6CLANG/v6clang.ld` | Existing individual `xcopy` entry. |
| `llvm-project/llvm/test/Linker/V6CLANG/...` | `tests/lit/Linker/V6CLANG/...` | Existing full `robocopy /MIR`, excluding `Output/`. |

`scripts/build.ps1` runs `scripts/sync_llvm_mirror.ps1` at the start of every
build. Therefore the implementation workflow is:

1. Edit source and canonical lit tests under `llvm-project/`.
2. Run `scripts/sync_llvm_mirror.ps1` immediately when a tracked checkpoint is
   needed; a normal `build.ps1` run also performs this outward sync.
3. Review and commit the resulting files under `lld/`, `clang/`, and
   `tests/lit/`. Never author a lit test directly in `tests/lit/`; the next
   `robocopy /MIR` would overwrite or delete it.
4. On a fresh clone, run `scripts/populate_llvm_project.ps1` to copy the tracked
   mirrors back into the pinned `llvm-project/` clone before building.

Every new or newly modified upstream LLD file in this plan must be added in
both directions: build tree to tracked mirror in `sync_llvm_mirror.ps1`, and
tracked mirror to build tree in `populate_llvm_project.ps1`. The final review
must use the tracked mirror diff, because `git status` does not report changes
inside `llvm-project/`.

## Success Criteria

1. `ld.lld --gc-sections` discards an unreferenced packed block independently
   of every other packed block.
2. All surviving anchors begin at an address where `addr % 256 == 0`.
3. All surviving windows satisfy `size <= 256` and
   `addr / 256 == (addr + size - 1) / 256` for non-empty blocks.
4. Fillers may occupy alignment holes, window bump holes, and page-crossing
   ranges.
5. Packing is global across all linked object files, not per object.
6. Packed sections remain `SHT_NOBITS`; `llvm-objcopy -O binary` output does
   not grow because of their contents.
7. The default script keeps `__bss_start` and `__bss_end` around both ordinary
   BSS and the packed arena so crt0 zero-initializes every packed block.
8. The 23-block reference workload packs 3232 live bytes into a 3232-byte
   arena with zero waste.
9. Links that contain no packed sections, non-V6CLANG links, and relocatable
   (`ld.lld -r`) links retain existing behavior.

## Required Producer Contract

The linker can move and garbage-collect only ELF input sections, not labels or
subranges within one input section. Therefore **each logical block must be one
independent input section**.

- Blocks in separate object files may use the same section name normally.
- Multiple blocks of one kind in a single object must be emitted as distinct
  ELF sections with the same visible name, using the assembler's unique-section
  facility (for example GAS/LLVM MC's `unique,<id>` section attribute), or by
  another mechanism proven to create separate section headers.
- Merely switching repeatedly to `.section .bss.pack` is insufficient if the
  assembler merges all reservations into one section; LLD would see one atomic
  block, and block-level GC and packing would be impossible.
- Each block should have at least one symbol through which live code/data can
  reference it. Normal relocations provide the GC reachability edge.
- Input `sh_addralign` should be 1 for all three kinds. The semantic 256-byte
  constraints are imposed by the V6CLANG packer; setting every anchor's ELF
  alignment to 256 would unnecessarily align the whole output arena and lose a
  usable leading hole.

Phase 1 must verify the exact LLVM MC syntax and resulting section table before
the LLD implementation begins. If LLVM MC cannot emit same-name unique input
sections, adopt unambiguous suffixed names instead:

- `.bss.pack.<id>`
- `.bss.pack.align.<id>`
- `.bss.pack.window.<id>`

In that fallback, classification must use the longest constrained prefix first
(`window`, then `align`, then filler), and the default linker script patterns
must accept both exact and suffixed forms. Do not silently classify arbitrary
`.bss.pack*` spelling mistakes as fillers.

## Locked Packing Policy

Use the assembler experiment's deterministic best-fit-decreasing policy. It is
a heuristic rather than a proof of globally optimal bin packing, but it reaches
the theoretical minimum on the real dataset and has predictable bounded cost.

All comparisons use block size descending, then original link/input order as a
stable tie-breaker.

### 1. Build the anchor skeleton

Place anchors in descending size order. For each anchor:

1. Round the absolute append cursor up to the next 256-byte boundary.
2. Register the skipped interval as a hole.
3. Place the anchor and advance by its size.

Descending anchor order leaves the smallest anchor last, reducing forced
trailing padding when there are too few fillers to consume all holes.

### 2. Place windows first

Process windows in descending size order before fillers because windows have
the tighter constraint. For each window, choose the smallest existing hole in
which it can be placed without crossing a page boundary.

For a candidate hole `[begin, end)`:

1. Try `begin` if the block ends in the same page.
2. Otherwise try `align_up(begin, 256)` if the complete block still fits before
   `end`.
3. Split the selected hole into any prefix and suffix left by the placement.

If no hole fits, append the window. If the append position would straddle a
page, bump it to the next page boundary and register the skipped interval as a
new hole so later, smaller blocks can reclaim it.

Reject a window larger than 256 bytes. Reject arithmetic overflow rather than
wrapping an address calculation.

### 3. Place fillers

Process fillers in descending size order. Place each into the smallest hole
large enough for it, at the hole's beginning, and retain any suffix as a
smaller hole. Append the filler if no hole fits. Fillers may cross pages.

### 4. Finalize the arena

- Arena start is the dedicated packed output section's address; it need not be
  page-aligned.
- Arena size is `max(block_end) - arena_start`. Remaining interior holes count
  as runtime waste but not file bytes.
- Sort placed input sections by final address before exposing them to ordinary
  LLD consumers, then assign monotonically increasing `outSecOff` values.
- Emit a stable map even though semantic source/link order was discarded.

Do not preserve source order: references are resolved through symbols and all
V6CLANG relocations (`R_V6CLANG_8`, `R_V6CLANG_16`, `R_V6CLANG_LO8`, `R_V6CLANG_HI8`) are absolute.

## LLD Integration Design

### Scope and gating

Gate the behavior on all of the following:

- `config->emachine == EM_V6Clang`;
- final executable link (not `-r`);
- a dedicated output section containing recognized packed inputs;
- every allocatable input in that output section is a recognized packed kind.

Do not change generic ELF layout for other targets. Avoid a new command-line
option in the first implementation: the explicit input names plus the V6CLANG
target are the opt-in contract. A disable/debug switch may be added later if
field diagnosis demonstrates a need.

### Dedicated output section

Update the default V6CLANG script so packed inputs are isolated from ordinary BSS:

```ld
__bss_start = .;
.bss.pack : {
  *(.bss.pack.align)
  *(.bss.pack.window)
  *(.bss.pack)
}
.bss : { *(.bss .bss.* COMMON) }
__bss_end = .;
```

If Phase 1 selects suffixed fallback names, add those patterns beside the exact
forms. Ensure `.bss` does not consume packed inputs first; linker-script input
patterns are first-match, so `.bss.pack` must precede the broad `.bss.*` rule.

Keeping the arena in its own output section makes the special offset allocator
local and keeps linker-script symbol assignments, ordinary BSS order, and
NOBITS writing straightforward. Because both output sections are NOBITS and
`__bss_end` follows both, crt0's existing contiguous zeroing loop remains valid.

Custom scripts must use the same dedicated-output-section structure to enable
packing. If recognized packed inputs are instead swallowed by a broad `.bss*`
rule, LLD should either lay them out normally or issue one clear V6CLANG warning;
it must not partially pack a mixed output section. Lock the choice with a test
and document it. Prefer normal layout plus a warning for compatibility.

### Placement hook

Implement a small V6CLANG-owned packing module rather than putting the algorithm in
`Arch/V6Clang.cpp`, which only owns target relocation behavior today:

- `llvm-project/lld/ELF/V6ClangPackedSections.h`
- `llvm-project/lld/ELF/V6ClangPackedSections.cpp`

The module should expose narrowly-scoped operations such as:

```cpp
bool isV6ClangPackedInput(const InputSection &sec);
bool assignV6ClangPackedOffsets(OutputSection &osec, uint64_t startAddr,
                            uint64_t &endAddr);
```

Call it from `LinkerScript::assignOffsets()` only for the qualifying dedicated
output section. The helper receives the final absolute start address because
anchor/window legality is based on absolute 256-byte pages, not merely output
section-relative offsets.

The helper must be repeatable and deterministic: `assignAddresses()` runs more
than once while address-dependent content converges. Repeated calls with the
same live sections and start address must produce identical order, offsets, and
size. Preserve an immutable original-order index for tie-breaking rather than
using the vector order mutated by an earlier pass.

After packing, update the same state ordinary `assignOffsets()` would update:

- each input section's `outSecOff`;
- packed output section `size`;
- linker-script `dot` / memory-region consumption;
- monotonic section order used by map generation and output writers.

Keep the normal `OutputSection::writeTo()` path. It already emits no contents
for `SHT_NOBITS`, so no ROM bytes or special zero filler are required.

### Garbage collection ordering

Run normal LLD garbage collection before packing. `MarkLive` already follows
relocations from live sections and marks each referenced `InputSection`
independently. The packer must inspect only the surviving input sections already
attached by `LinkerScript::processSectionCommands()`; it must not add GC roots,
merge blocks, or retain sections merely because their names are recognized.

Verify these cases:

- a live relocation to a block keeps exactly that block;
- an unreferenced block is absent under `--gc-sections`;
- `KEEP()` and `-u symbol` retain a block through standard LLD semantics;
- without `--gc-sections`, all input blocks participate in packing.

### Safety invariants

The implementation must assert or diagnose:

- every packed input is `SHT_NOBITS`;
- flags include `SHF_ALLOC | SHF_WRITE` and exclude `SHF_EXECINSTR`, TLS, merge,
  strings, and link-order semantics;
- block size is non-zero (choose warning-and-ignore or hard error in Phase 1;
  prefer a hard error because an empty movable block is almost certainly a
  producer mistake);
- windows are at most 256 bytes;
- no packed input has relocations applying *to bytes inside it* (NOBITS cannot
  carry initialized contents); relocations from other sections to its symbols
  are expected;
- computed addresses remain in the V6CLANG 16-bit address space and do not overlap
  later sections, reserved memory, video RAM constraints expressed by a custom
  script, or the stack boundary;
- packed `outSecOff` values are monotonic after final sorting, avoiding hidden
  assumptions in map writing, relocation scanning, and generic output code.

Do not allow aliases or symbols within a block to escape the block's extent.
Symbols naturally remain correct because their value is input-section-relative
and `SectionBase::getVA()` adds the newly assigned `outSecOff`.

## Implementation Phases

### Phase 1 - Lock the ELF contract

1. Create a minimal V6CLANG assembly fixture containing two same-kind blocks in one
   object and one block in a second object.
2. Verify the LLVM MC unique-section syntax with `llvm-readelf -S -s -r`.
3. Verify all blocks are separate `SHT_NOBITS`, alloc/write, alignment 1 input
   sections with independent symbols.
4. Link with `--gc-sections` and prove one referenced symbol retains one block
   while its neighbor is discarded.
5. Decide exact-name unique sections versus suffixed names and lock the result
   in MC/linker tests before coding the packer.

Exit gate: one block equals one independently collectible ELF input section.

### Phase 2 - Add and unit-test the pure packer

1. Add a file-local/plain-data model: kind, size, original order, placed
   address, and half-open holes.
2. Implement overflow-checked `align_up`, same-page testing, hole splitting,
   best-fit selection, and deterministic tie-breaks.
3. Implement descending anchors, windows-first placement, append-bump hole
   registration, then fillers.
4. Keep the algorithm independent of ELF objects so it can be unit-tested with
   compact synthetic cases.
5. Add tests for zero/one block, exact 256-byte windows, oversized windows,
   leading holes, interior prefix/suffix splits, page bumps, equal-size stable
   ties, anchors larger than one page, and near-`0xffff` overflow.

Exit gate: the pure packer validates every placement invariant and reproduces
the reference layout size without invoking the full linker.

### Phase 3 - Integrate with LLD layout

1. Add `V6ClangPackedSections.cpp` to `llvm-project/lld/ELF/CMakeLists.txt`.
2. Classify recognized input section names and validate type/flags/size.
3. Add the V6CLANG-gated packed-output path to
   `LinkerScript::assignOffsets(OutputSection *)`.
4. Preserve original-order tie-break metadata across repeated
   `assignAddresses()` calls.
5. Reorder the dedicated output section's input vectors by final address and
   assign monotonic `outSecOff` values.
6. Update output size, dot, and memory-region accounting exactly once per pass.
7. Confirm symbols, `SIZEOF(.bss.pack)`, `ADDR(.bss.pack)`, map output, and
   following output-section addresses converge across repeated assignments.

Exit gate: full `ld.lld` tests pass with correct addresses and no changes to
non-packed links.

### Phase 4 - Update the default V6CLANG script and runtime bounds

1. Add the dedicated `.bss.pack` output section before ordinary `.bss` in
   `clang/lib/Driver/ToolChains/V6CLANG/v6clang.ld`.
2. Place `__bss_start` before `.bss.pack` and `__bss_end` after ordinary
   `.bss`.
3. Verify an empty packed arena does not create an address gap or alter existing
   binaries unexpectedly.
4. Verify crt0 zeros packed and ordinary BSS in one contiguous range.
5. Document custom-script requirements and packed section semantics in
   `docs/V6ClangArchitecture.md` and `docs/V6ClangBuildGuide.md`.

Exit gate: the standard clang driver path enables packing automatically and
produces a runnable image.

### Phase 5 - Mirror and distribution plumbing

1. After the first working build-tree implementation, run
   `scripts/sync_llvm_mirror.ps1` and verify these durable tracked copies exist:
   - `lld/ELF/V6ClangPackedSections.h`
   - `lld/ELF/V6ClangPackedSections.cpp`
   - `lld/ELF/LinkerScript.cpp`
   - `lld/ELF/CMakeLists.txt`
   - `clang/lib/Driver/ToolChains/V6CLANG/v6clang.ld`
   - all new tests under `tests/lit/Linker/V6CLANG/`
2. Add individual, symmetric `xcopy` entries for both new packed-section files
   and the newly modified upstream `LinkerScript.cpp`. Keep the existing
   `CMakeLists.txt` and `v6clang.ld` entries. Update both scripts:
   - `scripts/sync_llvm_mirror.ps1`
   - `scripts/populate_llvm_project.ps1`
3. Author linker tests only under
   `llvm-project/llvm/test/Linker/V6CLANG/`. Rely on the existing full-directory
   mirror to populate `tests/lit/Linker/V6CLANG/`; do not add individual test
   `xcopy` commands and do not edit the tracked test mirror directly.
4. Ensure the updated V6CLANG linker script is copied into the staged clang
   resource tree by the existing packaging flow.
5. Run `sync_llvm_mirror.ps1`, inspect the tracked diff, then recreate or clean
   the relevant `llvm-project/` files and run `populate_llvm_project.ps1`.
   Rebuild and verify the round trip preserves the implementation and tests.

Exit gate: a clean populated `llvm-project/` rebuild contains exactly the same
feature as the tracked mirrors, and no implementation exists only in the
gitignored build tree.

### Phase 6 - Migrate the assembler-side experiment

1. Convert the 23 real blocks from `temp/pack/runtime_data.asm` into the locked
   ELF producer representation without pre-packing offsets in the assembler.
2. Remove any assembler-side arena alignment that would hide a leading linker
   hole.
3. Keep source declarations readable: block kind and block symbol should remain
   visible at each declaration.
4. Retire or mark superseded the assembler-side packing implementation while
   retaining its study script and expected statistics as a regression oracle.

Exit gate: source objects carry constraints only; all final placement decisions
come from `ld.lld`.

## Test Plan

Add canonical project tests under `llvm-project/llvm/test/Linker/V6CLANG/`. The
existing `robocopy /MIR` rule synchronizes them to the durable
`tests/lit/Linker/V6CLANG/` mirror. Do not add the feature only under
`llvm-project/lld/test/ELF/`: that directory is gitignored and currently has no
tracked mirror in this repository. Relevant upstream LLD ELF tests may still be
run as non-persistent compatibility checks.

Add one V6CLANG end-to-end feature fixture under the existing tracked feature-test
structure as well.

### ELF/linker tests

1. **Kinds and addresses:** link one block of each kind; inspect symbols with
   `llvm-readelf -s` and check anchor/window arithmetic.
2. **Cross-object packing:** put blocks in at least three objects; prove holes
   are filled across object boundaries.
3. **GC:** reference selected blocks from live `.text`; verify unreferenced
   blocks disappear and arena size shrinks.
4. **KEEP and `-u`:** prove standard roots still work.
5. **Window diagnostics:** reject 257-byte windows; accept exactly 256 bytes at
   a page boundary.
6. **Invalid section diagnostics:** reject PROGBITS, executable, TLS, merge,
   non-write, and over-aligned producer mistakes as decided in Phase 1.
7. **Absolute base:** begin packed BSS at a non-page-aligned address and prove
   constraints use absolute addresses.
8. **Append-bump hole:** force a window bump, then prove a smaller window or
   filler occupies the skipped bytes.
9. **Determinism:** link identical inputs twice and compare map/symbol output;
   equal-size ties follow original link order.
10. **Script expressions:** check `ADDR`, `SIZEOF`, `__bss_start`, `__bss_end`,
    and the address of the output section after BSS.
11. **Custom script:** mixed-output collection does not partially pack and
    produces the chosen warning/normal-layout behavior.
12. **No regression:** no packed sections, non-V6CLANG target, and `-r` retain
    ordinary layout.
13. **File size:** compare ELF program headers and flat binary size; NOBITS
    blocks reserve memory but do not add initialized bytes.
14. **64 KiB overflow:** a packed arena crossing `0x10000` fails clearly.

### Reference efficiency regression

Use the 23 real blocks from the assembler experiment:

| Model | Arena | Waste | Efficiency |
|---|---:|---:|---:|
| No window type (windows treated as anchors) | 3570 | 338 | 90.5% |
| Window type, source anchors, combined fill | 3339 | 107 | 96.8% |
| Descending anchors, windows first, append-bump holes | 3232 | 0 | 100% |

The LLD test must assert the final arena size is exactly 3232 bytes for 3232
bytes of live block data. Also retain a human-readable map comparison so an
algorithm change that preserves size but violates a constraint is visible.

### End-to-end runtime test

Build a small program through the normal clang driver that:

- references one block of every kind;
- leaves at least one packed block unreferenced;
- writes and reads the first and last byte of each live block;
- confirms the dead symbol is absent from the linked ELF;
- runs under `v6emul` and emits a known success byte;
- confirms the resulting ROM contains no bytes for the NOBITS arena.

## Verification Commands

Use the repository's normal MSVC-enabled build path.

```powershell
pwsh scripts\build.ps1 -SkipTests
python tests\run_all.py
```

During development, use the narrow linker suite first:

```powershell
llvm-build\bin\llvm-lit.exe -sv llvm-project\llvm\test\Linker\V6CLANG\v6clang-pack-*.s
```

Inspect representative outputs with:

```powershell
llvm-build\bin\llvm-readelf.exe -S -s -l out.elf
llvm-build\bin\ld.lld.exe -Map=out.map -o out.elf @inputs.rsp
llvm-build\bin\llvm-objcopy.exe -O binary out.elf out.bin
```

Final gates:

- targeted LLD packing tests pass;
- relevant upstream LLD ELF tests affected by `LinkerScript.cpp` still pass as
   compatibility checks;
- V6CLANG codegen/linker/feature suites pass;
- 23-block arena is 3232 bytes with zero constraint violations;
- every changed build-tree file and canonical test appears in its tracked
   mirror after sync;
- mirror sync and reverse-populate round trip cleanly;
- rebuild from the populated mirror reproduces the same symbol addresses and
  flat binary.

## Risks and Mitigations

### Repeated address assignment

LLD calls `assignAddresses()` repeatedly for relaxation and script-symbol
convergence. A packer that uses already-mutated input order as its tie-breaker
can oscillate. Preserve original order and make each invocation a pure function
of start address plus the live block set.

### Hidden monotonic-offset assumptions

Generic LLD code sorts relocations, writes gaps, and emits map entries using
`outSecOff`. Never leave the command vectors in source order with non-monotonic
offsets. Reorder the dedicated arena's sections into final address order.

### Linker-script interleaving

Symbol assignments or byte commands inside the packed output section make a
global reorder ambiguous. Require the dedicated simple output-section form and
diagnose/fall back for mixed commands rather than guessing.

### Producer section merging

If several logical blocks become one ELF input section, no linker algorithm can
recover their boundaries or GC them independently. Make the Phase 1 section
table test a hard prerequisite and retain it permanently.

### Heuristic quality

Best-fit-decreasing is not mathematically optimal for every possible input.
Track total live bytes, arena size, and waste in map/test output. If real inputs
later expose material waste, add an optional bounded improvement pass (for
example, local swaps among the final few blocks) without changing constraints
or determinism. An exponential exact solver is out of scope.

### Upstream maintenance

`LinkerScript.cpp` is an upstream core file. Keep its change to one V6CLANG-gated
call into a target-owned helper, add generic no-regression tests, and mirror the
file explicitly in both sync directions.

## Non-Goals

- Packing initialized data or executable code.
- Packing a subrange of one ELF input section.
- Preserving declaration, object, or command-line order in final addresses.
- Page sizes other than 256 bytes in the first implementation.
- Applying this policy to non-V6CLANG targets.
- Mathematically optimal general bin packing.
- Repacking relocatable (`-r`) output; preserve input constraints for the final
  link instead.
- Inferring anchor/window semantics from ELF alignment alone.

## Checklist

Phase 1 - ELF contract
- [x] Verify same-name unique NOBITS sections in LLVM MC
- [x] Lock exact versus suffixed naming
- [x] Prove independent GC within one and across multiple objects

Phase 2 - Packer
- [x] Implement pure deterministic packing model
- [x] Add constraint, hole, tie, and overflow unit tests
- [x] Reproduce the 3232-byte reference arena

Phase 3 - LLD integration
- [x] Add V6CLANG packed-section module and CMake entry
- [x] Integrate with repeated `LinkerScript::assignOffsets()`
- [x] Preserve monotonic final section order and offsets
- [x] Validate scripts, symbols, map output, and memory regions

Phase 4 - Default script/runtime
- [x] Add dedicated `.bss.pack` output section
- [x] Extend `__bss_start`/`__bss_end` over packed and ordinary BSS
- [x] Verify crt0 zeroing and empty-arena compatibility
- [x] Document section producer and custom-script contracts

Phase 5 - Mirroring/distribution
- [x] Add symmetric copies for both new files and `LinkerScript.cpp`
- [x] Sync canonical Linker/V6CLANG tests into the read-only tracked test mirror
- [x] Inspect and retain all resulting tracked `lld/`, `clang/`, and test diffs
- [x] Verify staged toolchain contains the updated script/linker
- [x] Complete clean mirror round-trip rebuild

Phase 6 - Migration and final validation
- [x] Convert the 23-block runtime-data fixture
- [x] Retire assembler-side object placement logic while preserving ROM mode
- [x] Pass targeted linker, allocator, emulator, size, and determinism gates

## Status

**Implemented and feature-complete.** The V6CLANG-only final-link path, pure
allocator, default script integration, diagnostics, durable mirrors, direct
unit tests, linker tests, and emulator fixture are in place. The external
`v6asm` producer emits one alignment-1 NOBITS section per logical block and its
tracked 23-block fixture links to a zero-waste `0xCA0` arena.

Validated results:

- 5/5 direct packed allocator tests pass.
- 7/7 `Linker/V6CLANG` tests pass after a mirror sync/reverse-populate rebuild.
- The packed-BSS driver/emulator test passes and emits success byte `0x5A`.
- The external 23-block v6asm object contains 4 anchor, 4 window, and 15 filler
   sections totaling 3232 bytes; LLD produces a `0xCA0` NOBITS arena and a
   zero-byte flat binary for the all-NOBITS fixture.
- `scripts/build.ps1 -SkipTests` passes from the populated source tree.
- `python tests/run_all.py` passes all four suites: golden, 165 lit tests,
   packed-BSS end-to-end, and benchmark correctness.