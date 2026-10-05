# V6CLANG Runtime and Inline Asm

This document describes the V6CLANG header-only runtime (the math
library `v6clang_arith.h` and the `mem*` / `str*` library `<string.h>`)
and the calling-convention contract that lets compiler-emitted
libcalls and hand-written inline asm coexist on the V6CLANG target.

## Why a header-only runtime?

V6CLANG targets the Vector-06C (Soviet i8080-clone). The CPU has no MUL,
no DIV, and only single-amount shifts. Any `unsigned a * b` therefore
lowers to a libcall. Historically these were assembled `.s` files
shipped under `compiler-rt/lib/builtins/v6clang/`. Empirically that broke
two things V6CLANG cares about:

1. **IPRA per-call clobber sets.** V6CLANG's `getCallPreservedMask` is
   empty (no callee-saves). Without IPRA, every call is treated as
   clobbering every register. With IPRA, the clobber set of each
   *internal* (same-TU `static`) callee is recovered exactly. Asm
   stubs in a separate library are external — IPRA can't see them.
2. **Cross-call elision.** When the caller is already in HL/DE the
   shape ISel wants, a per-TU `static` definition lets the assembler
   (and same-TU peepholes) collapse argument shuffles.

So O70 made the math runtime header-only:

```c
#define V6CLANG_RT static __attribute__((noinline, used, naked, \
                                     annotate("v6clang-rt-helper")))

V6CLANG_RT unsigned char __mulqi3(unsigned char a, unsigned char b) {
    __asm__ volatile ( /* 8-iteration shift-add ending in MOV A,L; RET */ );
}
```

O80 extended the same pattern to the `mem*` / `str*` family, replacing
the old hand-assembled `compiler-rt/lib/builtins/v6clang/memory.s`. The
`V6CLANG_RT` macro itself now lives in a shared internal header
`v6clang_rt_macros.h` and is pulled in by every runtime header, so the
attribute set stays consistent across `v6clang_arith.h` and `<string.h>`.

Each translation unit gets its own per-TU copy. `--gc-sections` (now
on by default for V6CLANG in ld.lld) prunes the ones the program never
calls. IPRA recovers each routine's true clobber set.

The `annotate("v6clang-rt-helper")` tag is purely metadata. It has **no**
effect on codegen, linkage, calling convention, or section placement;
it only marks the function so the V6CLANG `AsmPrinter` can suppress its
body from `.s` text output by default. See
[Suppressing helpers from `.s` output](#suppressing-helpers-from-s-output)
below.

## What the header provides

Every libcall the V6CLANG backend can emit:

| Symbol            | C signature                            | Operation                  |
|-------------------|----------------------------------------|----------------------------|
| `__mulqi3`        | `u8(u8,u8)`                            | i8 multiply, low byte → A  |
| `__v6clang_mulqihi3`  | `u16(u8,u8)`                           | i8×i8 widening → HL        |
| `__mulhi3`        | `u16(u16,u16)`                         | i16 multiply low 16        |
| `__udivhi3`       | `u16(u16,u16)`                         | unsigned div               |
| `__umodhi3`       | `u16(u16,u16)`                         | unsigned mod               |
| `__divhi3`        | `i16(i16,i16)`                         | signed div (truncated)     |
| `__modhi3`        | `i16(i16,i16)`                         | signed mod (C99)           |
| `__udivmodhi4`    | `u16(u16,u16,u16*)`                    | fused unsigned divmod      |
| `__divmodhi4`     | `i16(i16,i16,i16*)`                    | fused signed divmod        |
| `__ashlhi3`       | `u16(u16,u8)`                          | logical left shift         |
| `__lshrhi3`       | `u16(u16,u8)`                          | logical right shift        |
| `__ashrhi3`       | `i16(i16,u8)`                          | arithmetic right shift     |

ISel automatically lowers `*`, `/`, `%`, `<<`, `>>` to the matching
symbol. The `udivmod`/`divmod` fused calls only fire when the
mid-level optimizer keeps `q=a/b` and `r=a%b` as separate
udiv/urem — the default mid-level rewrite of `a%b` to `a-(a/b)*b`
defeats fusion (and is usually faster anyway when there are 0 or
1 callers of `q*b`).

## What `<string.h>` provides

O80 ships a small header-only `<string.h>` covering the routines V6CLANG
programs (and a future libc port) need most. Each routine is `V6CLANG_RT`,
uses the V6CLANG C calling convention directly, and emits its own `RET`.
Unlike `v6clang_arith.h` it is **not** auto-included — TUs that want it
must `#include <string.h>` explicitly.

| Symbol  | C signature                                  | Notes                              |
|---------|----------------------------------------------|------------------------------------|
| `memcpy`  | `void *(void *, const void *, size_t)`     | non-overlapping copy               |
| `memset`  | `void *(void *, int, size_t)`              | low byte of `val` used             |
| `memmove` | `void *(void *, const void *, size_t)`     | direction-aware (copies tail-first if dst>src) |
| `strlen`  | `size_t(const char *)`                     | returns `HL = end - start`         |
| `strcmp`  | `int(const char *, const char *)`          | unsigned-byte semantics; returns +1 / -1 / 0 |
| `strcpy`  | `char *(char *, const char *)`             | NUL-terminated copy                |

`strcmp` deliberately returns ±1 (not the byte-difference). Per C the
result of `strcmp` is only specified by sign; using ±1 lets the body
decide via the carry flag after a `CMP M` instead of computing
`*a - *b` with sign extension (which is wrong for high-bit unsigned
bytes — e.g. `0x80` vs `0x00`).

## Auto-include

The clang driver passes `-include v6clang_arith.h` automatically when the
target triple is `i8080-unknown-v6clang`. The header is searched at:

1. `<resource-dir>/lib/v6clang/include/v6clang_arith.h`
2. `<bin>/../../compiler-rt/lib/builtins/v6clang/include/v6clang_arith.h` (dev tree)

`<string.h>` lives next to `v6clang_arith.h` in the same `compiler-rt/lib/
builtins/v6clang/include` directory. The driver adds that directory as an
`-internal-isystem` path so `#include <string.h>` resolves naturally;
the header is **not** auto-included.

To suppress auto-inclusion of `v6clang_arith.h` (and supply your own runtime):

```sh
clang -target i8080-unknown-v6clang -fno-v6clang-auto-include main.c -o out.rom
```

You'll then see `ld.lld: error: undefined symbol: __mulhi3` (etc.)
unless you provide them.

## Suppressing helpers from `.s` output

Because `v6clang_arith.h` is auto-included and every helper is `used`,
running `clang -S` on even a tiny source file would otherwise dump all
~15 runtime routines into the assembly listing alongside user code,
making the output hard to read. The V6CLANG `AsmPrinter` therefore
**suppresses helpers from `.s` text output by default**:

| Mode | Helpers in output? |
|------|--------------------|
| `clang -S foo.c -o foo.s` (text)               | No (suppressed) |
| `clang -S foo.c -o foo.s -mllvm -mv6clang-print-rt-helpers` | Yes |
| `clang -c foo.c -o foo.o` (object)             | Yes (always — required for linking) |
| `llc -filetype=obj foo.ll` (object)            | Yes (always — required for linking) |

Mechanism:

1. Each helper carries `__attribute__((annotate("v6clang-rt-helper")))`
   (applied automatically by the `V6CLANG_RT` macro). The clang frontend
   lowers this to an entry in the module-level
   `@llvm.global.annotations` global.
2. `V6ClangAsmPrinter::doInitialization` walks `@llvm.global.annotations`,
   collects every function tagged `"v6clang-rt-helper"`, and stores their
   names in a `StringSet`.
3. `V6ClangAsmPrinter::runOnMachineFunction` returns early — skipping
   directives, label, and instruction emission — when **all** of the
   following hold:
   - `getV6ClangPrintRTHelpersEnabled()` is `false` (default), and
   - `OutStreamer->hasRawTextSupport()` is `true` (i.e. assembly text,
     not object code), and
   - the function name is in the helper set.

Because the suppression is gated by `hasRawTextSupport()`, object-file
emission is never affected and the linker resolves helper calls
normally.

## Tagging your own helpers

If you ship a private routine under the same convention (header-only,
naked, hand-written 8080 asm) and want it filtered from `.s` output,
add the same annotation:

```c
static __attribute__((noinline, used, naked,
                      annotate("v6clang-rt-helper")))
unsigned int my_helper(unsigned int a, unsigned int b) {
    __asm__ volatile (
        /* hand-written 8080 body */
        "RET\n"
    );
}
```

Pass `-mllvm -mv6clang-print-rt-helpers` whenever you need to inspect the
generated body.

## Calling convention contract (free-list C ABI)

| Type    | Arg #1 | Arg #2 | Arg #3 | Return |
|---------|--------|--------|--------|--------|
| `i8`    | A      | B      | C      | A      |
| `i16`   | HL     | DE     | BC     | HL     |
| ptr     | (i16)  | (i16)  | (i16)  | (i16)  |

No callee-saves. Stack used only for arg #4+ and IPRA-determined
spills. The runtime header conforms to this convention so ISel
emits no shuffle code at the call site when the operands are
already in the right registers.

## Writing inline asm against the runtime

Naked functions in the V6CLANG target accept ONLY inline asm — any C
statement (including `(void)param;`) is rejected. Reference parameters
implicitly via the calling convention:

```c
static __attribute__((noinline, used, naked))
unsigned my_helper(unsigned hl_arg, unsigned de_arg) {
    /* hl_arg is in HL, de_arg is in DE. Return value goes in HL. */
    __asm__ volatile (
        "DAD  D    \n\t"   /* HL += DE */
        "RET       \n\t"
    );
}
```

For non-naked functions, use standard GCC inline-asm constraints
(currently a small subset is supported — see
`tests/lit/Clang/V6CLANG/inline-asm.c` for the recognized list).

## See also

- `design/plan_O70_math_header.md` — math header design rationale.
- `design/plan_O80_string_header.md` — `<string.h>` design rationale.
- `tests/v6clang_lib/linkage_smoke.c` — exercises every operator.
- `tests/v6clang_lib/divmod_combined.c` — fused divmod runtime check.
- `tests/lit/CodeGen/V6CLANG/i8_mul_libcall.ll` — i8 MUL → __mulqi3.
- `tests/lit/CodeGen/V6CLANG/divmod-fusion.ll` — udiv+urem fusion.
