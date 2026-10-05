# V6CLANG IPRA

Interprocedural Register Allocation (IPRA) is an LLVM code generation feature
that narrows call-site clobber information based on the real register usage of
direct callees.

For the V6CLANG target, IPRA is especially valuable because the Intel 8080 has a
very small register file and call-related spills are expensive.

## Status

IPRA is **enabled by default** for the V6CLANG target at optimized levels.

The target machine explicitly opts in with:

```cpp
bool useIPRA() const override { return true; }
```

This default does **not** change the V6CLANG calling convention. Registers are
still caller-saved at the ABI level. IPRA only allows LLVM to prove that a
specific direct callee leaves some caller-saved registers untouched.

## Why It Matters on V6CLANG

Without IPRA, ordinary `CALL` sites are treated conservatively and live values
often get spilled before the call and reloaded after it.

With IPRA, LLVM can narrow the preserved-register mask for direct calls whose
callee bodies are known. On V6CLANG this often removes:

- temporary stack-frame setup used only to preserve live registers across calls
- spill / reload sequences around small leaf callees
- extra register shuffling needed solely for those spills

This is particularly effective for small helper functions like:

```c
volatile int sink;

__attribute__((noinline))
void action_a(void) { sink = 1; }

__attribute__((noinline))
void action_b(void) { sink = 2; }
```

where the callee really only touches `HL`, but the caller might otherwise have
to spill a live value held in `DE`.

## How It Works on V6CLANG

V6CLANG uses two layers of call clobber information:

1. The call-preserved register mask from `getCallPreservedMask()`.
2. Instruction-level implicit defs on `CALL`.

IPRA can refine the first layer, but not the second one. For IPRA to be useful,
the ordinary `CALL` instruction definition must not hard-code broad register
clobbers. V6CLANG therefore models `CALL` with `Defs = [SP]` and uses the register
mask as the authoritative source of clobber information.

At a high level:

1. LLVM compiles callees and records which physical registers they really use.
2. At direct call sites, LLVM propagates that information into the call's
   preserved-register mask.
3. Register allocation uses the narrowed mask to decide which live values can
   stay in registers across the call.

## When It Helps

IPRA is most effective when:

- the callee body is visible during code generation
- the call is direct, not indirect
- the callee is small and uses only a subset of registers
- the caller is under high register pressure

For V6CLANG this is a strong fit because many programs are built as small,
single-translation-unit, statically linked binaries.

## When It Does Not Help

IPRA has limited or no effect for:

- external library calls whose bodies are unavailable
- indirect calls through function pointers
- recursive SCCs where LLVM must stay conservative
- separately compiled units without whole-program visibility

In these cases V6CLANG still falls back to conservative behavior.

## Safety Model

IPRA on V6CLANG is intentionally safe by default:

- `getCallPreservedMask()` still returns the conservative all-zero mask as the
  default behavior
- unknown calls therefore still behave as full clobbers
- only direct calls with proven callee usage get narrower preserved masks

So enabling IPRA by default improves precision where possible without relaxing
correctness for unknown cases.

## Disabling IPRA

Although IPRA is enabled by default for V6CLANG, it can still be disabled for
debugging, regression bisection, or comparison runs.

### Disable from Clang

```text
clang -target i8080-unknown-v6clang -O2 -mllvm -enable-ipra=false file.c -S -o file.asm
```

### Enable explicitly from Clang

```text
clang -target i8080-unknown-v6clang -O2 -mllvm -enable-ipra file.c -S -o file.asm
```

This is usually unnecessary because V6CLANG already enables it by default.

### Disable from llc

```text
llc -march=v6clang -O2 -enable-ipra=false input.ll -o output.asm
```

### Enable explicitly from llc

```text
llc -march=v6clang -O2 -enable-ipra input.ll -o output.asm
```

## Practical Guidance

- Leave IPRA enabled for normal V6CLANG builds.
- Disable it only when isolating regressions or comparing pre-IPRA behavior.
- If a future codegen bug appears around calls, verify that every ordinary
  `CALL` still carries a register mask through instruction selection.

## Related Documents

- [V6ClangCallingConvention.md](V6ClangCallingConvention.md)
- [V6ClangOptimization.md](V6ClangOptimization.md)
- [V6ClangBuildGuide.md](V6ClangBuildGuide.md)
- [O39 Design](../design/future_plans/O39_ipra_integration.md)
