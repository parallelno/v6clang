# V6CLANG Calling Convention

## Overview

The V6CLANG calling convention (`V6CLANG_CConv`) is designed for the extreme register scarcity of the Intel 8080/KR580VM80A. With only 7 general-purpose 8-bit registers (A, B, C, D, E, H, L) and 3 register pairs (BC, DE, HL), every register is caller-saved.

## Argument Passing

Arguments are assigned through two parallel free-lists that are kept in sync.
The lists hold the preferred order in which the next 8-bit or 16-bit
argument should land:

```
FreeI8  : { A, B, C, D, E, L, H }
FreeI16 : { HL, DE, BC }
```

Allocation rules:

- **Take an i8.** Pick the head of `FreeI8`; remove it. If the picked register
  belongs to a 16-bit pair, also remove that pair from `FreeI16`. Mapping:
  `H,L → HL`, `D,E → DE`, `B,C → BC`. `A` is paired-free.
- **Take an i16.** Pick the head of `FreeI16`; remove it, and remove both of
  its 8-bit halves from `FreeI8`.
- **Exhaustion.** When the relevant list is empty for a given argument, the
  argument spills to the stack (right-to-left push, caller cleans).

This lets i8 and i16 arguments interleave freely without ever assigning the
same physical register to two values.

### Examples

| Signature                          | Register assignment      |
|-----------------------------------:|:-------------------------|
| `(i8)`                             | A                        |
| `(i8, i8)`                         | A, B                     |
| `(i8, i8, i8)`                     | A, B, C                  |
| `(i16)`                            | HL                       |
| `(i16, i16, i16)`                  | HL, DE, BC               |
| `(i8, i8, i8, i16, i16)`           | A, B, C, HL, DE          |
| `(i16, i16, i8, i16)`              | HL, DE, A, BC            |
| `(i8, i16, i8, i16)`               | A, HL, B, DE             |
| `(i16, i16, i8, i8)`               | HL, DE, A, B             |
| `(i8 × 8)`                         | A, B, C, D, E, L, H, stk |

```c
void f(uint8_t a);           // a → A
void g(uint16_t p);          // p → HL
void h(uint8_t a, uint8_t b); // a → A, b → B
void k(uint16_t x, uint16_t y, uint16_t z); // x → HL, y → DE, z → BC
```

The free-list order — `A, B, C, D, E, L, H` for i8 and `HL, DE, BC` for i16 —
is chosen so that early arguments land on the cheapest hardware operands
(A for ALU, HL for indirect addressing) before consuming the more
expensive `BC` pair / `H,L` halves.

## Return Values

| Type | Register(s) |
|------|-------------|
| `i8` | `A` |
| `i16` | `HL` |
| `i32` | `DE:HL` (DE = high 16 bits, HL = low 16 bits) |
| Struct (>4B) | `sret` pointer in `HL` |

## Callee-Saved Registers

**None.** All registers are caller-saved. With only 7 GPRs, callee-save obligations would force excessive spilling. Leaf functions benefit from full register availability; the call-graph optimizer can inline aggressively.

At optimized levels, V6CLANG also enables LLVM IPRA by default. This does **not**
change the ABI: registers remain caller-saved at the calling-convention level.
It only allows the compiler to prove that a particular direct callee leaves a
subset of caller-saved registers untouched, reducing spill/reload traffic at
that specific call site.

## Stack Frame Layout

```
High addresses
  ┌──────────────────┐
  │  Arg N (caller)  │   ← Pushed right-to-left
  │  ...             │
  │  Arg 4 (caller)  │
  │  Return Address  │   ← CALL pushes 16-bit PC
  │  [Saved regs]    │   ← Optional (if convention overridden)
  │  Local var 1     │
  │  Local var 2     │
  │  ...             │
  │  [Spill slots]   │
  └──────────────────┘
Low addresses          ← SP points here
```

## Prologue / Epilogue

**Prologue** (allocate N bytes of stack):
```asm
  LXI  H, -N       ; 12cc — load negative frame size
  DAD  SP           ; 12cc — HL = SP - N
  SPHL              ;  8cc — SP = HL
```

**Epilogue** (deallocate and return):
```asm
  LXI  H, N        ; 12cc — load frame size
  DAD  SP           ; 12cc — HL = SP + N
  SPHL              ;  8cc — SP = HL
  RET               ; 12cc
```

Leaf functions with no local variables omit the prologue/epilogue entirely (shrink-wrapping).

## Frame Pointer

The 8080 has no dedicated frame pointer register. By default, frame pointers are **omitted** at all optimization levels — the V6CLANG target returns `false` from `useFramePointerForTargetByDefault()` in `CommonArgs.cpp`, matching other register-constrained targets (xcore, wasm, msp430). For functions requiring a frame pointer (e.g., `alloca`, variable-length arrays, or `-fno-omit-frame-pointer`), `BC` is reserved as the frame pointer. This reduces allocatable register pairs from 3 to 2.

## Stack Slot Access

Accessing a stack slot at offset N from SP costs 32 cycles:
```asm
  LXI  H, N        ; 12cc — load offset
  DAD  SP           ; 12cc — HL = SP + N
  MOV  A, M         ;  8cc — load byte from [HL]
```

This high cost motivates aggressive register allocation, rematerialization (MVIr/LXI at 8–12cc vs 64cc+ spill round-trip), and the accumulator planning optimization pass.

## Implementation

- Return value assignment: `V6ClangCallingConv.td` (`RetCC_V6Clang`)
- Argument passing: `V6ClangISelLowering.cpp` (`V6ClangArgAllocator`, `LowerFormalArguments`, `LowerCall`) — implemented in C++ since the free-list allocator depends on per-call type ordering rather than fixed positions
- Frame lowering: `V6ClangFrameLowering.cpp`
