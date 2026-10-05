# Plan: O-LLD — Native ld.lld Linker for V6CLANG

Replace the Python `scripts/v6clang_link.py` with a real LLVM linker
(`ld.lld`) plus a V6CLANG linker script and a canonical `crt0.s`. Have
the clang driver invoke `ld.lld` and `llvm-objcopy` end-to-end so
that `clang -target i8080-unknown-v6clang app.c -o app.rom` produces a
correct, runnable Vector-06c ROM whose entry point is `_start`
(which calls `main`).

## Scope

**In scope**
- Add `lld` to `LLVM_ENABLE_PROJECTS` and build `ld.lld`.
- Implement a minimal V6CLANG ELF backend for lld at
  `llvm-project/lld/ELF/Arch/V6Clang.cpp` (handles R_V6CLANG_8 / _16 / _LO8 /
  _HI8, all absolute).
- Register the V6CLANG `e_machine` value in lld and confirm the same
  value is used by `V6ClangELFObjectWriter`.
- Provide a default V6CLANG linker script
  (`clang/lib/Driver/ToolChains/V6CLANG/v6clang.ld`) that:
  - sets `ENTRY(_start)`,
  - places sections at `0x0100`,
  - emits `__bss_start`, `__bss_end`, `__stack_top` (= `0x0000`,
    so the first PUSH wraps SP to `0xFFFE`),
  - orders crt0 before user `.text`.
- Make `compiler-rt/lib/builtins/v6clang/crt0.s` the canonical crt0;
  delete `lib/v6clang/crt0.s`.
- Update the clang V6CLANG driver (`clang/lib/Driver/ToolChains/V6Clang.cpp`)
  to: assemble → link with `ld.lld -T v6clang.ld` → `llvm-objcopy -O
  binary` to a `.rom`.
- Update `scripts/sync_llvm_mirror.ps1` to mirror the new
  `lld/ELF/Arch/V6Clang.cpp` (and any registry edits).
- Replace `scripts/v6clang_link.py` callers; mark the script deprecated
  with a stub that errors and points at `clang -fuse-ld=lld`.
- Add a feature/lit test that exercises the end-to-end flow on
  `tests/features/o_lld_bsort.c` (statically-initialized `ARR`,
  emits the sorted sequence on port `0xED`).
- Update build guide and architecture docs.

**Out of scope**
- Linker GC sections, archive (`.a`) creation tooling, LTO.
- Intel HEX output via objcopy (it works, but not part of the
  default driver flow).
- Any codegen changes; relocation set is unchanged.
- Multi-bank / overlay layouts.

## Phases

### Phase 1 — Build lld and verify generic ELF linking *(no V6CLANG-specific code)*
1. Edit `docs/V6ClangBuildGuide.md` CMake invocation: add `lld` to
   `LLVM_ENABLE_PROJECTS`. Re-run cmake configure + `ninja
   ld.lld lld`. Verify `llvm-build/bin/ld.lld.exe` exists.
2. Sanity-link a trivial X86 ELF with the new `ld.lld` to confirm
   the build is functional.

### Phase 2 — V6CLANG lld backend *(parallel with Phase 3 once Phase 1 is done)*
3. Confirm the V6CLANG `e_machine` value used by
   `llvm/lib/Target/V6CLANG/MCTargetDesc/V6ClangELFObjectWriter.cpp`. If
   it's a private/unassigned ID, document it in
   `docs/V6ClangArchitecture.md` and use the same constant in lld.
4. Create `llvm-project/lld/ELF/Arch/V6Clang.cpp` modelled on
   `llvm-project/lld/ELF/Arch/MSP430.cpp` (closest analogue —
   small target, mostly absolute relocs, no GOT/PLT). Implement:
   - `getRelExpr()` → `R_ABS` for all four V6CLANG relocs.
   - `relocate()` → write 8 / 16 / lo8 / hi8 with overflow
     checks (`checkUInt`/`checkInt` from `lld/ELF/Target.h`).
   - `getTargetSymbol`/`writeGotHeader` — N/A; either omit or
     leave default no-ops.
5. Wire into lld's target dispatch:
   - Add `case EM_V6Clang: return new V6CLANG(...)` in
     `llvm-project/lld/ELF/Target.cpp` (`getTarget()`).
   - Add `lld/ELF/Arch/V6Clang.cpp` to `lld/ELF/CMakeLists.txt`.
6. Update `scripts/sync_llvm_mirror.ps1` to copy the new
   `lld/ELF/Arch/V6Clang.cpp`, the `Target.cpp` patch, and the
   `CMakeLists.txt` patch back to the git-tracked `lld/ELF/`
   mirror (matches upstream lld layout). Remove the empty
   `lld/V6CLANG/` placeholder folder.

### Phase 3 — Linker script + canonical crt0 *(parallel with Phase 2)*
7. Move/rewrite `compiler-rt/lib/builtins/v6clang/crt0.s` to be the
   canonical crt0:
   - Set `SP = __stack_top`.
   - Zero `[__bss_start, __bss_end)`.
   - `CALL main`.
   - `HLT` on return.
   - Export `_start` as the entry symbol.
8. Delete `lib/v6clang/crt0.s` (the 6-line skeleton) so there's only
   one crt0 to maintain.
9. Create `clang/lib/Driver/ToolChains/V6CLANG/v6clang.ld`. The driver
   will reference it via the resource directory, like other
   toolchains do for their default scripts:
   ```
   ENTRY(_start)
   SECTIONS {
     . = 0x0100;
     .text   : { KEEP(*(.text._start)) *(.text*) }
     .rodata : { *(.rodata*) }
     .data   : { *(.data*) }
     . = ALIGN(1);
     __bss_start = .;
     .bss    : { *(.bss* COMMON) }
     __bss_end = .;
     __stack_top = 0x0000;
   }
   ```
   `__stack_top = 0x0000` makes the first PUSH wrap SP to
   `0xFFFE` — the highest legal SP position. crt0 sets
   `SP = __stack_top` before the first PUSH/CALL, so this is
   equivalent to "stack starts at top of RAM".

   Place crt0's `_start` in its own `.text._start` section
   (annotation in `crt0.s`) so the `KEEP` clause guarantees it
   sits at `0x0100`.

### Phase 4 — Driver integration
10. Edit `clang/lib/Driver/ToolChains/V6Clang.cpp` to:
    - Replace the `python scripts/v6clang_link.py` invocation with
      `ld.lld -T <resource-dir>/v6clang.ld -o <tmp>.elf <objs...>
      <resource-dir>/crt0.o
      <resource-dir>/libv6clang-builtins.a`.
      (The resource directory holds the script alongside crt0
      and the builtins archive.)
    - Append `llvm-objcopy -O binary <tmp>.elf <output>` so that
      `-o foo.rom` produces a flat ROM.
    - Honor `-Wl,--defsym=__stack_top=...` so the user can move
      the stack without editing the script.
    - Honor `-T <script>` to override the default linker script.
11. Build crt0 and the V6CLANG builtins into a static archive
    (`libv6clang-builtins.a`) as part of the `compiler-rt/V6CLANG` build,
    so the driver can pass it to `ld.lld` like a normal libgcc.
    *(Depends on whatever build system already produces those
    objects; reuse it.)*

    **Status: superseded by `design/plan_asm_interop_overhaul.md`.**
    Phase 3 of that plan implemented the V6CLANG MC `AsmParser`, so
    `compiler-rt/lib/builtins/v6clang/*.s` (including `crt0.s`) now
    assemble to proper ELF objects via `clang -c file.s -o file.o`.
    Phase 7 of that plan retired `libv6clang-builtins.a` entirely:
    runtime helpers are now exposed as header-only inline-`__asm__`
    wrappers under `<resource-dir>/lib/v6clang/include/` (`<string.h>`,
    `<stdlib.h>`, `<v6clang.h>`), with per-routine `.o` files for
    non-inlinable bodies, pruned by `ld.lld --gc-sections`. The
    driver no longer searches for `libv6clang-builtins.a`; only `crt0.o`
    is picked up under `<resource-dir>/lib/v6clang/` or the compiler-rt
    dev tree. The `--defsym=_start=main` workaround is no longer
    needed.
12. Mirror sync: re-run `scripts/sync_llvm_mirror.ps1` and confirm
    `clang/`, `lld/`, and `compiler-rt/` mirrors are clean.

### Phase 5 — Migration & cleanup
13. Replace the body of `scripts/v6clang_link.py` and `scripts/elf2bin.py`
    with a stub that prints a deprecation message and exits with a
    non-zero code unless `--legacy` is passed.
14. Audit callers: `tests/run_all.py`, `tests/run_golden_tests.py`,
    any feature-test scripts, the build guide. Replace with the
    `clang … -o foo.rom` (or `clang -c` + `ld.lld` + `llvm-objcopy`)
    flow.
15. Wire `tests/features/o_lld_bsort.c` into the new flow:
    `clang -target i8080-unknown-v6clang -O2 tests/features/o_lld_bsort.c
    -o tests/features/o_lld_bsort.rom`. Add a `result.txt` that
    captures the expected port-`0xED` byte stream
    (`01 05 07 0C 10 17 1F 23 2A 37 42 55 63 7E 99 BC`) plus
    `.text`/`.data`/`.bss` sizes for regression tracking.

### Phase 6 — Tests & docs
16. Add `tests/lit/Linker/V6CLANG/basic-link.test`: `clang -c` two
    objects, link with `ld.lld -T v6clang.ld`, FileCheck the entry
    point and a relocation in the resulting ELF.
17. Add a small end-to-end test under `tests/features/`: multi-`.c`
    project (e.g. `main.c` + `helper.c`) → ROM → run in `v6emul`
    → check stdout/MMIO. This locks down that crt0 + script
    actually boot the program at `_start`.
18. Update `docs/V6ClangBuildGuide.md` (toolchain build steps) and
    `docs/V6ClangArchitecture.md` (memory map: confirm `_start` at
    `0x0100`, `__stack_top = 0x0000` rationale).
19. Mark the plan complete in `design/future_plans/README.md`
    (add an `O-LLD` row if not present).

### Checklist

Phase 1 — Build lld
- [x] 1. Add `lld` to `LLVM_ENABLE_PROJECTS`; rebuild
- [x] 2. Sanity-link a trivial X86 ELF with the new `ld.lld`

Phase 2 — V6CLANG lld backend
- [x] 3. Confirm / document `EM_V6Clang` machine ID (= `0x8080`)
- [x] 4. Create `lld/ELF/Arch/V6Clang.cpp` (`getRelExpr`, `relocate`)
- [x] 5. Wire into `lld/ELF/Target.cpp` + `CMakeLists.txt`
- [x] 6. Update `sync_llvm_mirror.ps1`; remove `lld/V6CLANG/` placeholder

Phase 3 — Linker script + canonical crt0
- [x] 7. Promote `compiler-rt/.../crt0.s` (SP, .bss zero, CALL main, HLT)
- [x] 8. Delete `lib/v6clang/crt0.s`
- [x] 9. Create `clang/lib/Driver/ToolChains/V6CLANG/v6clang.ld`

Phase 4 — Driver integration
- [x] 10. `V6Clang.cpp` driver: `ld.lld -T … | llvm-objcopy -O binary`
- [ ] 11. Build `libv6clang-builtins.a` archive *(deferred — needs V6CLANG MC AsmParser; tracked separately)*
- [x] 12. Re-run `sync_llvm_mirror.ps1`; mirrors clean

Phase 5 — Migration & cleanup
- [x] 13. Stub out `v6clang_link.py` and `elf2bin.py`
- [x] 14. Audit and update callers in `tests/`
- [x] 15. Convert `tests/features/43/` to the new flow *(handled via fresh `tests/features/o_lld_bsort.*`; legacy `43/` artifacts left in place as historical reference)*

Phase 6 — Tests & docs
- [x] 16. Add `tests/lit/Linker/V6CLANG/basic-link.test`
- [x] 17. Add multi-`.c` end-to-end feature test *(`tests/features/o_lld_multifile/`)*
- [x] 18. Update `V6ClangBuildGuide.md` and `V6ClangArchitecture.md`
- [x] 19. Mark plan complete in `design/future_plans/README.md`

Verification gates
- [x] V1. `ld.lld --version` runs
- [x] V2. `clang … o_lld_bsort.c -o o_lld_bsort.rom` produces a runnable ROM
- [x] V3. `o_lld_bsort.rom` in `v6emul` emits the expected byte stream on port `0xED`
- [x] V4. `python tests/run_all.py` — full suite passes (golden 15/15 + lit 112/112)
- [x] V5. New lit test passes (`tests/lit/Linker/V6CLANG/basic-link.test`)
- [x] V6. `sync_llvm_mirror.ps1` runs cleanly (extra `.lit_test_times.txt` is the only diff)
- [x] V7. Mirror round-trip rebuilds a byte-identical `o_lld_bsort.rom` (SHA-256 match)

## Status

**Complete.** Step 11 (crt0 ELF + builtins archive) was originally
deferred behind the missing V6CLANG MC AsmParser; resolved by
`design/plan_asm_interop_overhaul.md` Phase 3 (AsmParser landed) and
Phase 7 (libv6clang-builtins.a retired in favor of header-only inline-asm
wrappers). Automatic crt0.o linkage now ships through the standard
clang driver path: `clang -target i8080-unknown-v6clang -O2 file.c -o
file.rom` produces a runnable ROM with no `--defsym=_start=main` /
`-nostartfiles` workarounds. Verified end-to-end by
`scripts/validate_dist.ps1` against the staged release tree
(SP=0xFFFE post-HALT confirms crt0 ran).


## Relevant files

- `docs/V6ClangBuildGuide.md` — CMake invocation change (add `lld`).
- `llvm-project/lld/ELF/Arch/V6Clang.cpp` — **new**, ~80–120 LOC,
  modeled on `llvm-project/lld/ELF/Arch/MSP430.cpp`.
- `llvm-project/lld/ELF/Target.cpp` — add `case EM_V6Clang` in
  `getTarget()`.
- `llvm-project/lld/ELF/CMakeLists.txt` — list `Arch/V6Clang.cpp`.
- `llvm/lib/Target/V6CLANG/MCTargetDesc/V6ClangELFObjectWriter.cpp` —
  reference for the `EM_V6Clang` machine ID and the relocation
  emission rules.
- `llvm/lib/Target/V6CLANG/MCTargetDesc/V6ClangFixupKinds.h` — reference
  for the four fixup → R_V6Clang mappings.
- `compiler-rt/lib/builtins/v6clang/crt0.s` — promote to canonical;
  add `.section .text._start`.
- `lib/v6clang/crt0.s` — **delete**.
- `clang/lib/Driver/ToolChains/V6CLANG/v6clang.ld` — **new**, default
  linker script.
- `lld/V6CLANG/` — **delete** (empty placeholder folder; the V6CLANG
  backend lives at `lld/ELF/Arch/V6Clang.cpp` matching upstream).
- `clang/lib/Driver/ToolChains/V6Clang.cpp` — replace Python linker
  invocation with `ld.lld` + `llvm-objcopy` chain.
- `scripts/sync_llvm_mirror.ps1` — mirror the new lld files.
- `scripts/v6clang_link.py`, `scripts/elf2bin.py` — convert to
  deprecation stubs.
- `tests/run_all.py`, `tests/run_golden_tests.py` — switch to the
  new driver flow.
- `tests/features/o_lld_bsort.c` — **new**, end-to-end test with
  statically-initialized array (already created); add
  `result.txt` documenting expected port-`0xED` output.
- `tests/lit/Linker/V6CLANG/basic-link.test` — **new**.
- `design/future_plans/README.md` — register / mark this plan.

## Verification

1. `ninja -C llvm-build ld.lld lld` succeeds; `llvm-build/bin/ld.lld
   --version` runs.
2. Manual: build `tests/features/o_lld_bsort.c` end-to-end —
   ```
   clang -target i8080-unknown-v6clang -O2 tests\features\o_lld_bsort.c -o tests\features\o_lld_bsort.rom
   ```
   Expect: ROM with `_start` at `0x0100`, byte at `0x0100` matches
   crt0's first opcode, `bsort_for` and `main` at later offsets,
   the 16-byte initialized `ARR` present in `.data`.
3. Run `tests/features/o_lld_bsort.rom` in `tools/v6emul/` and
   confirm the byte stream emitted on port `0xED` is
   `01 05 07 0C 10 17 1F 23 2A 37 42 55 63 7E 99 BC` (the input
   array sorted ascending).
4. `python tests/run_all.py` — all golden + lit + feature tests
   pass under the new linker flow.
5. New lit test `tests/lit/Linker/V6CLANG/basic-link.test` passes
   (links two objects, checks symbols + relocs in output ELF).
6. `scripts/sync_llvm_mirror.ps1` reports no diffs after running
   on a clean tree.
7. Mirror round-trip: clean `llvm-project/`, run the populate
   script, rebuild, re-link `o_lld_bsort.c` — produces a
   byte-identical ROM.

## Decisions

- **Replace `v6clang_link.py`**: ld.lld becomes the sole linker; the
  Python script is converted to a deprecation stub (kept for one
  release for any out-of-tree caller).
- **Final image**: `llvm-objcopy -O binary` produces the ROM. No
  custom Python tooling in the production path.
- **Driver-integrated**: `clang -o foo.rom` runs the full chain
  (compile → assemble → link → objcopy) end-to-end in this plan
  (not deferred to a follow-up).
- **Canonical crt0**: `compiler-rt/lib/builtins/v6clang/crt0.s` (the
  full implementation with `.bss` zeroing). The skeleton at
  `lib/v6clang/crt0.s` is deleted.
- **Linker script lives in
  `clang/lib/Driver/ToolChains/V6CLANG/v6clang.ld`**: shipped alongside
  the driver in the clang resource directory, like other
  toolchains' default scripts; the driver locates it
  programmatically rather than via a hard-coded path.
- **Mirror the upstream lld layout**: V6CLANG backend at
  `lld/ELF/Arch/V6Clang.cpp`; the empty placeholder `lld/V6CLANG/`
  folder is removed. Easier to follow upstream lld conventions
  and to merge upstream lld changes.
- **Same `EM_V6Clang` machine ID** is used in lld and
  `V6ClangELFObjectWriter`; if it's currently a private/unassigned
  value, document it in `docs/V6ClangArchitecture.md` rather than
  changing it.

## Further considerations

1. **`compiler-rt` builtins archive** — does the project already
   produce `libv6clang-builtins.a`, or are the builtin objects
   passed individually today? If individual, add an archive step
   to the compiler-rt build so `ld.lld` can pick what it needs
   instead of always linking everything.
2. **`-Wl,--defsym` vs. config file** — for stack/load-address
   tweaks per project, `--defsym` is enough today; a per-board
   config file (`-target i8080-unknown-v6clang-vector06c`) is a
   future enhancement worth tracking but out of scope here.
