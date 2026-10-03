# V6C — LLVM Backend for Vector 06c

An LLVM compiler backend and Clang frontend targeting the **Vector 06c** home computer (Intel 8080 / KR580VM80A CPU, 3 MHz, 64 KB RAM).

**Full pipeline**: C source → Clang → LLVM IR → V6C backend → flat binary → Vector 06c

## Quick Start

### Prerequisites

- CMake ≥ 3.20, MSVC 2022+ (or GCC 11+ / Clang 14+)
- [uv](https://docs.astral.sh/uv/) to bootstrap the local `.venv`
    (Ninja and Python are installed into `.venv`; the system Python is not used)
- [v6asm](https://github.com/parallelno/v6asm) installed separately (needed for assembly-reference tests)
- [v6emul](https://github.com/parallelno/v6emul) installed separately (needed for execution tests)
- [c8080](https://github.com/Aleksey-F-Morozov/c8080) installed separately (needed for benchmarks)
- [z88dk](https://github.com/z88dk/z88dk) installed separately (optional benchmark comparator)

### Using the Packaged Release

```powershell
# Build the bundled hello-world sample from the release root
.\bin\clang.exe -target i8080-unknown-v6c -O2 .\samples\01_hello\main.c -o hello.rom

# Run it in your configured emulator
& $env:V6EMUL --rom hello.rom --load-addr 0x0100 --halt-exit --dump-cpu
```

### Build from Source

On Windows, the recommended build entry point is:

```powershell
$env:V6ASM = 'C:\Tools\v6asm\v6asm.exe'
$env:V6EMUL = 'C:\Tools\v6emul\v6emul.exe'
$env:C8080 = 'C:\Tools\c8080\c8080.exe'
$env:Z88DK = 'C:\Tools\z88dk'
pwsh scripts\build.ps1
```

`V6ASM`, `V6EMUL`, and `C8080` must point to their separately installed
executables. `Z88DK` is an optional installation root for the benchmark
comparator. These tools are not required to compile or link C programs with
the LLVM toolchain. Pass `-V6AsmPath <path>` or `-V6EmulPath <path>` to
`build.ps1` for one-off overrides.

For a faster build-only iteration loop:

```powershell
pwsh scripts\build.ps1 -SkipTests
```

For manual and non-Windows setup details, see `docs/V6CBuildGuide.md` in the
repository or `docs/V6CBuildGuide.md`.

### Compile a C Program from a Source Checkout

```powershell
# C → assembly
.\llvm-build\bin\clang.exe -target i8080-unknown-v6c -S hello.c -o hello.s

# C → flat binary (ROM) — clang drives ld.lld + llvm-objcopy automatically
.\llvm-build\bin\clang.exe -target i8080-unknown-v6c -O2 hello.c -o hello.rom

# Run in emulator
& $env:V6EMUL --rom hello.rom --load-addr 0x0100 --halt-exit --dump-cpu
```

### Run Tests

```powershell
python tests\run_all.py                 # Full suite (golden + lit + benchmarks)
python tests\run_all.py --no-benchmarks # Faster dev loop
python tests\run_golden_tests.py        # Emulator trust baseline (16 tests)
```

## Supported C Subset

- **Types**: `char` (unsigned, 1B), `short` / `int` (2B), `long` (4B), pointers (2B)
- **Operations**: All integer arithmetic, bitwise, shifts, comparisons, control flow
- **Functions**: Full calling convention with register + stack argument passing
- **Globals**: Initialized and uninitialized data, `const` → `.rodata`
- **Multi-file**: Cross-file linking via native `ld.lld` (driven by clang)
- **Intrinsics**: `__builtin_v6c_in`, `__builtin_v6c_out`, `__builtin_v6c_di`, `__builtin_v6c_ei`, `__builtin_v6c_hlt`, `__builtin_v6c_nop`
- **Inline assembly**: `asm volatile("NOP")` (IR-level constraints)

### Limitations

- No standard C library (freestanding only)
- `long long` / `float` / `double` compile but are very expensive (warning emitted)
- No hardware floating-point
- Maximum binary size: 64 KB

## Project Structure

| Path | Description |
|------|-------------|
| `llvm-project/` | LLVM monorepo (pinned `llvmorg-18.1.0`, gitignored) |
| `llvm/` | Git-tracked mirror of V6C backend + modified upstream files |
| `clang/` | Git-tracked mirror of Clang V6C integration |
| `compiler-rt/` | Runtime library, headers, and crt0 |
| `scripts/` | Build, release, mirror sync, linker, and ELF→binary tooling |
| `samples/` | Sample programs and demo projects |
| `V6ASM` | Separately installed reference 8080 assembler used by tests |
| `V6EMUL` | Separately installed Vector 06c emulator used by tests and samples |
| `C8080` | Separately installed reference C compiler used by benchmarks |
| `Z88DK` | Optional z88dk installation root used by benchmarks |
| `tests/` | Golden, lit (mirror), integration, runtime, and benchmark tests |
| `docs/` | [Documentation index](docs/README.md) |
| `design/` | [Architecture design](design/design.md) and [implementation plan](design/plan.md) |

## Documentation

Repository documentation lives under [docs/README.md](docs/README.md).

Key entry points:

- [Build Guide](docs/V6CBuildGuide.md) — detailed build instructions, mirror sync, binary emission
- [Architecture](docs/V6CArchitecture.md) — CPU, data layout, memory map, runtime library
- [Calling Convention](docs/V6CCallingConvention.md) — register/stack argument passing, frame layout
- [Optimization Passes](docs/V6COptimization.md) — 8 custom passes with toggle flags
- [Instruction Timings](docs/V6CInstructionTimings.md) — cycle costs for all 8080 instructions
- [Benchmarks](docs/benchmarks.md) — head-to-head vs c8080 and z88dk on shared C programs

## Samples

Sample programs live in `samples/`.

- `01_hello/` — minimal compile-and-run example
- `02_bsort/` — small benchmark-style C program
- `03_demo/` — larger drawing/demo program with helper headers and build files

## Benchmarks

V6C is benchmarked head-to-head against [c8080](https://github.com/Aleksey-F-Morozov/c8080)
and [z88dk](https://github.com/z88dk/z88dk) (sccz80 backend) on five pure-C
programs (`bsort`, `sieve`, `fib_crc`, `fannkuch`, `lfsr16`).

- Reproduce: `python tests/benchmarks_c/run_benchmarks.py`
- Latest results: [docs/benchmarks.md](docs/benchmarks.md)
- Source + how-to add new compilers/programs: [tests/benchmarks_c/](tests/benchmarks_c/README.md)

## License

See [LICENSE](LICENSE).
