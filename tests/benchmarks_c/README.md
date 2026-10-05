# V6CLANG C-compiler benchmarks

Head-to-head cycle-count comparison of **v6clang** (this repo) against other
i8080-capable C compilers, run on the cycle-accurate `v6emul` emulator.

See [docs/benchmarks.md](../../docs/benchmarks.md) for the latest results.

## Compilers covered

| Compiler | Source | Acquisition |
|---|---|---|
| v6clang  | this repo | already built; uses `dist/v6clang-2026.04.27-windows-x64/bin/clang.exe` |
| c8080    | https://github.com/Aleksey-F-Morozov/c8080 | separately installed executable configured by `C8080` |
| z88dk    | https://github.com/z88dk/z88dk             | optional installation root configured by `Z88DK`; skipped if unavailable |
| ACK      | https://github.com/davidgiven/ack          | not yet integrated (Windows build is non-trivial) |

SDCC is intentionally not benchmarked: it has no pure-8080 target — its
`-mz80` output uses `JR` / `DJNZ` / `IX` instructions that the i8080 cannot
execute.

## Benchmark programs

All three are pure ANSI C, no stdlib calls, deterministic inputs, finite
runtime, and end with `bench_finish(checksum)` which writes a single byte to
port 0xED then HLTs.

| Program | Source | What it stresses |
|---|---|---|
| `bsort`    | [src/bsort.c](src/bsort.c)       | bubble-sort 255 i8 values + sum reduction (loops, i8 ALU, indexing) |
| `sieve`    | [src/sieve.c](src/sieve.c)       | Sieve of Eratosthenes over [0..7999] (pointer arithmetic, byte memory; port of z88dk benchmark) |
| `fib_crc`  | [src/fib_crc.c](src/fib_crc.c)   | 24 Fibonacci steps + CRC-16 over the byte stream (i16 add / shift / xor) |
| `fannkuch` | [src/fannkuch.c](src/fannkuch.c) | classic Anderson/Rettig pancake-flip benchmark, N=7 (port of z88dk benchmark; nested loops, byte arrays, in-place reverse) |
| `lfsr16`   | [src/lfsr16.c](src/lfsr16.c)     | 16-bit Galois LFSR (poly 0xB400) for 4096 iterations (i16 shift + conditional i16 xor with 16-bit constant) |

Correctness invariant: every compiler must produce the same checksum byte for
each program (`bsort`=0x98, `sieve`=0xEC, `fib_crc`=0x2B, `fannkuch`=0x10,
`lfsr16`=0x1D). The runner aborts with a non-zero exit code on mismatch.

## Per-compiler glue

[src/bench.h](src/bench.h) selects a `bench_finish()` definition based on the
active compiler:

* `__V6CLANG__` — uses `__builtin_v6clang_out(0xED, ...)` + `__builtin_v6clang_hlt()`.
* `__C8080_COMPILER` — `__global` function, `out (0xED), a; halt` in inline asm.
* `__SCCZ80` / `__Z88DK` — pops the stack-passed argument and emits `OUT` + `HLT` via `#asm`.

ROM packaging:

* **v6clang** emits a flat ROM that loads at 0x0100 directly; `crt0.s` from
  compiler-rt zeroes BSS, sets SP, calls `main`, and HLTs on return.
* **c8080** emits a CP/M `.COM` (ORG=0x0100). The runner loads it at 0x0100
  directly; the c8080 crt does not use BDOS for our programs.
* **z88dk**'s CP/M crt0 calls BDOS at 0x0005. The runner builds a small
  in-memory image containing a tiny stub (`JMP 0x0100` at 0, `RET` at 0x0005)
  followed by the `.COM` payload at 0x0100, then loads it at 0x0000.

## Running

```powershell
python tests/benchmarks_c/run_benchmarks.py
```

This compiles every (compiler × program) combination, executes each ROM
through `v6emul`, validates checksums, and writes the result table to
[docs/benchmarks.md](../../docs/benchmarks.md).

The driver also emits one assembly listing per (compiler × opt-level) pair
into `tests/benchmarks_c/asm/` for side-by-side analysis:

* `v6clang_<prog>_<O1|O2|Os>.s` — clang `-S` output.
* `c8080_<prog>.asm` — c8080 native listing (`-a`).
* `z88dk_<prog>.asm` — sccz80 output (`-S`).

Prerequisites:

* Python 3.9+
* `dist/v6clang-2026.04.27-windows-x64/bin/clang.exe` exists (build the dist target if needed)
* `C8080` points to the installed `c8080.exe`
* `V6EMUL` points to the installed `v6emul.exe`
* Optional: `Z88DK` points to the installation root containing `bin/zcc.exe` and `lib/config`; if absent, the runner skips only the z88dk submatrix

## Adding a new compiler

1. Install the toolchain separately and configure it through an environment variable.
2. Pick a unique predefined macro (for example `__SDCC` or `__ACK`) and add a
   `bench_finish()` definition to [src/bench.h](src/bench.h) guarded by that
   macro.
3. Add a `build_<name>(prog)` function to
   [run_benchmarks.py](run_benchmarks.py), returning a `Result`, and include
   it in the matrix and the report column list.

## Adding a new program

1. Drop `src/<name>.c` next to the existing benchmarks. It must:
   * be self-contained (no stdlib),
   * end with `bench_finish(checksum)`,
   * pick deterministic inputs and have finite, bounded runtime.
2. Add `<name>` to the `PROGRAMS` list and its expected checksum to `EXPECTED`
   in [run_benchmarks.py](run_benchmarks.py).

## Backend notes (v6clang gotchas observed)

Workarounds applied while authoring the benchmarks. These also live in
`/memories/repo/v6clang-backend.md`:

* `int` loop counters where the loop range fits in 8 bits push the i8080 GPR
  set hard. Prefer `u8` indices.
* Helper functions that LLVM might inline back together can blow regalloc;
  `__attribute__((noinline))` (guarded by
  `defined(__V6CLANG__) || __GNUC__ || __clang__`) keeps live ranges short.
* Computing `j + p` and storing back as `u8` may trigger an `__mulhi3`
  reference in the current toolchain — use a `u16` loop variable instead.
* Heavy constant folding at -O2 can collapse a whole benchmark to a single
  `OUT`. Add a `volatile` seed at the top of `main` to defeat it.
