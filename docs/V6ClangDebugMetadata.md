# V6CLANG Debug Metadata

V6CLANG debug builds use DWARF v5 metadata in the final linked ELF. When a build
also produces a flat ROM, that ELF is retained as the ROM's debug companion.
Use the ROM to run the program and the final ELF for symbols and source-line
lookup.

## What a Debug Build Produces

Pass `-g` to the V6CLANG Clang driver:

```bash
llvm-build/bin/clang -target i8080-unknown-v6clang -g \
    main.c -o game.rom
```

This produces:

| File | Purpose |
|------|---------|
| `game.rom` | Flat binary to load and run on Vector-06C or in an emulator. |
| `game.elf` | Final linked debug companion with symbols and DWARF metadata. |

The ROM is derived from `game.elf`, so code addresses in the ELF are the CPU
addresses for the default V6CLANG linker script. A normal non-debug ROM build does
not retain the intermediate ELF.

The companion ELF contains final symbols and standard DWARF v5 sections,
including `.debug_info`, `.debug_abbrev`, `.debug_line`, indexed string and
address tables, range/location lists when required, and `.debug_frame` for C
physical unwinding. It records source file names and instruction source
locations for C and supported assembly inputs.

## C Programs

Compile and link a single C source file in one command:

```bash
llvm-build/bin/clang -target i8080-unknown-v6clang -O0 -g \
    hello.c -o hello.rom
```

For multiple translation units, compile each object with debug information and
link the final program with debug information enabled:

```bash
llvm-build/bin/clang -target i8080-unknown-v6clang -O0 -g -c main.c -o main.o
llvm-build/bin/clang -target i8080-unknown-v6clang -O0 -g -c sprite.c -o sprite.o
llvm-build/bin/clang -target i8080-unknown-v6clang -g \
    main.o sprite.o -o game.rom
```

Headers included by a C translation unit are represented in the line table
when they contain executable source locations.

## ELF-First Workflow

For custom linking, produce the final ELF explicitly and derive the ROM from
it:

```bash
llvm-build/bin/clang -target i8080-unknown-v6clang -O0 -g -c main.c -o main.o
llvm-build/bin/ld.lld -m elf32v6clang \
    -T clang/lib/Driver/ToolChains/V6Clang/v6clang.ld \
    main.o -o game.elf
llvm-build/bin/llvm-objcopy -O binary game.elf game.rom
```

Use this form when supplying a custom linker script or linking objects from
multiple producers. Keep the final linked ELF with the ROM; relocatable `.o`
files do not contain final CPU addresses.

## v6asm Objects

The packaged v6asm assembler can emit compatible debug ELF objects. Enable
debug metadata with `-g`, then link its object with Clang-produced objects:

```bash
tools/v6asm/v6asm.exe -g -f obj asm-leaf.asm -o asm-leaf.o
llvm-build/bin/clang -target i8080-unknown-v6clang -O0 -g \
    -fno-v6clang-auto-include -c c-entry.c -o c-entry.o
llvm-build/bin/ld.lld -m elf32v6clang -e c_entry \
    c-entry.o asm-leaf.o -o mixed.elf
llvm-build/bin/llvm-objcopy -O binary mixed.elf mixed.rom
```

The resulting `mixed.elf` contains the symbols and source-line information
from both C and v6asm inputs.

## Inspecting a Debug Companion

Inspect the final ELF rather than the ROM:

```bash
# Verify the DWARF sections and final symbols.
llvm-build/bin/llvm-readelf -S -s game.elf

# Inspect final instruction addresses with symbols.
llvm-build/bin/llvm-objdump -d game.elf

# Display the raw DWARF line-table payload when diagnosing metadata.
llvm-build/bin/llvm-readelf -x .debug_line game.elf

# Display CIE/FDE rules and per-PC unwind rows.
llvm-build/bin/llvm-dwarfdump --debug-frame game.elf
```

For source-to-address tools, use rows from the final ELF that belong to a
final executable section. This matters when linking with `--gc-sections`:
discarded code has no executable address and must not become a breakpoint.

## Scope and Limitations

- DWARF v5 is the supported format emitted by `-g`. Existing line-table-only
  DWARF v4 artifacts remain a consumer compatibility case.
- The final ELF is authoritative. Its default virtual addresses are already
  16-bit CPU addresses; do not add the ROM base address again.
- Metadata is non-loadable and does not become part of the flat ROM image.
- Physical unwinding is available only where a valid `.debug_frame` FDE and
  recoverable rule cover the stopped PC. Naked/interrupt boundaries stop
  explicitly rather than guessing from stack contents.
- This repository provides debug artifacts and inspection support. A DAP
  adapter that turns source lines into emulator breakpoints is not included
  here; it must consume the final ELF companion.
- Optimized code can merge, move, or remove source statements. For predictable
  source-line inspection, begin with `-O0`.

## Baseline C Variables

At `-O0`, V6CLANG emits tested parameter and local locations for byte/pair
registers, stack-frame homes, promoted static homes, and proven constants.
Frame-relative locations use `DW_OP_fbreg` from a CFA-derived
`DW_AT_frame_base`. A promoted local uses its final linked address through
`DW_OP_addr` or `DW_OP_addrx`, with `DW_OP_plus_uconst` for member offsets.

These are locations valid for their emitted PC ranges, not a promise that all
optimized variables remain available. Complex optimized lifetimes, spill and
reload transitions, O61 patched-code values, pieces, and unavailable ranges
remain unsupported baseline cases.

## Optimized Static Locations

At optimized levels, a recoverable value held in a V6CLANG static-stack slot uses
its final global address in a DWARF v5 location list. When O61 rewrites that
slot into a patched reload immediate, the location uses the final
`.LLo61_N+1` code address as `DW_OP_addrx; DW_OP_plus_uconst 1`. Each entry is
limited to the PC range in which the corresponding storage is valid.

Other optimized movement, gaps, and complex split values remain under active
implementation; an absent location means the value is not currently
recoverable.

## Optimized Preservation Policy

V6CLANG preserves a source location only while the final machine program still
contains the same value in the described physical register or storage. A
redundant-instruction fold may leave an existing location unchanged; a
storage-changing rewrite must replace it with the final global, stack, or O61
patch-byte address. A physical register definition or unsupported storage
transition ends the range, producing an absent-location gap rather than a
stale value.

The post-RA optimizer pipeline remains enabled in debug builds. Its final
instruction stream is authoritative for location-list clobber boundaries.

## Scopes, Types, and Inline Frames

Final V6CLANG ELFs preserve tested `DW_TAG_lexical_block` scopes and separate DIE
identities for shadowed variables. Supported C type metadata includes signed
and unsigned scalar types, `_Bool`/character forms emitted by Clang, enums,
pointers and function pointers, arrays/subranges, structures, unions, members,
typedefs, and const/volatile qualifiers. Offsets and byte sizes follow the
16-bit V6CLANG data layout.

Optimized inline code uses `DW_TAG_inlined_subroutine` with abstract origins
and call coordinates. Nested inline ranges use final linked 16-bit PCs. A
debugger should select an inline frame only when the stopped PC lies within its
emitted range; source entities absent after optimization remain unavailable.

## Final-Link Fixture Matrix

Feature 83 is the deterministic producer handoff fixture. It builds the same
C call/inline program at `-O0`, `-O1`, `-O2`, and `-Os`; each build retains a
final ELF and ROM, verifies DWARF, compares the ROM with
`llvm-objcopy -O binary` of that ELF, and records an emulator snapshot at a
nested-inline stop. The fixture also verifies final symbols, line rows,
location/range sections, and `.debug_frame` coverage for its physical call
chain.

The fixture is a producer contract artifact. Consumers should use it as an
input fixture only after their own DWARF v5 semantic reader is implemented.
It does not claim consumer compatibility by itself.


## Related Documentation

- [V6ClangBuildGuide.md](V6ClangBuildGuide.md) for build setup and custom link flows.
- [V6ClangUsage.md](V6ClangUsage.md) for the Clang driver and V6CLANG C support.
- [V6ClangDebugABI.md](V6ClangDebugABI.md) for the normative ABI and register map.
- [Source Debug Metadata Plan](../design/future_plans/plan_source_debug_metadata.md)
  for the broader artifact and future adapter contract.