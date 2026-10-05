# O9. Inline Assembly Completion (MC Asm Parser)

## Rejected
Already implemented `plan_asm_interop_overhaul.md`.

## Problem

Inline assembly (`asm()` / `__asm__`) works at the LLVM IR level — constraint
resolution (`getConstraintType`, `getRegForInlineAsmConstraint`) is implemented
and `-emit-llvm` verifies it. However, **assembly emission fails** because V6CLANG
has no MC asm parser. The error is:

> "Inline asm not supported by this streamer because we don't have an asm
> parser for this target"

## Implementation

Implement a V6CLANG MC asm parser that:
1. Parses 8080 mnemonics (`MOV`, `LXI`, `ADD`, etc.) from inline asm strings
2. Converts them to `MCInst` objects
3. Integrates with `AsmPrinter` for inline asm directive emission

This is essentially a mini-assembler within the MC layer.

**Reference**: [inline_assembly.md](inline_assembly.md)

## Benefit

- Enables inline 8080 assembly in C code for timing-critical sequences,
  I/O port handling, and custom instruction patterns
- Required for porting existing 8080 assembly libraries to the V6CLANG C toolchain

## Complexity

High. An MC asm parser is a milestone-scale effort: lexer, parser, operand
matching, encoding, directive handling. Comparable to M3 (MC layer) in
original plan scope.

## Risk

Low (isolated). The parser is a new component with no impact on existing
codegen. Failures are compile-time errors, not silent miscompilation.
