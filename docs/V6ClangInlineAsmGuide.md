# V6CLANG Inline Asm Guide

A practical reference for writing GCC/Clang inline assembly targeting the
V6CLANG (Vector-06C / i8080) backend. This is a syntax + idiom guide; for the
runtime-helper / IPRA contract see
[V6ClangRuntimeAndInlineAsm.md](V6ClangRuntimeAndInlineAsm.md).

---

## 1. `asm` keyword forms

| Form        | When to use                                                                 |
|-------------|------------------------------------------------------------------------------|
| `asm(...)`  | Plain C with a GNU dialect (Clang's default `-std=gnu11`). Not available in strict `-std=c11`. |
| `__asm__(...)` | Always available, in any `-std=` mode. Use in headers and portable code. |
| `__asm(...)`  | Same as `__asm__`. Less common. |

All three lower to identical IR. Mixing them in the same TU is harmless.

## 2. Basic vs extended asm

### Basic asm — no operand lists

```c
asm ("DI");                 // disable interrupts
asm ("HLT");
```

* No operands, no clobbers, no template substitutions.
* **Implicitly `volatile`** — never deleted, never moved.
* Compiler treats it as a black box that may touch anything → you must
  preserve any register the surrounding code relies on, or use extended
  asm with a proper clobber list.

### Extended asm — with operand lists

```
asm [volatile] ( template
                 : outputs
                 : inputs
                 : clobbers );
```

The four sections are colon-separated. Empty sections are allowed; trailing
ones may be omitted.

## 3. The template string

The template is a string literal containing one or more V6CLANG instructions.
Multi-line templates use `\n\t` between instructions so the assembler sees
them on separate, indented lines:

```c
asm ("ADD C\n\t"
     "MOV C, A");
```

Operands declared in the lists are referenced inside the template via:

* **Positional**: `%0`, `%1`, ... numbered in the order outputs-then-inputs.
* **Symbolic**: `%[name]` after declaring `[name]"r"(c_expr)` in the list.

```c
uint8_t x, y;
asm ("ADD %[src]"
     : [dst]"+a"(x) : [src]"r"(y));
```

To emit a literal `%` write `%%`.

## 4. Output, input, and clobber lists

```c
register uint16_t bc_in  asm("BC") = arg;   // local register variable, BC, initialized
register uint16_t out    asm("BC");          // local register variable, BC, write target

asm volatile ("call helper"
              : "=r"(out)     // outputs:  C lvalue receiving a written value
              : "r"(bc_in)    // inputs:   C rvalue supplying a read value
              : "FLAGS");     // clobbers: things the asm trashes
```

The bracketed `(out)`, `(bc_in)` are **C expressions** (lvalue for outputs,
rvalue for inputs). They have nothing to do with what is written *inside*
the template — the template references them only through `%0`/`%[name]`
substitutions (or, as above, indirectly via register-pinned variables).

### Constraint string syntax

`"<mods><letter>"` where `<letter>` selects the allowed location and
`<mods>` is zero or more prefix modifiers.

#### V6CLANG-supported constraint letters

| Letter | Meaning                                                | Reg class |
|--------|--------------------------------------------------------|-----------|
| `r`    | Any GPR. 8-bit operand → `GR8` (A,L,H,E,D,C,B); 16-bit operand → `GR16` (HL,DE,BC). | `GR8` / `GR16` |
| `a`    | The accumulator only.                                  | `A`       |
| `p`    | A 16-bit register pair.                                | `GR16`    |
| `I`    | 8-bit unsigned immediate (compile-time constant).      | —         |
| `J`    | 16-bit unsigned immediate.                             | —         |
| `m`    | A memory operand (generic GCC; lowers via address regs). | — |
| `i`    | Any immediate integer constant, or a symbol address (`&global`). For byte extraction from a link-time address use the `<`/`>` operators in the template (see §7.5). | —         |
| `g`    | Register, memory, or immediate.                        | —         |
| `0`..`9` | Matching constraint — must share location with operand N. | — |

Defined in `V6ClangTargetLowering::getConstraintType` /
`getRegForInlineAsmConstraint`.

#### Modifiers (prefix the letter)

| Mod | Meaning |
|-----|---------|
| `=` | Write-only output. Old value is not read. |
| `+` | Read-write output. Asm reads then writes the same operand. |
| `&` | Early-clobber. Output is written before all inputs are read; must not share a register with any input. Use whenever the asm writes the output partway through and then reads other inputs. |
| `%` | Operand is commutative with the next; compiler may swap. |
| (none on input) | Read-only input. |

#### Clobbers

A clobber tells the compiler "this register/resource is destroyed". The
compiler will spill anything live in that register across the asm.

V6CLANG names usable in clobber lists:

* Byte regs: `"A"`, `"B"`, `"C"`, `"D"`, `"E"`, `"H"`, `"L"`
* Pair regs: `"BC"`, `"DE"`, `"HL"`, `"SP"`, `"PSW"`
* `"FLAGS"` — condition codes (Z, C, S, P, AC). Equivalent to GCC's
  generic `"cc"` clobber on other targets.
* `"memory"` — see §6.

Listing a pair (e.g. `"HL"`) implicitly clobbers its sub-registers (`H`, `L`).

## 5. Local register variables ("register-asm")

```c
register uint16_t bc_in asm("BC") = arg;
```

Declares a C variable **pinned to a physical register** for the purpose
of an adjacent extended-asm statement.

* The pin applies *at the use site by the asm*, not globally. Doing
  arithmetic on `bc_in` elsewhere does not generally force BC.
* In an operand, combine with `"r"` (or any class containing the chosen
  reg). The compiler narrows `"r"` to exactly the pinned register.
* Used in pairs (one init'd input + one uninitialized output) this is the
  standard way to implement a **custom calling convention at a single
  call site** without touching the backend CC tables.

Idiomatic pattern (custom CC at a call site, BC in/out):

```c
register uint16_t bc_in asm("BC") = arg0;
register uint16_t result asm("BC");
asm volatile ("call helper" : "=r"(result) : "r"(bc_in) : "FLAGS");
```

Valid V6CLANG pin names: `A`, `B`, `C`, `D`, `E`, `H`, `L`, `BC`, `DE`, `HL`.
Pinning to `SP` or `FLAGS` is not supported.

## 6. `volatile` and `"memory"`

### `volatile`

Without `volatile`, an *extended* asm is treated as a pure function of its
declared inputs/outputs. The compiler may:

* Delete it if its outputs are unused.
* Hoist it out of loops (LICM/CSE) when inputs are loop-invariant.
* Reorder it across unrelated code.

`asm volatile` disables all three. Use it whenever the asm has any side
effect not captured in the output list — I/O (`IN`/`OUT`), control flow
(`CALL`, `JMP`, `RST`, `HLT`), memory stores, flag-only effects relied on
by later asm, etc.

Basic asm (no operand lists) is **implicitly volatile**; the keyword is
redundant but harmless.

### `"memory"` clobber

Declares that the asm may read or write arbitrary memory the compiler
cannot see. Effects:

1. All values the compiler had cached in registers from memory must be
   **reloaded** after the asm.
2. All pending stores held in registers must be **flushed to memory**
   before the asm.
3. The asm becomes a **memory barrier** — loads/stores cannot be reordered
   across it.

Add `"memory"` whenever the asm:

* Writes to a memory location not exposed as an output operand.
* Reads memory not exposed as an input operand.
* Performs a `CALL` to a routine that might do either.

Omitting `"memory"` when it's needed causes silent miscompiles under
optimization.

## 7. Worked examples

### 7.1 Port output (volatile, no operands needed beyond input)

```c
static inline void v6clang_out(uint8_t port, uint8_t v) {
    // OUT takes an 8-bit immediate port; A must hold the value.
    asm volatile ("OUT %[p]"
                  :
                  : "a"(v), [p]"I"(port));
}
```


### 7.2 Read-modify-write the accumulator

```c
static inline uint8_t add_via_asm(uint8_t a, uint8_t b) {
    asm ("ADD %[rhs]"
         : [acc]"+a"(a)        // A is both input and output
         : [rhs]"r"(b)
         : "FLAGS");
    return a;
}
```

Note `+a`: A is read **and** written, so `+` (not `=`) is required.

### 7.3 16-bit add via DAD H

```c
static inline uint16_t dad(uint16_t lhs, uint16_t rhs) {
    register uint16_t hl asm("HL") = lhs;
    register uint16_t de asm("DE") = rhs;
    asm ("DAD D"
         : "+r"(hl)
         : "r"(de)
         : "FLAGS");
    return hl;
}
```

### 7.4 Custom calling convention (BC in, BC out)

See `temp/asm_inline/custom_cc.c` for a full worked test.

```c
__attribute__((noinline, used)) void helper(void) {
    asm ( /* reads BC and A, writes BC, clobbers A and FLAGS */
        "STAX B  \n\t"
        "ADD C   \n\t"
        "MOV C,A \n\t"
        "ADD B   \n\t"
        "MOV B,A");
    // RET emitted by the C epilogue.
}

static inline uint16_t call_helper(uint16_t arg) {
    register uint16_t in  asm("BC") = arg;
    register uint16_t out asm("BC");
    asm volatile ("call helper" : "=r"(out) : "r"(in) : "A", "FLAGS");
    return out;
}
```

### 7.5 Load the hi/lo byte of a link-time symbol address

8080 `MVI r, imm8` takes a single byte. When you want to load only the
high or low byte of an address that is not known until link time, use the
V6CLANG byte-extraction prefix operators inside the asm template:

| Operator | Meaning                         | ELF relocation  |
|----------|---------------------------------|-----------------|
| `<(sym)` | Low byte of the 16-bit address  | `R_V6CLANG_LO8`     |
| `>(sym)` | High byte of the 16-bit address | `R_V6CLANG_HI8`     |

The relocation is patched by lld at link time, so the asm assembles and
links correctly regardless of where the linker places the symbol.

```c
static uint8_t addr = 0x42;

void set_hl_to_addr(void) {
    asm (
        "MVI H, >(%[a]) \n"   // H = high byte of &addr
        "MVI L, <(%[a]) \n"   // L = low  byte of &addr
        :
        : [a] "i" (&addr)
    );
}
```

The `"i"` constraint passes the *address* of `addr` as a symbolic
immediate. The operators `<`/`>` are applied in the assembler, not at the
C level — so this compiles and links correctly even though the address is
not a compile-time constant.

**Why not compute the byte in C?**

```c
// WRONG — does not compile:
[lo] "i" (((uint8_t)&addr) & 0xFF)
```

The `"i"` constraint requires an integer constant expression in the C
sense. A pointer cast to an integer is a runtime/link-time quantity, not a
C constant expression, so Clang rejects it with `invalid operand for inline
asm constraint 'i'`.

**Full LXI + byte-load example** (set HL to the address, then override one
byte — e.g. to page-switch a banked address):

```c
asm (
    "LXI  H, %[a]    \n"   // HL = full 16-bit address  (R_V6CLANG_16)
    "MVI  H, >(%[a]) \n"   // H  = high byte            (R_V6CLANG_HI8)
    "MVI  L, <(%[a]) \n"   // L  = low  byte            (R_V6CLANG_LO8)
    :
    : [a] "i" (&addr)
);
```

The operators work on any constant-address expression accepted by `"i"`,
including `&global`, `&global + N`, and numeric literals.

### 7.6 Naked runtime helper (the V6CLANG runtime pattern)

```c
#define V6CLANG_RT static __attribute__((noinline, used, naked, \
                                     annotate("v6clang-rt-helper")))

V6CLANG_RT uint8_t __mulqi3(uint8_t a, uint8_t b) {
    asm volatile (/* full prologue/body/RET */);
}
```

`naked` suppresses the compiler-generated prologue/epilogue — the asm
template must include its own `RET`. The default CC's parameter
locations still apply (see [V6ClangCallingConvention.md](V6ClangCallingConvention.md)).

## 8. Diagnosing mistakes

* **"impossible constraint"** — usually a constraint letter the V6CLANG
  backend does not accept, or `=` used where `+` is needed (or vice versa).
* **Asm produces wrong values intermittently** — missing `volatile`, or
  missing `"memory"` clobber.
* **A register you set before the asm is gone** — that register is in
  `GR8` / `GR16` and the asm clobbered it without saying so. Add it to
  the clobber list, or pin the value via a register-asm variable so the
  allocator picks a different register.
* **`call` inside asm corrupts caller state** — V6CLANG has empty
  `getCallPreservedMask`, so a manual `call` clobbers everything not
  pinned. Either list every used register in clobbers, or wrap the call
  with a small `noinline` C function so IPRA can compute the real set.
* **Operand evaluated multiple times** — operand expressions can be
  duplicated when the same `%N` appears more than once in the template.
  This is C-level evaluation, not run-time: side-effecting C expressions
  inside operand parens are still evaluated exactly once.

## 9. Quick reference card

```
asm [volatile] ( "template"
                 : "<mods><letter>"(c_lvalue), ...    // outputs
                 : "<letter>"(c_rvalue), ...          // inputs
                 : "regname", "memory", "FLAGS" );    // clobbers
```

V6CLANG constraint letters: `r` (any GPR) · `a` (A only) · `p` (16-bit pair) ·
`I` (u8 imm) · `J` (u16 imm).

Modifiers: `=` write-only · `+` read-write · `&` early-clobber.

Pin a C variable to a physical reg:
```c
register T name asm("REG") [= init];
```

Always-volatile cases: I/O, control flow, hidden memory access, basic asm.

Always-`"memory"` cases: asm writes/reads memory not in operand list, or
calls anything that might.

## 10. See also

* [V6ClangRuntimeAndInlineAsm.md](V6ClangRuntimeAndInlineAsm.md) — runtime helper
  pattern, IPRA interaction, `annotate("v6clang-rt-helper")` suppression.
* [V6ClangCallingConvention.md](V6ClangCallingConvention.md) — default CC details
  for plain `call`s out of inline asm.
* [V6ClangArchitecture.md](V6ClangArchitecture.md) — register classes and the
  i8080 instruction set V6CLANG targets.
* GCC manual, *Extended Asm* chapter — authoritative syntax reference for
  everything not V6CLANG-specific.
