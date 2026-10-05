# V6CLANG Target Architecture

## CPU

| Property | Value |
|----------|-------|
| CPU | Intel 8080 (KR580VM80A) |
| Clock | 3 MHz |
| Memory | 64 KB flat address space |
| Endianness | Little-endian |
| Word size | 8-bit ALU, 16-bit address bus |
| Registers | A, B, C, D, E, H, L (8-bit); BC, DE, HL, SP (16-bit pairs) |
| Stack | Grows downward, full-descending |

## Data Layout

```
e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8
```

- Pointers are 16-bit, byte-aligned
- Native integer widths: 8 and 16 bits
- No hardware alignment requirements

## Default Memory Map

The canonical layout is set by `clang/lib/Driver/ToolChains/V6Clang/v6clang.ld`,
which clang passes to `ld.lld` automatically. Sections are emitted in
the order `.text`, `.rodata`, `.data`, `.bss.pack`, `.bss`. The linker
also defines the symbols `__bss_start`, `__bss_end`, and
`__stack_top = 0x0000`.

```
0x0000 ┌──────────────────┐  ← __stack_top (first PUSH wraps SP to 0xFFFE)
       │  (reserved)      │
0x0100 ├──────────────────┤  ← Default load address (`. = 0x0100;` in v6clang.ld)
       │  .text._start    │  ← crt0 / entry pinned by KEEP(*(.text._start))
       │  .text           │
       │  .rodata         │
       │  .data           │
       │  .bss.pack       │  ← __bss_start; linker-packed BSS blocks
       │  .bss            │  ← ordinary BSS data (no bytes added to ROM/COM)
       │                  │  ← __bss_end; .bss.pack & .bss sections zeroed by crt0
       │  (heap ↑)        │
       │       ...        │
       │  (stack ↓)       │  ← grows downward from 0xFFFE
0x8000 ├──────────────────┤
       │  Video RAM       │
0xFFFF └──────────────────┘
```

To relocate `.text` to a different base, override the script base via
`-Wl,-Ttext=0xNNNN` or pass a custom script with `-Wl,-T,my.ld`.

### Packed BSS Blocks

The V6CLANG linker packs independent zero-initialized runtime blocks in the
`.bss.pack` output section. Input section names select each block's rule:

| Input section | Placement rule |
|---------------|----------------|
| `.bss.pack` | Filler; may start anywhere and cross a 256-byte page boundary. |
| `.bss.pack.align` | Anchor; starts on a 256-byte page boundary. |
| `.bss.pack.window` | Window; at most 256 bytes and contained in one 256-byte page. |

Each logical block must be a separate writable, allocatable `SHT_NOBITS`
input section with alignment 1. Normal linker garbage collection applies per
block, so an unreferenced block is discarded with `--gc-sections`. The packed
arena remains inside `[__bss_start, __bss_end)` and is zeroed by crt0 without
occupying bytes in a flat ROM image.

### Overriding the Initial Stack Pointer

`crt0` sets `SP = __stack_top` before calling `__entry`. The default value
`0x0000` causes the first `PUSH` to wrap SP to `0xFFFE` (top of RAM).
To place the stack elsewhere, override the symbol at link time:

```bash
llvm-build/bin/clang -target i8080-unknown-v6clang -O2 \
    -Wl,--defsym=__stack_top=0xBFFF input.c -o output.elf
```

`-Wl,` forwards the flag to `ld.lld`; `--defsym` overrides the value
defined in `v6clang.ld`. The new SP takes effect at the very first instruction
of `_start` — before any C code runs.

### Overriding the C Entry Function

`crt0` calls `__entry` instead of hardcoding `main`. The linker script
provides the default via `PROVIDE(__entry = main);`, which is a no-op when
`--defsym` already defines `__entry`. To use a different function name:

```bash
llvm-build/bin/clang -target i8080-unknown-v6clang -O2 \
    -Wl,--defsym=__entry=myStart input.c -o output.elf
```

The user-supplied function (`myStart` here) must match the V6CLANG calling
convention and return `i8` or `i16`; the return value is ignored by crt0.

## Supported Type Widths

| C Type | Width | LLVM Type | Support |
|--------|-------|-----------|---------|
| `char` / `unsigned char` | 8-bit | `i8` | Native (8080 ALU) |
| `short` / `unsigned short` | 16-bit | `i16` | Register pairs (BC, DE, HL); pseudo-instructions expand to 8-bit sequences |
| `int` / `unsigned int` | 16-bit | `i16` | Same as `short` |
| `long` / `unsigned long` | 32-bit | `i32` | Expanded to pairs of `i16` |
| `void *` / pointers | 16-bit | `i16` | Native 16-bit address bus |

**Limitations:**
- `long long` (64-bit): Not supported. Diagnostic warning emitted.
- `float` / `double`: Not supported (no FPU). Diagnostic warning emitted.
- `char` is **unsigned** by default (`__CHAR_UNSIGNED__`).
- No hardware alignment requirements — all types are byte-aligned.
- Maximum addressable memory: 64 KB.

## Calling Convention Summary

All registers are **caller-saved** (no callee-saved registers).

| Argument # | i8 | i16 |
|------------|-----|------|
| 1st | `A` | `HL` |
| 2nd | `E` | `DE` |
| 3rd | `C` | `BC` |
| 4th+ | Stack | Stack |

Returns: `i8` → `A`, `i16` → `HL`, `i32` → `DE:HL`.

See [V6ClangCallingConvention.md](V6ClangCallingConvention.md) for full details.

## Runtime Library

The V6CLANG runtime library lives at `compiler-rt/lib/builtins/v6clang/`.
With one exception (`crt0.s`), it is delivered as a **header-only**
inline-asm runtime shipped under `compiler-rt/lib/builtins/v6clang/include/`.
Each routine is a `static naked noinline used` function whose body is
a single `__asm__ volatile` block ending in `RET`. The clang driver
adds the include directory as `-internal-isystem`; `v6clang_arith.h` is
auto-included, `<string.h>` is opt-in via `#include`. All routines
follow the V6CLANG calling convention. See
[V6ClangRuntimeAndInlineAsm.md](V6ClangRuntimeAndInlineAsm.md) for the full
rationale.

### Startup

| File | Symbol | Description |
|------|--------|-------------|
| `crt0.s` | `_start` | Sets `SP = __stack_top` (default `0x0000` → first PUSH wraps to `0xFFFE`), zeros `[__bss_start, __bss_end)`, calls `__entry` (default: `main`), then `HLT`. Placed in `.text._start` so the linker script (`v6clang.ld`) pins it at `0x0100`. |

### Arithmetic (provided by `v6clang_arith.h`, auto-included)

| Symbol | Signature | Description |
|--------|-----------|-------------|
| `__mulqi3`        | `u8(u8,u8)`           | i8 multiply, low byte → A |
| `__v6clang_mulqihi3`  | `u16(u8,u8)`          | widening i8×i8 → HL |
| `__mulhi3`        | `u16(u16,u16)`        | 16×16→16 unsigned multiply |
| `__udivhi3`       | `u16(u16,u16)`        | unsigned 16-bit division |
| `__umodhi3`       | `u16(u16,u16)`        | unsigned 16-bit modulo |
| `__divhi3`        | `i16(i16,i16)`        | signed 16-bit division |
| `__modhi3`        | `i16(i16,i16)`        | signed 16-bit modulo |
| `__udivmodhi4`    | `u16(u16,u16,u16*)`   | fused unsigned divmod |
| `__divmodhi4`     | `i16(i16,i16,i16*)`   | fused signed divmod |
| `__ashlhi3`       | `u16(u16,u8)`         | variable left shift |
| `__lshrhi3`       | `u16(u16,u8)`         | variable logical right shift |
| `__ashrhi3`       | `i16(i16,u8)`         | variable arithmetic right shift |

### Memory / strings (provided by `<string.h>`, opt-in)

| Symbol  | Signature                                | Notes |
|---------|------------------------------------------|-------|
| `memcpy`  | `void *(void *, const void *, size_t)` | forward byte copy |
| `memset`  | `void *(void *, int, size_t)`          | low byte of `val` used |
| `memmove` | `void *(void *, const void *, size_t)` | overlap-safe |
| `strlen`  | `size_t(const char *)`                 | NUL-terminated length |
| `strcmp`  | `int(const char *, const char *)`      | unsigned-byte semantics, returns ±1 / 0 |
| `strcpy`  | `char *(char *, const char *)`         | NUL-terminated copy |

### Backend Integration

- i8 arithmetic (`MUL`, `SDIV`, `UDIV`, `SREM`, `UREM`) is promoted to i16, so all operations use the i16 libcalls.
- i8 variable shifts are promoted to i16 with appropriate zero/sign extension.
- i16 variable shifts emit libcalls directly.
- Constant shifts are unrolled inline (no libcall).

## ELF Object Format

V6CLANG object files (`.o` produced by `clang -c` / `llc -filetype=obj`) and
linked images use the standard ELF32 little-endian container with a private,
unassigned `e_machine` value:

| Field | Value |
|-------|-------|
| `e_ident[EI_CLASS]` | `ELFCLASS32` |
| `e_ident[EI_DATA]`  | `ELFDATA2LSB` |
| `e_ident[EI_OSABI]` | `ELFOSABI_STANDALONE` (no hosted runtime) |
| `e_machine`         | `EM_V6Clang = 0x8080` |

`EM_V6Clang = 0x8080` is **not** registered with the official ELF e_machine
registry. The value was chosen to mirror the i8080 CPU number and is local to
this toolchain. It is defined once in `llvm/include/llvm/BinaryFormat/ELF.h`
and consumed by:

- `llvm/lib/Target/V6Clang/MCTargetDesc/V6ClangAsmBackend.cpp` — emits objects with
  this `e_machine`.
- `lld/ELF/Arch/V6Clang.cpp` + `lld/ELF/Target.cpp` — `ld.lld` dispatches to the
  V6CLANG relocation backend on this `e_machine`.

### Relocations

V6CLANG is purely absolute (no PC-relative addressing on the 8080). Four
relocation types are defined; their numeric values are stable and shared
between `V6ClangAsmBackend` (writer) and `lld` (consumer):

| Type | Value | Width | Description |
|------|-------|-------|-------------|
| `R_V6CLANG_NONE` | 0 | — | No relocation |
| `R_V6CLANG_8`    | 1 | 1 byte  | 8-bit absolute value |
| `R_V6CLANG_16`   | 2 | 2 bytes | 16-bit absolute address (little-endian) |
| `R_V6CLANG_LO8`  | 3 | 1 byte  | Low byte of a 16-bit absolute (`lo8(expr)`) |
| `R_V6CLANG_HI8`  | 4 | 1 byte  | High byte of a 16-bit absolute (`hi8(expr)`) |

`R_V6CLANG_8` and `R_V6CLANG_16` perform overflow checks (the value must fit in a
signed or unsigned 8/16-bit field). `R_V6CLANG_LO8` / `R_V6CLANG_HI8` are byte
extractions and never overflow.
