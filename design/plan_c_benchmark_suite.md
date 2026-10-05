# Plan: C Compilers Benchmark Suite for V6CLANG / i8080

Set up a head-to-head cycle-count benchmark of v6clang against three other
i8080-capable C compilers (c8080, z88dk/sccz80, ACK), running each compiled ROM
through `v6emul --halt-exit --dump-cpu` and aggregating results.

## Compiler matrix (decisions locked)

| # | Compiler | Source | i8080 capable? | Acquisition |
|---|---|---|---|---|
| 1 | v6clang | this repo | Yes (baseline 100%) | already built in `llvm-build/` |
| 2 | c8080 | already in `tools/c8080/` | Yes | already present |
| 3 | z88dk (sccz80) | https://github.com/z88dk/z88dk | Yes (`+8080`, `+cpm` targets) | **download nightly Windows zip** from http://nightly.z88dk.org/ → unpack to `tools/z88dk/` |
| 4 | ACK | https://github.com/davidgiven/ack | Yes (`-mcpm`, i80 .COM) | **build from source under MSYS2** (flex+yacc+lua-posix+python+make); install to `tools/ack/` |
| ~~SDCC~~ | dropped | no pure-8080 target (Z80-only emits JR/DJNZ/IX) | — |

## Benchmark programs (3, identical source for all compilers)

All programs are pure ANSI C, no stdlib calls, no float, deterministic inputs
embedded as constants, finite runtime, single `int main(void)`. Each emits a
checksum byte via `OUT 0xED` (port write) before returning, then crt0 issues
`HLT`. Correctness is verified by comparing the OUT byte across compilers; cycle
count is reported by v6emul.

1. **bsort** — bubble sort 16 i8 values, OUT the sum after sort. Stresses
   loops + i8 ALU + array indexing.
2. **sieve** — Sieve of Eratosthenes over 256 bytes (primes 0..255), OUT prime
   count. Stresses pointer arithmetic + bit/byte ops.
3. **fib_crc** — compute first 16 Fibonacci numbers (i16), accumulate CRC-16
   over the byte stream, OUT the low byte of CRC. Stresses i16 add + shift +
   xor.

## Per-compiler crt0 / ROM packaging

Each compiler needs a tiny target-specific startup that:
- starts at 0x100
- calls `main`
- after return, executes `HLT` (0x76) so v6emul prints `cpu_cycles`

| Compiler | Mechanism |
|---|---|
| v6clang | use existing pipeline `clang --target=i8080-unknown-v6clang -O2 prog.c -o prog.rom` (already wraps crt0 + lld + objcopy). Append `_Pragma`-free `__attribute__((noreturn))` exit helper `__halt()` calling `__asm__("HLT")` from main, OR provide a custom crt0 that calls main then HLTs. **Prefer**: small custom crt0 in `tests/benchmarks_c/crt/v6clang_crt.s` invoked via `-nostartfiles`. |
| c8080 | invoke `c8080.exe -a out.asm prog.c`, prepend a small ASM header that does `CALL main` then `OUT 0xED` (optional) then `HLT`, assemble with `v6asm`. Or use c8080's built-in crt mechanism if present (check `tools/c8080/include/`). |
| z88dk | use `+8080 -create-app -startup=0` and supply a custom `crt0` that calls main and HLTs. Output binary is ORG=0x100 raw. Concrete: `zcc +8080 -SO3 -compiler=sccz80 -startup=...` — actual flags TBD during implementation. |
| ACK | `ack -mcpm -O prog.c -o prog.com` → `.COM` file already starts at 0x100. Patch the BDOS-exit hook (RET to address 0x0000) so on return from main, it does HLT instead. Alternative: prepend `JMP 0x0103; HLT` and patch the .COM. |

Verification port: standard `OUT 0xED, A` (already used by v6emul for `TEST_OUT`).

## File layout (final)

```
tests/benchmarks_c/
  README.md                          # rewritten (see Phase 6)
  crt/
    v6clang_crt.s                    # halt after main
    c8080_crt.asm                    # call main; HLT
    z88dk_crt.asm                    # custom z88dk crt; HLT
    ack_crt.asm                      # post-process patch (or wrapper)
  src/
    bsort.c                          # benchmark 1 source (shared, compiler-agnostic)
    sieve.c                          # benchmark 2 source
    fib_crc.c                        # benchmark 3 source
  build/                             # gitignored, generated ROMs
    v6clang_bsort.rom v6clang_sieve.rom v6clang_fib_crc.rom
    c8080_bsort.rom   c8080_sieve.rom   c8080_fib_crc.rom
    z88dk_bsort.rom   z88dk_sieve.rom   z88dk_fib_crc.rom
    ack_bsort.rom     ack_sieve.rom     ack_fib_crc.rom
  run_benchmarks.py                  # builds + runs + aggregates results

tools/z88dk/                         # downloaded nightly
tools/ack/                           # built from source

docs/benchmarks.md                   # results table (cross-posted)
```

The existing `tests/benchmarks_c/v6clang_bsort.c` (1-line stub) is **moved** to
`tests/benchmarks_c/src/bsort.c` and fleshed out as a real benchmark.

---

## Phases

### Phase 1 — Compiler acquisition (parallelizable, except ACK is heavy)

1. **z88dk (easy)**: download `https://nightly.z88dk.org/` Win32 zip, extract to
   `tools/z88dk/`, smoke test `tools/z88dk/bin/zcc.exe --version`.
2. **ACK (heavy)**: under MSYS2 (separate manual prerequisite the user must
   install), `git clone --depth 1 davidgiven/ack tools/ack-src/`, edit Makefile
   `PREFIX=...tools/ack/` and `PLATS=cpm`, run `make && make install`. If MSYS2
   is unavailable, **fall back** to checking GitHub release `dev` tag for any
   prebuilt Windows artifact and using that. If both fail: document blocker in
   README and exclude ACK from the table.
3. **c8080**: already present, no action.
4. **v6clang**: already built (verify `llvm-build/bin/clang --target=i8080-unknown-v6clang -v` works).

*Risk*: ACK build on Windows is fragile. If it fails after 2 attempts, mark ACK
as "TBD" and proceed with 3 compilers.

### Phase 2 — Per-compiler crt0 + ROM build script

5. Author `crt/v6clang_crt.s` (tiny: `JMP main` at 0x100, post-main HLT — but
   v6clang already provides a default crt0 in `compiler-rt/lib/builtins/v6clang/`
   per repo memory; **first inspect** to see if HLT-on-return is already done
   or if it loops forever). Adjust as needed.
6. Author `crt/c8080_crt.asm` — assembled by `v6asm`, linked before c8080 output.
7. Author `crt/z88dk_crt.asm` — z88dk `+8080` custom crt with a HLT in `__Exit`.
8. Author `crt/ack_crt.asm` (or a Python post-processor) for ACK's `.COM`
   output.
9. Author `tests/benchmarks_c/run_benchmarks.py` driving the matrix:
   - For each (compiler, program) → invoke compiler → produce `build/<comp>_<prog>.rom`
   - Run `tools/v6emul/v6emul.exe --rom <rom> --load-addr 0x0100 --halt-exit --dump-cpu`
   - Parse `HALT at PC=... after N cpu_cycles` and `TEST_OUT port=0xED value=0xNN`
   - Validate all compilers produced same checksum per program
   - Print + write a markdown results table

### Phase 3 — Benchmark sources

10. Author `src/bsort.c` (replace 1-line stub).
11. Author `src/sieve.c`.
12. Author `src/fib_crc.c`.

All three: pure C, no `<stdio.h>`, only the implicit `out(0xED, x)` mechanism
(per-compiler small inline-asm or `__builtin` wrapper supplied via `bench.h`).

### Phase 4 — Run + aggregate (depends on 1-3)

13. Run `python tests/benchmarks_c/run_benchmarks.py`.
14. Verify all 12 ROMs produce the **same** OUT byte per program (correctness
    cross-check across compilers).
15. Generated `docs/benchmarks.md` contains:
    - Matrix table: rows=programs, cols=compilers, cells=`cycles (ratio vs v6clang)`
    - ROM size table
    - Compiler version + flags footnote

### Phase 5 — Documentation

16. Rewrite `tests/benchmarks_c/README.md` with: prerequisites, how to acquire
    each compiler (esp. ACK MSYS2 instructions), build commands, how to add a
    new compiler, how to add a new program, output format.
17. Cross-post a summary table into root `README.md` (a new section "Benchmarks").
18. Add a link to `docs/benchmarks.md` in `docs/README.md`.

---

## Steps & dependencies

| # | Step | Deps | Phase |
|---|---|---|---|
| 1 | Download z88dk nightly | — | 1 |
| 2 | Build ACK (or fallback) | — *(parallel w/ 1)* | 1 |
| 3 | Verify c8080 + v6clang | — *(parallel)* | 1 |
| 4 | Inspect v6clang default crt0; design HLT exit | 3 | 2 |
| 5 | Write 4 crt0 files | 1, 2, 4 | 2 |
| 6 | Author bench.h (per-compiler `out_port` macro) | 4 | 2 |
| 7 | Author 3 benchmark .c files | 6 | 3 |
| 8 | Author run_benchmarks.py | 5 | 2 |
| 9 | Run matrix; validate checksums match | 7, 8 | 4 |
| 10 | Generate `docs/benchmarks.md` | 9 | 4 |
| 11 | Rewrite tests/benchmarks_c/README.md | 9 | 5 |
| 12 | Update root README + docs/README.md | 10 | 5 |

Steps 1, 2, 3 run in parallel. Steps 5, 6 in parallel. Step 7 is parallel
across the 3 programs. Steps 8 onward are sequential.

---

## Relevant files

- [tests/benchmarks_c/README.md](tests/benchmarks_c/README.md) — current
  scaffold; rewrite in step 11
- [tests/benchmarks_c/v6clang_bsort.c](tests/benchmarks_c/v6clang_bsort.c) —
  1-line stub; move/rename to `src/bsort.c` and flesh out
- [tools/c8080/c8080.exe](tools/c8080/c8080.exe) — already present compiler
- [tools/v6emul/v6emul.exe](tools/v6emul/v6emul.exe) — emulator, prints
  `HALT at PC=... after N cpu_cycles` and `TEST_OUT port=0xED value=0xNN`
- [tools/v6asm/v6asm.exe](tools/v6asm/v6asm.exe) — assembler for our crt0 files
- `compiler-rt/lib/builtins/v6clang/crt0.s` — existing v6clang crt0 (inspect for
  HLT semantics in step 4)
- [docs/README.md](docs/README.md) — index, add link to benchmarks.md
- [README.md](README.md) — root, add a Benchmarks section

---

## Verification

1. After Phase 1: `tools/z88dk/bin/zcc.exe --version` works; `tools/ack/bin/ack -V` works (or ACK skipped); `tools/c8080/c8080.exe -h` works.
2. After Phase 2: each crt0 individually assembles + links; trivial "out 0x42, HLT" hello produces correct emulator output for **each** compiler.
3. After Phase 3: each .c file compiles cleanly with **all** 4 compilers (or 3 if ACK skipped), producing a ROM ≤ ~2KB.
4. After Phase 4: 12 (or 9) ROMs run to HALT in finite cycles, all compilers produce the **same** OUT byte per program (correctness invariant). If any disagree, the program has UB/portability issue → fix before recording results.
5. After Phase 5: results table in `docs/benchmarks.md` shows v6clang as 100% baseline and others as ratios; root README links it.

---

## Decisions

- **SDCC dropped** — no pure-8080 target; replaced by c8080 (already in repo).
- **ACK** — try MSYS2 source build; fall back to skipping if blocker; do not
  block the rest of the suite on it.
- **Programs**: bsort + sieve + fib_crc.
- **Harness**: per-compiler crt0 ends in HLT; correctness checked via shared
  `OUT 0xED, checksum` byte; cycles read from `--dump-cpu` output.
- **Excluded scope**: floating point benchmarks (i8080 has no FPU and float
  emulation is huge); large stdlib (no printf, no malloc).

## Further considerations

1. **ACK build feasibility on Windows** — high risk. Recommendation: time-box to
   one MSYS2 attempt; if it fails, document the prereq steps in README and ship
   the suite with 3 compilers (v6clang + c8080 + z88dk).
2. **z88dk default optimization level** — sccz80 vs zsdcc backend choice
   matters. Recommendation: use `sccz80` (the native 8080-aware backend) at
   `-SO3` and document; optionally also benchmark `-O2`.
3. **Compiler version pinning** — record exact versions in the results table
   footnote (z88dk nightly date, ACK commit, c8080 build date, llvm-build hash).
