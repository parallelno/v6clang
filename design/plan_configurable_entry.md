# Plan: Configurable C Entry Symbol in crt0

## Problem

`crt0.s` hardcodes `CALL main` as the C-level entry point.  Programs that use a
different entry function name (e.g. game-ROM stubs, interrupt-driven firmwares,
or programs with custom startup) must either rename their function to `main` or
supply their own `_start` via `-nostartfiles`.

## Goal

Make the C entry symbol overridable at link time via
`-Wl,--defsym=__entry=NAME`, defaulting to `main`, exactly like `__stack_top`
controls the initial SP.

## Mechanism

`__stack_top` works as follows:

1. `v6clang.ld` defines `__stack_top = 0x0000;` (absolute value).
2. crt0 references it: `LXI SP, __stack_top`.
3. User overrides: `--defsym=__stack_top=0x8000` → ld.lld's absolute
   definition wins over the linker-script value.

For the entry symbol we need a *default alias*, not a fixed value.  The linker's
`PROVIDE` directive is the right tool:

```
PROVIDE(__entry = main);
```

`PROVIDE(sym = expr)` defines `sym` **only if it is not already defined** (by
`--defsym` or user object).  When the user passes `--defsym=__entry=myStart`, ld
defines `__entry` absolutely pointing at `myStart`; the `PROVIDE` is skipped.
When no override is given, `__entry` becomes an alias for `main`.

crt0 then calls `__entry` instead of `main`:

```asm
CALL __entry     ; call user entry (default: main, overridable via --defsym)
```

### Why `__entry` and not `__main`?

`__main` is reserved on several toolchains (GCC/libgcc uses it as the
global-constructor wrapper).  `__c_entry` is more descriptive but longer.
`__entry` is short, unambiguous, and consistent with the double-underscore
reserved-for-implementation-use convention.

## Symbol name

`__entry`

## Linker / driver changes needed

| Component | Change |
|-----------|--------|
| `compiler-rt/lib/builtins/v6clang/crt0.s` | `CALL main` → `CALL __entry`; update header comments |
| `clang/lib/Driver/ToolChains/V6Clang/v6clang.ld` | Add `PROVIDE(__entry = main);` inside `SECTIONS`; update header comment |
| No driver C++ change needed | `--defsym` already forwarded via `OPT_Wl_COMMA` |

## Usage

Default (unchanged behaviour):
```bash
clang -target i8080-unknown-v6clang -O2 main.c -o out.rom
```

Custom entry:
```bash
clang -target i8080-unknown-v6clang -O2 -Wl,--defsym=__entry=myStart main.c -o out.rom
```

## `gc-sections` interaction

`PROVIDE(__entry = main)` references `main`, so ld.lld's
`--gc-sections` keeps `main` live even when it is overridden by
`--defsym=__entry=myStart`.  The unused `main` function will be retained
in the ROM.  This is acceptable (it is a small, known cost) and mirrors
the behaviour of `PROVIDE` with other symbols in the existing script.
Users who need strict dead-stripping should use `-nostartfiles` and a
custom linker script.

## Test plan

### 1. Temp program (`temp/entry_override/`)

| File | Purpose |
|------|---------|
| `main_default.c` | Normal program with `main`, verify unchanged flow |
| `custom_entry.c` | Program with `myStart` instead of `main`, built with `--defsym=__entry=myStart` |
| `build.bat` | Demonstrates both build variants |

### 2. lit tests (`tests/lit/Linker/V6Clang/entry-override.test`)

- Assemble a `main` object and an `alt` object via `llc`.
- Link **without** `--defsym`: verify `__entry` symbol address equals `main`'s address.
- Link **with** `--defsym=__entry=alt`: verify `__entry` symbol address equals `alt`'s address.

`lit.local.cfg` gains a `%v6clang_crt0_src` substitution pointing at
`compiler-rt/lib/builtins/v6clang/crt0.s` so the test can assemble it inline.

## Affected documentation

- `docs/V6ClangArchitecture.md` — startup table + new "Overriding the C Entry Function" section.
- `docs/V6ClangUsage.md` — crt0 mandatory section; document `__entry` alongside
  `_start` override note.
- `docs/V6ClangBuildGuide.md` — add `--defsym=__entry=NAME` example next to
  `--defsym=__stack_top` example.
