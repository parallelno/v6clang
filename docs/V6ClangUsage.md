# V6CLANG Usage

C-frontend reference for the V6CLANG target: compiling, type model, language
restrictions, function attributes, builtins, inline assembly, and the
auto-included header set.

For build/setup and tooling pipeline, see
[V6ClangBuildGuide.md](V6ClangBuildGuide.md). For backend tuning flags and
debugging output, see [V6ClangCompilerOptions.md](V6ClangCompilerOptions.md).
For the math runtime contract, see
[V6ClangRuntimeAndInlineAsm.md](V6ClangRuntimeAndInlineAsm.md).

## Building Clang

To build Clang alongside the V6CLANG backend, add `-DLLVM_ENABLE_PROJECTS=clang`:

```bash
cmake -G Ninja -S llvm-project\llvm -B llvm-build ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DLLVM_TARGETS_TO_BUILD=X86 ^
  -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=V6Clang ^
  -DLLVM_ENABLE_PROJECTS=clang;lld

ninja -C llvm-build clang llc ld.lld llvm-objcopy
```

## Compiling C Code

```bash
# C source → LLVM IR
llvm-build/bin/clang -target i8080-unknown-v6clang -S -emit-llvm hello.c -o hello.ll

# C source → V6CLANG assembly
llvm-build/bin/clang -target i8080-unknown-v6clang -S hello.c -o hello.s

# C source → object file
llvm-build/bin/clang -target i8080-unknown-v6clang -c hello.c -o hello.o
```

The driver automatically forces `-ffreestanding` (no hosted C library).

## Type Sizes

| C Type | Size | Notes |
|--------|------|-------|
| `char` | 1 byte | **Unsigned** by default |
| `short` | 2 bytes | |
| `int` | 2 bytes | Same as pointer width |
| `long` | 4 bytes | Software-emulated |
| `long long` | 8 bytes | Warning: very expensive |
| `float` | 4 bytes | Software-emulated (IEEE single) |
| `double` | 4 bytes | Mapped to `float` (no 64-bit FP) |
| `void *` | 2 bytes | 16-bit address space |

## Built-in Macros

| Macro | Description |
|-------|-------------|
| `__V6CLANG__` | Always defined for V6CLANG targets |
| `__I8080__` | Always defined for i8080 |
| `__CHAR_UNSIGNED__` | Indicates `char` is unsigned |

## Language Restrictions

The V6CLANG target emits warnings (controlled by `-Wv6clang-expensive-type`) when using types that require expensive software emulation:

- **`long long`** (64-bit integer) — prohibitively expensive on 8-bit CPU
- **`float` / `double`** — no FPU, all operations are software-emulated

Suppress with `-Wno-v6clang-expensive-type` if intentional.

## Function Attributes

| Attribute | Effect |
|-----------|--------|
| `__attribute__((leaf))` | Declares that the function does not call back into the current translation unit. Allows LLVM to infer `norecurse` on callers, enabling static stack allocation (O10). Use on external declarations. |
| `__attribute__((interrupt))` | Marks a function as an interrupt service routine. Excludes it and all its transitive callees from static stack allocation and SP-trick optimization. |
| `__attribute__((annotate("v6clang-rt-helper")))` | Tags a function as a V6CLANG runtime helper. The V6CLANG `AsmPrinter` uses this tag to suppress the function from `.s` output by default; the object-file emission (`-c`/`-filetype=obj`) is unaffected. Used by the auto-included `v6clang_arith.h` header. Toggle visibility with `-mllvm -mv6clang-print-rt-helpers` (see [V6ClangCompilerOptions.md](V6ClangCompilerOptions.md#debugging)). |

Example:
```c
// External function that never calls back into user code.
// Without this attribute, callers cannot get static stack allocation.
__attribute__((leaf))
extern void uart_write(unsigned char c);

// The compiler can now prove this caller is non-reentrant
// and allocate its spill slots statically.
void send_message(const unsigned char *buf, unsigned int len) {
    for (unsigned int i = 0; i < len; i++)
        uart_write(buf[i]);
}
```

## Hardware Instruction Wrappers (`<v6clang.h>`)

Include `<v6clang.h>` for always-inlined wrappers around i8080 hardware instructions:

| Function | Assembly | Purpose |
|----------|----------|---------|
| `v6clang_in(port)` | `IN port` | Read I/O port (returns `uint8_t`) |
| `v6clang_out(port, val)` | `OUT port` | Write `val` to I/O port |
| `v6clang_di()` | `DI` | Disable interrupts |
| `v6clang_ei()` | `EI` | Enable interrupts |
| `v6clang_hlt()` | `HLT` | Halt processor |
| `v6clang_nop()` | `NOP` | No-operation |
| `v6clang_set_sp(addr)` | `LXI SP, addr` | Set stack pointer to a compile-time constant |

Example:
```c
#include <v6clang.h>

void write_port(uint8_t port, uint8_t val) {
    v6clang_out(port, val);
}

uint8_t read_port(uint8_t port) {
    return v6clang_in(port);
}

void critical_section(void) {
    v6clang_di();
    // ... critical code ...
    v6clang_ei();
}
```

## Inline Assembly

The V6CLANG target supports GCC-style inline assembly with 8080 mnemonics:

```c
V6CLANG_INLINE
uint8_t v6clang_set_empty_interrupt(uint8_t a0, uint8_t a1) {
    register uint8_t _a0 asm("B") = a0;
    register uint8_t _a1 asm("C") = a1;
    uint8_t val;

    __asm__ volatile (
        "MVI A, %[ei]       \n"
        "STA 0x38           \n"
        "MVI A, %[ret]      \n"
        "STA 0x39           \n"
        "ADD B              \n"
        "ADD C              \n"
        /* outputs */
        : "=a"(val)
        /* input constraints */
        : [ei] "i"(OPCODE_EI), [ret] "i"(OPCODE_RET), [_a0] "r"(a0), [_a1] "r"(a1)
        /* clobbered regs */
        : "A", "FLAGS"
    );
    return val;
}
```

**Constraint letters:**

| Constraint | Meaning |
|------------|---------|
| `a` | Accumulator (A register) |
| `r` | Any 8-bit general register |
| `p` | Any 16-bit register pair (BC, DE, HL) |
| `I` | 8-bit unsigned immediate (0–255) |
| `J` | 16-bit unsigned immediate (0–65535) |

## V6CLANG Runtime Headers

All V6CLANG runtime headers live in a single directory:
`compiler-rt/lib/builtins/v6clang/include/` (dev tree) or
`<resource-dir>/lib/v6clang/include/` (installed). The driver injects this
directory via `-internal-isystem`, so the following headers resolve
without any `-I` or `-isystem` flag:

| Header | Provides |
|--------|----------|
| `<string.h>` | `memcpy`, `memset`, `memmove`, `strlen`, `strcmp`, `strcpy` — header-only inline asm; opt-in via `#include` |
| `<stdlib.h>` | `EXIT_SUCCESS`/`EXIT_FAILURE`, `abort()`, `exit(int)` (both `noreturn`, expand to `HLT` loop), `abs()`, `labs()`, `min()`, `max()` |
| `<v6clang.h>` | `v6clang_in`, `v6clang_out`, `v6clang_di`, `v6clang_ei`, `v6clang_hlt`, `v6clang_nop`, `v6clang_set_sp` — inline asm wrappers for i8080 hardware instructions |
| `v6clang_arith.h` | Math runtime (`__mulqi3`, `__mulhi3`, `__udivhi3`, `__divhi3`, `__ashlhi3`, ...). **Auto-included** via `-include v6clang_arith.h` on V6CLANG targets; suppress with `-fno-v6clang-auto-include`. See [V6ClangRuntimeAndInlineAsm.md](V6ClangRuntimeAndInlineAsm.md). |

All runtime routines are header-only inline-`__asm__` helpers — there
is no `libv6clang-builtins.a` archive. Each translation unit gets its own
per-TU static copy of every helper it actually calls; `--gc-sections`
(on by default for V6CLANG in ld.lld) prunes the unreferenced ones.

The driver also passes `-ffunction-sections` by default so per-function
ELF sections are emitted. Pass `-Wl,--gc-sections` at the link step to
prune unreferenced helper functions transitively. Override the
per-function sections with `-fno-function-sections` if needed.

The V6CLANG include directory is injected only by the V6CLANG toolchain;
cross-host compiles for x86 and other targets are unaffected.

## Inline Assembly Patterns

Two idiomatic styles are supported by the V6CLANG inline-asm flow:

### Style A — Inlined Body (single instruction sequence)

The compiler interleaves the asm with surrounding code. Use for short
sequences where the cost of a `CALL` would dominate.

```c
static inline __attribute__((always_inline))
void out_port(unsigned char port, unsigned char val) {
    __asm__ volatile (
        "MVI A, %1\n"
        "OUT %0\n"
        : : "i"(port), "r"(val)
        : "A"
    );
}
```

The clobber list (`"A"` here) is honored exactly: only the accumulator
is treated as live-out across the asm block. Pair registers `B`/`D`/`H`
and pair halves `C`/`E`/`L` are not spilled unless explicitly listed.

### Style B — CALL Extern (per-routine `.o`)

The asm is a single `CALL helper` with a strict clobber list; the
helper lives in a separately assembled `.s`/`.o` file. Pruning by
`ld.lld --gc-sections` works transitively across the asm/C boundary
because `CALL helper` emits a normal `R_V6CLANG_16` relocation the
linker can see.

```c
static inline __attribute__((always_inline))
void external_helper(void) {
    __asm__ volatile ("CALL helper" : : : "A", "memory");
}
```

GCC register names used in clobber lists are case-sensitive: spell
single regs uppercase (`"A"`, `"B"`, `"C"`, `"D"`, `"E"`, `"H"`, `"L"`).

## Computed Jumps and `--gc-sections`

`ld.lld --gc-sections` walks relocations in **all** reachable
sections, including `.rodata` jump tables. Authors must encode
addresses through the assembler's symbol machinery so a relocation is
emitted; otherwise the target may be GC'd:

| Form | Relocation | Status |
|------|------------|--------|
| `.word target` | `R_V6CLANG_16` | Safe |
| `.byte target@lo` / `.byte target@hi` | `R_V6CLANG_8_LO` / `R_V6CLANG_8_HI` | Safe |
| Hand-computed `.byte 0xC3, 0x34, 0x12` literal | none | **Unsafe** — linker can't see the reference |

Forced-live escapes when the relocation route is impractical:

- `__attribute__((used))` on a C wrapper that references the target.
- `KEEP(*(.text.func))` in the linker script.
- Group all jump-table targets in a single `KEEP`'d section.

## End-to-End Example

```bash
# Single-command build of a C program for V6CLANG.
# The driver finds crt0.o under <resource-dir>/lib/v6clang/ (or the
# compiler-rt dev tree), runs ld.lld with v6clang.ld (and --gc-sections),
# and converts the linked ELF to a flat ROM via llvm-objcopy.
# Auto-includes v6clang_arith.h for the math runtime (suppress with
# -fno-v6clang-auto-include).
llvm-build/bin/clang -target i8080-unknown-v6clang -O2 main.c -o out.rom
```

For source debugging, add `-g`. A flat-ROM output retains a sibling DWARF v5
final ELF containing the DWARF line tables and symbols; launch the emulator
with the `.rom` and use the `.elf` as its debug companion.

```bash
llvm-build/bin/clang -target i8080-unknown-v6clang -g \
    main.c -o out.rom
# Produces out.rom and out.elf.
```

No `-nostartfiles`, `-nodefaultlibs`, or `-Wl,--defsym=_start=main`
workaround is needed. `crt0.s` is assembled by the V6CLANG MC AsmParser
(Phase 3 of the asm-interop overhaul), and `_start` is the canonical
entry point declared in `crt0.s`.

## crt0.o is Mandatory (and How to Opt Out)

Every V6CLANG link pulls in `crt0.o`, which defines `_start` — the entry
symbol named by `v6clang.ld`. Without it, `ld.lld --gc-sections` would have
no root and silently drop every code section, producing a zero-byte ROM.
To make that failure visible at build time, the clang driver **errors
out** when `crt0.o` cannot be located:

```text
clang: error: no such file or directory: 'crt0.o (V6CLANG startup) —
assemble crt0.s with scripts/build_v6clang_runtime.ps1, or pass
-nostartfiles to opt out'
```

### Overriding the C Entry Function

By default `crt0` calls `main`. The V6CLANG linker script provides this
default via `PROVIDE(__entry = main);` — a no-op when `--defsym` already
defines `__entry`. To call a different function instead:

```bash
clang -target i8080-unknown-v6clang -O2 -Wl,--defsym=__entry=myStart \
      main.c -o out.rom
```

This is analogous to `--defsym=__stack_top=ADDR` for the stack pointer.
No `-nostartfiles` or other workaround is required — crt0 still runs,
sets up the stack, zeroes `.bss`, and then transfers control to `myStart`.

The driver searches two locations (see
`clang/lib/Driver/ToolChains/V6Clang.cpp` → `findV6ClangRuntimeFile`):

1. `<ResourceDir>/lib/v6clang/crt0.o` — installed release tree
   (populated by `scripts/make_dist.ps1`).
2. `<clang-bin>/../../compiler-rt/lib/builtins/v6clang/crt0.o` — dev tree
   (populated by `scripts/build_v6clang_runtime.ps1`, which
   `scripts/build.ps1` invokes automatically after `ninja`).

If the error fires in a dev checkout, run `scripts/build_v6clang_runtime.ps1`
to assemble `crt0.s` → `crt0.o` next to the source. See
[V6ClangBuildGuide.md → Build the V6CLANG Runtime](V6ClangBuildGuide.md#build-the-v6clang-runtime-crt0o).

### Freestanding / `-nostartfiles` Builds

Pass `-nostartfiles` (or `-nostdlib`) to tell the driver **not** to link
`crt0.o`. This is for programs that supply their own startup, e.g. a
custom `_start`, ROM monitor entry, or a bootloader stub:

```bash
clang -target i8080-unknown-v6clang -nostartfiles -Wl,--defsym=_start=main \
      main.c -o out.rom
```

Without a `_start` symbol (either from `crt0.o` or `--defsym`),
`ld.lld` emits `cannot find entry symbol _start; not setting start
address` and the resulting ROM has no defined entry point.
