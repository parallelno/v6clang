# V6CLANG Static Stack Allocation (O10)

Static stack allocation replaces the dynamic stack frame of non-reentrant
functions with a statically-allocated global memory region in BSS.

On the Intel 8080, accessing a stack slot requires computing the address at
runtime (`LXI HL, offset; DAD SP` — 24cc, 4B). With static allocation, the
address is a link-time constant and can be accessed directly via `SHLD`/`LHLD`
(20cc, 3B) or `STA`/`LDA` (16cc, 3B). The stack frame prologue and epilogue
are eliminated entirely.

## Motivation

The 8080 has no indexed addressing. Every stack-relative access must compute
`SP + offset` into HL, which clobbers a register pair and costs 24+ cycles.
A function with 4 spill slots across 3 calls can spend **100+ cycles** just on
address computation for the stack frame.

The c8080 compiler already uses static allocation for all local variables by
default (since non-reentrant code is the norm on 8-bit platforms). O10 brings
this optimization to v6clang, but with safety analysis to preserve correctness
for reentrant and interrupt-driven code.

## Usage

Static stack is **enabled by default**. To disable:

```sh
# via Clang
clang --target=i8080-unknown-v6clang -O2 -mllvm -mv6clang-no-static-stack -S file.c

# via llc
llc -march=v6clang -O2 -mv6clang-no-static-stack < file.ll
```

When disabled, no analysis runs and all functions use the normal SP-relative
frame.

## Eligibility Criteria

A function qualifies for static allocation only when all five conditions hold:

### 1. `leaf` attribute on external declarations

When a function calls an external function whose body is not visible, LLVM
assume the extern could theoretically call back into the translation unit causing
staticly allocated function fail.
Marking the external function declaration `__attribute__((leaf))` tells the
compiler it does not call back, allowing LLVM to infer `norecurse` on the caller
and enable static stack allocation.

```c
// Without leaf, callers of uart_write use dynamic stack frames.
__attribute__((leaf))
extern void uart_write(unsigned char c);
```

Functions whose callees all have visible bodies (defined in the same `.c`
file) do not need this — LLVM infers `norecurse` automatically.

### 2. Not an interrupt handler

The function must **not** have the `"interrupt"` attribute. Interrupt handlers
are invoked asynchronously by hardware — if their frame were static, a nested
interrupt (or a re-trigger after EI) could corrupt it.

### 3. Not reachable from any interrupt handler

Even if a function is not an interrupt handler itself, it can be **called from
one** (directly or transitively). Consider:

```
main() → foo() → bar()
                   ↑
ISR()  → helper() ─┘
```

Here `bar()` is `norecurse` and is not an ISR, but it IS reachable from `ISR`
through `helper`. If `main` is in the middle of `bar()` and the interrupt
fires, `ISR → helper → bar` would re-enter `bar` — corrupting the static
frame.

The pass computes this with a **module-wide BFS** starting from every function
with the `"interrupt"` attribute. All functions discovered by the BFS are
marked as interrupt-reachable and excluded from static allocation.

### 4. Address not taken

If a function's address is taken (`&func` in C), it could be stored in a
function pointer and called from interrupt context in a way the compiler
cannot see. Such functions are excluded conservatively.

### 5. Has frame objects

The function must have at least one non-fixed, non-dead frame object (local
variables or spill slots). Functions that don't need a stack frame gain
nothing from this optimization.

## The `interrupt` Attribute

The V6CLANG backend recognizes the standard LLVM `"interrupt"` function attribute
to identify interrupt service routines (ISRs). In C, mark a function as an
ISR using `__attribute__((interrupt))`:

```c
// Declare a function as an interrupt handler.
// The compiler will:
//   - Exclude it from static stack allocation (criterion 2)
//   - Exclude all its direct/transitive callees (criterion 3)
//   - Skip SP-trick optimization inside it (V6ClangSPTrickOpt)
__attribute__((interrupt))
void timer_isr(void) {
    // Handle timer tick
    tick_count++;
}
```

### How the compiler uses it

The `"interrupt"` attribute affects two optimization passes:

1. **V6ClangStaticStackAlloc** — The pass scans every function in the module.
   Any function with `hasFnAttribute("interrupt")` becomes a BFS seed. The
   BFS then walks the call graph (via `CallBase` instructions) to find all
   transitively reachable callees. Both the ISR itself and every reachable
   callee are excluded from static allocation.

2. **V6ClangSPTrickOpt** — The SP-trick (repurpose SP as a fast read pointer)
   is disabled inside ISR functions because SP manipulation inside an ISR
   would corrupt the interrupt return stack.

### Examples

```c
// Helper called from both normal code and ISR.
// Will be detected as interrupt-reachable via BFS → no static stack.
void update_counter(void) {
    counter++;
}

__attribute__((interrupt))
void vsync_isr(void) {
    update_counter();   // BFS reaches update_counter from here
}

void main_loop(void) {
    update_counter();   // Same function, also called from main
    // ...
}
```

```c
// A leaf function only called from main — never from any ISR.
// Will get static stack if it has spills (enabled by default).
__attribute__((noinline))
int compute(int a, int b, int c) {
    int x = a + 1;
    int y = b + 2;
    int z = c + 3;
    use_val(x);         // y, z must survive → spill slots
    use_val(y);
    use_val(z);
    return x + y + z;
}
```

### What the compiler does NOT do (yet)

The V6CLANG backend does **not** currently generate special ISR prologue/epilogue
sequences (save all registers, return via `EI; RET`). The `"interrupt"`
attribute is currently used only as a **safety marker** for optimization
decisions. ISR entry/exit code should be written in inline assembly or a
separate `.asm` file for now.

### Why `norecurse` alone is not enough

A concrete example of the re-entrance problem:

```c
__attribute__((noinline))
void foo(void) {
    int local = get_val();  // spill slot allocated
    use_val(local + 1);
}

__attribute__((interrupt))
void timer_isr(void) {
    foo();                  // Re-enters foo while main's call is suspended!
}

void main(void) {
    foo();                  // foo is executing here...
    // Timer interrupt fires mid-execution of foo
    // ISR calls foo again → static frame corrupted
}
```

`foo()` is `norecurse` (it doesn't call itself), but it IS reentrant because
the ISR can invoke it while `main`'s invocation is suspended on the stack.
Without the BFS analysis from ISRs, a naïve implementation would assign a
static frame to `foo` and produce silent data corruption.

## norecurse Inference

For LLVM to infer `norecurse` at `-O2`, the `PostOrderFunctionAttrs` pass
must see the bodies of all callees. This requires:

- **Single translation unit:** All called functions defined in the same `.c`
  file, or
- **LTO (Link-Time Optimization):** `-flto` merges all translation units
  before the attribute inference pass runs

External function declarations (without bodies) block `norecurse` inference
for all their callers. Workarounds:

```c
// Option 1: Provide visible bodies (noinline prevents unwanted inlining)
__attribute__((noinline))
void helper(int x) { /* body visible */ }

// Option 2: Mark extern declarations as leaf (preferred)
__attribute__((leaf))
extern void external_helper(int x);

// Option 3: Use LTO
// clang -flto --target=i8080-unknown-v6clang -O2 file1.c file2.c -o out
```
## Pass Architecture

### Pipeline position

`V6ClangStaticStackAlloc` runs in `addPostRegAlloc()` — after register allocation
(which determines spill slot count and layout) but before PrologEpilogInserter
(which would emit SP-adjustment code for the frame).

### Per-function global variables

Each eligible function gets its own BSS symbol:

```
@__v6clang_ss.heavy_spill = internal global [4 x i8] zeroinitializer
@__v6clang_ss.compute     = internal global [6 x i8] zeroinitializer
```

The symbol name is `__v6clang_ss.<function_name>`, sized to exactly the function's
frame size. Frame indices are mapped to byte offsets within this region via
`V6ClangMachineFunctionInfo::addStaticSlot()`.

### Frame elimination

When `eliminateFrameIndex` encounters a spill/reload pseudo-instruction and
the function has static stack info, it emits direct memory access instead of
SP-relative computation:

| Pseudo | Register | Static expansion | Cycles | Bytes |
|--------|----------|-----------------|--------|-------|
| `V6CLANG_SPILL16` | HL | `SHLD addr` | 20 | 3 |
| `V6CLANG_SPILL16` | DE | `XCHG; SHLD addr; XCHG` | 28 | 5 |
| `V6CLANG_SPILL16` | BC | `PUSH HL; LXI HL, addr; MOV M,C; INX HL; MOV M,B; POP HL` | 68 | 7 |
| `V6CLANG_RELOAD16` | HL | `LHLD addr` | 20 | 3 |
| `V6CLANG_RELOAD16` | DE | `XCHG; LHLD addr; XCHG` | 28 | 5 |
| `V6CLANG_RELOAD16` | BC | `PUSH HL; LXI HL, addr; MOV C,M; INX HL; MOV B,M; POP HL` | 68 | 7 |
| `V6CLANG_SPILL8` | A | `STA addr` | 16 | 3 |
| `V6CLANG_RELOAD8` | A | `LDA addr` | 16 | 3 |
| `V6CLANG_LEA_FI` | HL | `LXI HL, addr` | 12 | 3 |

Compare with SP-relative for a non-HL 16-bit spill (worst case):
`PUSH HL; LXI HL, off; DAD SP; MOV M,r; INX HL; MOV M,r; POP HL` = **76cc, 9B**

Static HL spill: **20cc, 3B** — saves **56cc and 6B per operation**.

## Performance Results

From the feature test ([tests/features/21/](../tests/features/21/)):

### `heavy_spill(int a, int b)` — 3 values live across 3 calls

| Metric | c8080 | v6clang baseline | v6clang + O10 |
|--------|-------|-----------------|---------------|
| Cycles | 436 | 768 | **364** |
| Bytes | 62 | 102 | **49** |

- vs baseline: **−404cc (−53%), −53B (−52%)**
- vs c8080: **−72cc (−17%), −13B (−21%)**

### Whole-program totals

| Compiler | Cycles | Bytes |
|----------|--------|-------|
| c8080 | 1128 | 159 |
| v6clang baseline | 1354 | 187 |
| v6clang + O10 | **950** | **134** |

## Related

- [V6ClangOptimization.md](V6ClangOptimization.md) — All optimization passes overview
- [V6ClangIPRA.md](V6ClangIPRA.md) — IPRA reduces spill count, complementing O10
- [Feature test](../tests/features/21/) — Source, assembly, and result.txt
- [Lit test](../tests/lit/CodeGen/V6CLANG/static-stack-alloc.ll) — Automated regression test (mirror; source in `llvm-project/llvm/test/CodeGen/V6CLANG/`)
- [Implementation plan](../design/plan_static_stack_allocation.md) — Step-by-step plan
