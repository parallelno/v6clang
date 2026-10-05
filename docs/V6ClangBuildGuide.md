# V6CLANG Build Guide

Build and tooling pipeline for the V6CLANG LLVM backend: prerequisites,
configuration, mirror sync workflow, running tests, invoking `llc`, and
producing flat-binary ROMs.

For C-language and inline-asm reference, see
[V6ClangUsage.md](V6ClangUsage.md). For backend tuning and debugging
flags, see [V6ClangCompilerOptions.md](V6ClangCompilerOptions.md). For release
cutting, see [V6ClangRelease.md](V6ClangRelease.md).

## Prerequisites

- CMake ≥ 3.20
- C++17 compiler (GCC 11+, Clang 14+, or MSVC 2022+)
- [uv](https://docs.astral.sh/uv/) — used only once to
    bootstrap the project-local `.venv`. Ninja and Python themselves are
    installed **into** `.venv`; the system Python is never used.
- [v6asm](https://github.com/parallelno/v6asm) installed separately (for
    assembly-reference tests)
- [v6emul](https://github.com/parallelno/v6emul) installed separately (for
    execution tests)
- [c8080](https://github.com/Aleksey-F-Morozov/c8080) installed separately
    (for benchmarks)
- [z88dk](https://github.com/z88dk/z88dk) installed separately (optional
    benchmark comparator)

## Tool Dependencies

| Tool | Location | Purpose |
|------|----------|---------|
| LLVM | `llvm-project/` (pinned `llvmorg-18.1.0`) | Compiler infrastructure (gitignored, build source) |
| v6asm | `$env:V6ASM` | Separately installed CLI 8080 assembler — reference assembly, ASM→ROM conversion |
| v6emul | `$env:V6EMUL` | Separately installed CLI Vector 06c emulator — execution, register/memory inspection, cycle counting |
| c8080 | `$env:C8080` | Separately installed reference C compiler used by benchmarks |
| z88dk | `$env:Z88DK` | Optional separately installed z88dk root used by benchmarks |

Set the environment variables before running the full test suite:

```powershell
$env:V6ASM = 'C:\Tools\v6asm\v6asm.exe'
$env:V6EMUL = 'C:\Tools\v6emul\v6emul.exe'
$env:C8080 = 'C:\Tools\c8080\c8080.exe'
$env:Z88DK = 'C:\Tools\z88dk'
```

`V6ASM`, `V6EMUL`, and `C8080` are executable paths. `Z88DK` is the z88dk
installation root, containing `bin\zcc.exe` and `lib\config`; it is optional,
and its benchmark submatrix is skipped if unset. The C compiler, linker, and
packaged V6CLANG release do not include or require these reference tools. Test
scripts accept `--v6asm <path>` and `--v6emul <path>` one-off overrides, while
`scripts\build.ps1` accepts `-V6AsmPath <path>` and `-V6EmulPath <path>`.

## Python Environment (.venv)

V6CLANG builds must not depend on a system-wide Python installation: system
interpreters can be upgraded, relocated, or removed, which leaves CMake
pointing at a stale `ninja.exe` path and breaks `cmake -G Ninja`. Instead, all
build and release scripts use a pinned, project-local environment under
`.venv/`.

`scripts/build.ps1` and `scripts/publish.ps1` provision it automatically by
calling:

```powershell
pwsh scripts\setup_venv.ps1
```

`setup_venv.ps1` is idempotent and offline-friendly. It creates `.venv/` with
`uv` when available (falling back to `python -m venv`) and installs the build
tooling into it:

| Package | Purpose |
|---------|---------|
| `ninja` | Build executor used by CMake's `-G Ninja` generator |
| `pyyaml` | LLVM CMake feature detection and lit/test tooling |
| `pygments` | lit/LLVM diagnostic reporting |

The scripts then use `.venv\Scripts\ninja.exe` and
`.venv\Scripts\python.exe` exclusively, and pass `-DCMAKE_MAKE_PROGRAM` /
`-DPython3_EXECUTABLE` to CMake so a previously cached system path is
overridden. `.venv/` is gitignored; recreate it at any time with
`pwsh scripts\setup_venv.ps1 -Force`.

## Build LLVM with V6CLANG Target

`scripts/build.ps1` is the recommended way to do a full build. It activates the
MSVC toolchain environment on Windows, configures cmake on first run, syncs the
mirror, builds all required binaries with ninja, assembles `crt0.o`, runs all
test suites:

```powershell
$env:V6ASM = 'C:\Tools\v6asm\v6asm.exe'
$env:V6EMUL = 'C:\Tools\v6emul\v6emul.exe'
$env:C8080 = 'C:\Tools\c8080\c8080.exe'
pwsh scripts\build.ps1

# Build only, skip tests
pwsh scripts\build.ps1 -SkipTests

# Full release: package + tag + push
pwsh scripts\publish.ps1
```

## Build the V6CLANG Runtime (crt0.o)

`crt0.o` is assembled automatically by `build.ps1`
after every ninja run. For a manual build:

```powershell
pwsh scripts\build_v6clang_runtime.ps1
```

Assembles `compiler-rt\lib\builtins\v6clang\crt0.s` → `crt0.o` next to its
source; skips if already up to date. `make_dist.ps1` copies the prebuilt
object into the staged install tree.

## Syncing the Mirror

`llvm-project/` is a large cloned repo (pinned to `llvmorg-18.1.0`) and is **gitignored**.
All V6CLANG source code and tests are git-tracked under `llvm/`, `clang/`, and `tests/lit/`, which serve as mirrors.

`build.ps1` calls `sync_llvm_mirror.ps1` automatically at the start of every
build. Run it manually only when you edit files inside `llvm-project/` directly
outside a normal build:

```powershell
pwsh scripts\sync_llvm_mirror.ps1
```

The script handles three categories:

1. **V6CLANG target directory** (`llvm-project/llvm/lib/Target/V6Clang/` → `llvm/lib/Target/V6Clang/`) — full directory mirror via `robocopy /MIR`.
2. **Lit tests** (`llvm-project/{llvm,clang}/test/.../V6Clang/` → `tests/lit/`) — full directory mirror excluding `Output/`.
3. **Modified upstream LLVM files** (e.g. `Triple.h`, `Triple.cpp`) — individual file copies via `xcopy`.

> **Warning — `tests/lit/` is a read-only mirror.**
> `robocopy /MIR` overwrites the entire destination tree on every sync. Any file written directly to `tests/lit/` that does not exist in `llvm-project/` will be deleted on the next build. Always author new files in `llvm-project/` first.

When a new milestone modifies additional upstream files, add `xcopy` lines to `scripts\sync_llvm_mirror.ps1`.

## Populating llvm-project/ (New Contributors)

After cloning the repo and the LLVM monorepo, run the populate script to copy all V6CLANG code and tests into `llvm-project/`:

```powershell
git clone --depth 1 --branch llvmorg-18.1.0 https://github.com/llvm/llvm-project.git llvm-project
pwsh scripts\populate_llvm_project.ps1
```

This is the reverse of `sync_llvm_mirror.ps1` — it copies from git-tracked mirrors into `llvm-project/` so it's ready to build.

## Running Tests

```bash
# Full suite (golden + lit)
python tests/run_all.py

# Golden test suite (emulator trust baseline)
python tests/run_golden_tests.py

# With verbose output
python tests/run_golden_tests.py -v
```

### Authoring Lit Tests

`tests/lit/` is a **read-only mirror** — it is completely overwritten by `sync_llvm_mirror.ps1` on every build. Always create new lit tests in `llvm-project/` (the source of truth):

| Test category | Source of truth (write here) | Mirror (do not write here) |
|---|---|---|
| CodeGen | `llvm-project/llvm/test/CodeGen/V6Clang/` | `tests/lit/CodeGen/V6Clang/` |
| MC | `llvm-project/llvm/test/MC/V6Clang/` | `tests/lit/MC/V6Clang/` |
| Linker | `llvm-project/llvm/test/Linker/V6Clang/` | `tests/lit/Linker/V6Clang/` |
| Clang CodeGen | `llvm-project/clang/test/CodeGen/V6Clang/` | `tests/lit/Clang/V6Clang/` |

After adding a test in `llvm-project/`, the mirror updates automatically on the next `build.ps1` run. To sync immediately without a full build:

```powershell
pwsh scripts\sync_llvm_mirror.ps1
```

## Using llc for Assembly Output

Once built, `llc` can compile LLVM IR to 8080 assembly:

```bash
# Emit assembly to stdout
llvm-build/bin/llc -march=v6clang -o - input.ll

# Emit assembly to file
llvm-build/bin/llc -march=v6clang -o output.s input.ll
```

Example trivial IR (`trivial.ll`):
```llvm
target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

define void @empty() {
  ret void
}
```

Running `llc -march=v6clang -o - trivial.ll` produces:
```asm
        .text
        .globl  empty
empty:
        RET
```

## Binary Emission

The clang driver runs `ld.lld` and `llvm-objcopy` automatically. The
output extension determines the format: `.elf` keeps the linked ELF;
anything else (e.g. `.rom`, `.bin`) is converted to a flat binary via
`llvm-objcopy -O binary`.

```bash
# C source -> flat binary ROM (single command)
llvm-build/bin/clang -target i8080-unknown-v6clang -O2 input.c -o output.rom

# C source -> ELF (no objcopy step)
llvm-build/bin/clang -target i8080-unknown-v6clang -O2 input.c -o output.elf
```

### Debug ROM Companions

Pass `-g` when producing a flat ROM to retain a sibling ELF with the final
symbols and DWARF v5 metadata. The ROM is still derived from that
same final ELF, so its runtime addresses and debug addresses agree.

```bash
llvm-build/bin/clang -target i8080-unknown-v6clang -g \
    input.c -o output.rom
# Produces output.rom and output.elf.
```

Use `output.elf` for source-to-address lookup and `output.rom` for the
emulator. Non-debug flat-ROM builds retain the existing temporary-ELF flow and
do not leave a companion artifact.

For lower-level control (e.g. linking multiple objects with a custom
linker script):

```bash
# Step 1: Compile each translation unit to ELF object
llvm-build/bin/clang -target i8080-unknown-v6clang -O2 -c a.c -o a.o
llvm-build/bin/clang -target i8080-unknown-v6clang -O2 -c b.c -o b.o

# Step 2: Link with ld.lld using the V6CLANG linker script
llvm-build/bin/ld.lld -m elf32v6clang \
    -T clang/lib/Driver/ToolChains/V6Clang/v6clang.ld \
    a.o b.o -o out.elf

# Step 3: Convert to flat binary
llvm-build/bin/llvm-objcopy -O binary out.elf out.rom
```

### Linker Maps

Pass `-Wl,-Map,<path>` to clang to write LLD's final layout map. It reports
the output sections, their VMA/LMA addresses and sizes, contributing input
sections, and section-relative symbols:

```bash
llvm-build/bin/clang -target i8080-unknown-v6clang -nostdlib -O2 \
    main.o engine.o \
    -Wl,-Map,build/program.map \
    -o build/program.rom
```

Use this map to inspect ROM and RAM layout. It does not list global absolute
constants because they do not occupy a section. To write their final values,
add the V6CLANG LLD option `--v6clang-constants-map=<path>`:

```bash
llvm-build/bin/clang -target i8080-unknown-v6clang -nostdlib -O2 \
    main.o engine.o \
    -Wl,-Map,build/program.map \
    -Wl,--v6clang-constants-map,build/program.constants.map \
    -o build/program.rom
```

The constants map is generated by LLD after final symbol resolution. It lists
global `SHN_ABS` symbols from every linked object in name order, including
assembler exports such as `CONTROL_CODE_NO`:

```text
# V6CLANG final global absolute constants
# Value     Symbol
00000000 CONTROL_CODE_NO
00000001 CONTROL_CODE_RIGHT
```

It excludes section-relative labels such as functions and data addresses. A
flat `.rom` is raw binary, so this report must be requested during linking;
the constants cannot be recovered from the ROM afterward.

### Packed BSS Sections

V6CLANG `ld.lld` recognizes three exact input section names for compact runtime
storage. Emit every logical block as an independent writable, allocatable
`SHT_NOBITS` section with alignment 1. LLVM MC can create repeated exact-name
sections with `unique`:

```asm
.section .bss.pack.window,"aw",@nobits,unique,1
window_block:
    .zero 64
```

Use `.bss.pack.align` for blocks that must start on a 256-byte boundary,
`.bss.pack.window` for blocks of at most 256 bytes that must not cross a page,
and `.bss.pack` for unrestricted filler blocks. The default `v6clang.ld` collects
all three and places the arena within the crt0 BSS zeroing range.

A custom linker script must preserve the output section name and collection
order so the specialized allocator is selected:

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

Link with `--gc-sections` to discard each unreferenced packed block. Packed
sections reserve runtime addresses but, as `SHT_NOBITS`, do not add bytes to
the ROM or COM image.

### Start Address

The default load address is `0x0100`, set by the `v6clang.ld` linker script
(`. = 0x0100;` at the start of `.text`). To override, either:

1. **Pass a custom linker script** via `-Wl,-T,my-script.ld` to clang, or
2. **Use `-Wl,-Ttext=0xNNNN`** to override the text base while keeping
   the rest of the layout. Example:
   ```bash
   llvm-build/bin/clang -target i8080-unknown-v6clang -O2 \
       -Wl,-Ttext=0x8000 input.c -o output.rom
   ```

Note: when relocating to a non-default base, the V6CLANG runtime
(`__stack_top = 0x0000`) and crt0 entry stay the same; only the code/data
addresses change. The legal range is `0x0000`–`0xFFFF`.

To also move the initial stack pointer, add `--defsym`:
```bash
llvm-build/bin/clang -target i8080-unknown-v6clang -O2 \
    -Wl,-Ttext=0x8000 -Wl,--defsym=__stack_top=0xBFFF input.c -o output.rom
```
`--defsym=__stack_top=ADDR` overrides the linker-script default (`0x0000`).
`crt0` will execute `LXI SP, ADDR` as its very first instruction.

To use a function other than `main` as the C entry point, add `--defsym=__entry`:
```bash
llvm-build/bin/clang -target i8080-unknown-v6clang -O2 \
    -Wl,--defsym=__entry=myStart input.c -o output.rom
```
`--defsym=__entry=NAME` overrides the `PROVIDE(__entry = main)` default in
`v6clang.ld`. No driver change is needed — `--defsym` is already forwarded.

### Intel HEX Format

Standalone conversion from flat binary to Intel HEX:
```bash
python scripts/bin2hex.py output.bin -o output.hex --base 0x0100
```

### Running in the Emulator

```bash
& $env:V6EMUL --rom output.bin --load-addr 0x0100 --halt-exit --dump-cpu
```

## Further Reading

| Topic | Document |
|-------|----------|
| C language model, builtins, attributes, inline asm | [V6ClangUsage.md](V6ClangUsage.md) |
| Backend tuning and debugging flags | [V6ClangCompilerOptions.md](V6ClangCompilerOptions.md) |
| Math runtime (`v6clang_arith.h`) and asm interop contract | [V6ClangRuntimeAndInlineAsm.md](V6ClangRuntimeAndInlineAsm.md) |
| Optimization passes and design notes | [V6ClangOptimization.md](V6ClangOptimization.md) |
| Cutting a tagged release | [V6ClangRelease.md](V6ClangRelease.md) |
