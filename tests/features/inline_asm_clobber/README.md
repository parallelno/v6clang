Inline-asm clobber + --gc-sections end-to-end test (Phase 4)
============================================================

Verifies three properties of the V6CLANG asm-interop pipeline:

1. **Inline-asm clobber lists are honored** — `extern_func()` issues
   `__asm__ volatile("CALL func1" : : : "A", "memory")`. The Style-B
   inline asm declares only `A` and `memory` as clobbered, so the
   compiler must NOT save/restore `BC`/`DE` around the asm site. The
   `step4_check_no_overspill` step in `run.py` asserts this on the
   `.s` listing of `main.c`.

2. **Linker GC across asm/C boundaries** — `external.s` defines four
   functions in per-function `.text.<name>` sections:

       _start (crt0) -> main -> [inline asm] CALL func1 -> CALL func2

   `func3` and `func4` are unreferenced in this closure and must be
   dropped by `ld.lld --gc-sections`. The `step3_check_gc` step verifies
   absence via `llvm-nm`.

3. **Runtime correctness** — the resulting ROM, executed in v6emul,
   emits exactly `0x31 0x32` (i.e. `"12"`) on the TEST_OUT debug port,
   confirming neither `func3` (`'3'`) nor `func4` (`'4'`) executed.

## Run

    python tests/features/inline_asm_clobber/run.py

Prints `OK: ...` on success.

## Files

- `main.c`        — calls `extern_func()` then `__builtin_v6clang_hlt()`.
- `external.h`    — `static inline __asm__ volatile("CALL func1" ... "A","memory")`.
- `external.s`    — bodies of `func1`..`func4` in per-function sections.
- `expected.txt`  — `12` (the expected stdout).
- `run.py`        — orchestrates assemble crt0 -> compile -> link -> emulate -> nm -> filecheck.
