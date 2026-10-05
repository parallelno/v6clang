# Vector 06c LLVM Backend — Design Document

## 1. Project Overview

This document defines the high-level architecture for `llvm-v6clang`, a custom LLVM backend targeting the Vector 06c home computer, which uses an Intel 8080-compatible 8-bit CPU with a 64 KB flat memory model. The backend transforms LLVM IR into native 8080 machine code with Vector 06c-specific instruction timing.

### 1.1 Goals

| Goal | Description |
|------|-------------|
| Correctness | Produce correct 8080 machine code for all supported C constructs |
| Efficiency | Exploit the Vector 06c cost model to minimize total cycle count |
| Modularity | Clean separation between target description, lowering, scheduling, and emission |
| Testability | Every layer independently testable via LLVM's `lit` / `FileCheck` infrastructure |
| Configurability | Arbitrary start address within 0x0000–0xFFFF; selectable calling conventions |

### 1.2 Implementation Technologies

LLVM's backend infrastructure is written in C++ and exposes only C++ APIs; all existing backends (X86, ARM, AVR, etc.) follow the same technology stack. This project adopts the same, with no practical alternatives:

| Language | Scope |
|----------|-------|
| **C++17** | Backend, Clang integration, linker — subclasses LLVM/Clang/LLD C++ base classes |
| **TableGen** | Register, instruction, scheduling, and calling convention descriptions (LLVM's declarative DSL) |
| **8080 Assembly** | Runtime library (`crt0`, math, shift, memory) — hand-optimized for cycle counting |
| **LLVM IR** + **lit/FileCheck** | Compiler pipeline tests |
| **C** | Integration tests, standalone unit tests |
| **CMake / Ninja** | Build system (standard LLVM) |

### 1.3 Non-Goals

- Floating-point support in hardware (software emulation library only, if needed).
- Full C11/C17 standard library — only freestanding subset.
- Support for CPUs beyond the 8080 instruction set (no Z80 extensions).

---

## 2. Target Machine Model

### 2.1 Target Triple

```
i8080-unknown-v6clang
```

Components:
- **Arch**: `i8080`
- **Vendor**: `unknown`
- **OS**: `v6clang` (bare-metal Vector 06c runtime)

### 2.2 Data Layout String

```
e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8
```

| Property | Value | Rationale |
|----------|-------|-----------|
| Endianness | Little-endian (`e`) | 8080 stores 16-bit values low-byte-first |
| Pointer size | 16 bits | 64 KB flat address space |
| Pointer alignment | 8 bits | No alignment requirements in hardware |
| Native integer widths | 8, 16 (`n8:16`) | 8-bit ALU, 16-bit register pairs |
| Stack alignment | 8 bits (`S8`) | Stack is byte-addressable |
| Integer alignments | All 8-bit aligned | No alignment penalties on 8080 |

### 2.3 Type Mapping

| C Type | LLVM Type | Width | Notes |
|--------|-----------|-------|-------|
| `_Bool` / `bool` | `i1` (stored as `i8`) | 8b | Zero or one |
| `char` | `i8` | 8b | Unsigned by default (8080 convention) |
| `short` | `i16` | 16b | |
| `int` | `i16` | 16b | Matches pointer width |
| `long` | `i32` | 32b | Synthesized via register pair sequences |
| `long long` | Unsupported | — | Too expensive; reject or warn at frontend |
| pointer | `i16` | 16b | Flat 64 KB |
| `size_t` | `i16` | 16b | |

---

## 3. Register Architecture

### 3.1 Physical Registers

```
  8-bit GPRs:   A   B   C   D   E   H   L
  16-bit Pairs:  BC (B:C)   DE (D:E)   HL (H:L)   SP   PSW (A:Flags)
  Implicit:      PC, Flags (Z, S, P, CY, AC)
```

### 3.2 Register Classes (TableGen)

| Class | Members | Purpose |
|-------|---------|---------|
| `GR8` | A, B, C, D, E, H, L | General 8-bit operands |
| `GR8NoA` | B, C, D, E, H, L | Destinations for non-accumulator ops |
| `Acc` | A | Singleton — accumulator-only ops |
| `GR16` | BC, DE, HL | General 16-bit operands |
| `GR16Ptr` | HL | Memory pointer (M operand) |
| `GR16Idx` | BC, DE | LDAX/STAX pointer pairs |
| `GR16SP` | SP | Stack pointer |
| `GR16All` | BC, DE, HL, SP | PUSH/POP, LXI, INX, DCX, DAD |
| `FlagReg` | FLAGS | Implicit def/use on ALU/compare |

### 3.3 Sub-Register Relationships

```
BC -> { B (sub_hi), C (sub_lo) }
DE -> { D (sub_hi), E (sub_lo) }
HL -> { H (sub_hi), L (sub_lo) }
PSW -> { A (sub_hi), FLAGS (sub_lo) }
```

These sub-register indices enable the register allocator to split/coalesce 8-bit and 16-bit live ranges.

### 3.4 Register Allocation Constraints

- **Accumulator bottleneck**: All ALU binary operations read/write `A`. The register allocator must model `A` as an implicit operand.
- **HL as pointer**: Memory operands `(M)` require the address in `HL`. Any instruction referencing memory implicitly uses `HL`.
- **Reserved registers**: `SP` is reserved for the frame/stack pointer. `PC` is not modeled as allocatable.
- **Allocation order**: `A, L, H, E, D, C, B` — favor registers involved in the cheapest operations first.

---

## 4. Instruction Description Layer

### 4.1 TableGen Organization

```
llvm/lib/Target/V6Clang/
  V6Clang.td                    # Top-level target description
  V6ClangRegisterInfo.td         # Register classes & sub-registers (§3)
  V6ClangInstrInfo.td            # Instruction definitions (§4.2)
  V6ClangInstrFormats.td         # Encoding formats (§4.3)
  V6ClangSchedule.td             # Scheduling model & costs (§4.4)
  V6ClangCallingConv.td          # Calling conventions (§6)
```

### 4.2 Instruction Modeling

Each 8080 instruction is described as a TableGen `Instruction` record with:

- **Encoding** — opcode byte(s) + operand bytes.
- **Operand list** — register class constraints, immediates, addresses.
- **Implicit defs/uses** — e.g., all ALU ops implicitly define `FLAGS`, accumulator ops implicitly use/def `A`.
- **Scheduling info** — cycle cost from the Vector 06c timing table.
- **Pattern** — optional SelectionDAG pattern for direct ISel matching.

#### Instruction categories

| Category | Example Instructions | Key Modeling Notes |
|----------|---------------------|--------------------|
| Data Move | MOV, MVI, LDA, STA, LDAX, STAX, LXI, LHLD, SHLD | MOV r,r costs 8cc — *not* free. MVI r,n also 8cc. |
| Stack | PUSH, POP, SPHL, XTHL | PUSH 16cc, POP 12cc. Model SP side effects. |
| ALU 8-bit | ADD, SUB, ADC, SBB, ANA, ORA, XRA, CMP | 4cc register, 8cc memory/immediate. Implicit A. |
| ALU 16-bit | DAD, INX, DCX | DAD 12cc, INX/DCX 8cc. DAD only adds to HL. |
| Increment | INR, DCR | 8cc register, 12cc memory. Sets flags except CY. |
| Rotate | RLC, RRC, RAL, RAR | 4cc. Operate on A only. Modify CY. |
| Branch | JMP, Jcc, CALL, Ccc, RET, Rcc, RST, PCHL | Conditional cost differs taken/not-taken. |
| Misc | NOP, HLT, EI, DI, CMC, STC, CMA, DAA, XCHG | XCHG 4cc — model as zero-cost rename where possible. |
| I/O | IN, OUT | 12cc. Intrinsic interface. |

### 4.3 Encoding Formats

The 8080 uses a fixed single-byte opcode with 0, 1, or 2 operand bytes:

| Format | Size | Structure | Examples |
|--------|------|-----------|----------|
| `Implied` | 1 | `[opcode]` | NOP, RET, XCHG, CMA |
| `Reg` | 1 | `[opcode+reg_field]` | MOV r,r, ADD r, INR r |
| `Imm8` | 2 | `[opcode][d8]` | MVI r,n, ADI n, CPI n |
| `Imm16` | 3 | `[opcode][lo][hi]` | LXI rp,nn, JMP addr, CALL addr |
| `Direct` | 3 | `[opcode][lo][hi]` | LDA addr, STA addr, LHLD, SHLD |
| `RST` | 1 | `[opcode+n]` | RST 0–7 |
| `IO` | 2 | `[opcode][port]` | IN port, OUT port |

### 4.4 Scheduling Model (Vector 06c Timings)

The scheduling model uses an `SchedMachineModel` with a single-issue, in-order pipeline (the 8080 has no pipelining, no out-of-order execution):

```
MicroOpBufferSize = 0      // Strictly in-order
IssueWidth        = 1      // One instruction at a time
LoadLatency       = 2      // Model memory access latency in "cost units"
```

Each instruction class maps to a `SchedWriteRes` with its cycle cost. The cost table directly encodes Vector 06c timings from the specification (§ prompt).

**Cost-model highlights the optimizer must exploit:**

| Observation | Implication |
|-------------|-------------|
| ALU r-r is 4cc, MOV r,r is 8cc | Avoid unnecessary register shuffles; prefer recomputation over move chains |
| XCHG is 4cc | Use XCHG to swap DE↔HL essentially for free |
| ORA A (4cc) vs CPI 0 (8cc) | Peephole: replace `CPI 0` with `ORA A` for zero-test |
| PUSH 16cc, POP 12cc | SP-based block copy is 28cc/2B — competitive with MOV chains for memcpy |
| LDA/STA 16cc vs MOV r,M 8cc | Prefer HL-indirect over direct addressing when HL is available |
| DAD rp 12cc | Cheap 16-bit addition; use for pointer arithmetic |
| Conditional branch taken/not-taken differ | Branch prediction hints for scheduling |

---

## 5. Instruction Selection & Lowering

### 5.1 Architecture

```
                        ┌──────────────┐
   LLVM IR  ──────────► │  Legalization │  (type & operation legalization)
                        └──────┬───────┘
                               │
                        ┌──────▼───────┐
                        │  DAG Combine  │  (target-independent + target combines)
                        └──────┬───────┘
                               │
                        ┌──────▼───────────┐
                        │  ISel (TableGen  │  (pattern-matched instruction selection)
                        │   + Custom C++)  │
                        └──────┬───────────┘
                               │
                        ┌──────▼───────┐
                        │  Post-ISel    │  (peephole, scheduling)
                        └──────┬───────┘
                               │
                        ┌──────▼───────┐
                        │  RegAlloc     │  (greedy allocator + V6CLANG constraints)
                        └──────┬───────┘
                               │
                        ┌──────▼─────────────┐
                        │  Post-RA Passes    │  (frame lowering, prologue/epilogue)
                        └──────┬─────────────┘
                               │
                        ┌──────▼───────┐
                        │  MC Emission  │  (binary / assembly)
                        └──────────────┘
```

### 5.2 Type Legalization Strategy

| LLVM Type | Strategy | Lowered To |
|-----------|----------|------------|
| `i1` | Promote | `i8` (in register) |
| `i8` | Legal | Native `GR8` |
| `i16` | Legal | Native `GR16` / pair of `GR8` |
| `i32` | Expand | Pair of `i16` (4 × `GR8`) |
| `i64` | Expand | Four `i16` values (if supported) |
| `f32`, `f64` | SoftFloat / LibCall | Runtime library |
| `ptr` | Legal | `i16` |
| Vectors | Scalarize | Not natively supported |

### 5.3 Operation Legalization

Key operations and their lowering:

| Operation | Strategy | Notes |
|-----------|----------|-------|
| `add i8` | Legal | `ADD r` / `ADI` |
| `add i16` | Custom | `DAD` (only HL += rp), otherwise expand to 8-bit chain with carry |
| `sub i16` | Expand | 8-bit SUB+SBB chain |
| `mul` | LibCall | No hardware multiply |
| `sdiv`, `udiv` | LibCall | No hardware divide |
| `srem`, `urem` | LibCall | No hardware remainder |
| `shl`, `lshr`, `ashr` | Custom | Unrolled rotate/shift sequences; shift-by-1 uses RLC/RRC/RAL/RAR |
| `and`, `or`, `xor` | Legal (i8) | `ANA`, `ORA`, `XRA`; i16 expanded |
| `icmp` + `br` | Custom | Fused compare-and-branch using CMP + Jcc |
| `select` | Expand | Branch sequence |
| `frame_index` | Custom | Materialize SP-relative address into HL |
| `GlobalAddress` | Custom | LXI with relocated address |
| `call` | Custom | CALL with ABI lowering |
| `ret` | Custom | RET with result register placement |
| `load` / `store` | Custom | Requires HL setup or LDA/STA for direct addressing |
| `memcpy` | LibCall / Inline | Small: inline MOV chain or SP-trick; large: library |
| `byval` / `sret` | Custom | Struct pass-by-value via stack copy |

### 5.4 Custom DAG Combines

| Pattern | Combine To | Rationale |
|---------|-----------|-----------|
| `(store (load [addr1]) [addr2])` | MOV sequence or PUSH/POP | Avoid A bottleneck |
| `(xor HL, DE)` → swap meaning | `XCHG` | 4cc instead of multi-MOV |
| `(add HL, rp)` | `DAD rp` | Direct 12cc 16-bit add |
| `(icmp eq X, 0)` | `ORA A` (if X in A) | 4cc vs 8cc for CPI 0 |
| `(shl X, 1)` | `ADD A,A` or `DAD HL` | 4cc doubling |
| `(load (frameindex))` near SP | SP-relative via HL computation | Minimize direct-address usage |

### 5.5 Pseudo-Instructions

Pseudo-instructions that expand during or after register allocation:

| Pseudo | Expansion | Purpose |
|--------|-----------|---------|
| `V6CLANG_MOV16rr` | Two `MOV` (hi, lo) | 16-bit register-pair move |
| `V6CLANG_LOAD16` | `LHLD` / `LXI+MOV+MOV` | 16-bit memory load |
| `V6CLANG_STORE16` | `SHLD` / `MOV+MOV` | 16-bit memory store |
| `V6CLANG_ADD16` | `DAD` / 8-bit expand | 16-bit addition |
| `V6CLANG_SUB16` | 8-bit SUB+SBB chain | 16-bit subtraction |
| `V6CLANG_CMP16` | 8-bit compare chain | 16-bit comparison |
| `V6CLANG_SHIFT_L` | Unrolled `RAL`/`ADD A,A` | Left shift by N |
| `V6CLANG_SHIFT_R` | Unrolled `RAR`/RRC chain | Right shift by N |
| `V6CLANG_CALL_SEQ_START` | SP adjustment | Call frame setup |
| `V6CLANG_CALL_SEQ_END` | SP adjustment | Call frame teardown |
| `V6CLANG_RET_FLAG` | `RET` | Return with glue |
| `V6CLANG_SELECT_CC` | Compare + branch | Conditional select |

---

## 6. Calling Convention & ABI

### 6.1 Primary Calling Convention: `V6CLANG_CConv`

Designed for the extreme register scarcity of the 8080:

**Argument Passing:**

| Argument # | Type | Location | Notes |
|------------|------|----------|-------|
| 1st | i8 | `A` | Accumulator — cheapest access |
| 1st | i16 | `HL` | Primary 16-bit register |
| 2nd | i8/i16 | `DE` | Secondary pair |
| 3rd | i8/i16 | `BC` | Tertiary pair |
| Remaining | any | Stack (R-to-L) | Caller-cleans (cdecl-style) |

**Return Values:**

| Type | Location |
|------|----------|
| `i8` | `A` |
| `i16` | `HL` |
| `i32` | `DE:HL` (DE=high, HL=low) |
| Struct (>4B) | `sret` pointer in `HL` |

**Callee-Saved Registers:** None by default. All registers are caller-saved. Rationale: with only 7 GPRs, callee-save obligations would force excessive spilling. Leaf functions benefit; the call-graph optimizer can inline aggressively.

**Stack Frame Layout:**

```
High addresses
  ┌──────────────────┐
  │  Arg N (caller)  │   ← Pushed right-to-left
  │  ...             │
  │  Arg 4 (caller)  │
  │  Return Address  │   ← CALL pushes 16-bit PC
  │  [Saved regs]    │   ← Optional callee-save (if convention overridden)
  │  Local var 1     │
  │  Local var 2     │
  │  ...             │
  │  [Spill slots]   │
  └──────────────────┘
Low addresses          ← SP points here
```

### 6.2 Alternative Convention: `V6CLANG_FastCall`

All arguments on stack. No register arguments. Simpler for variadic functions and functions called via pointer.

### 6.3 Interrupt Handler Convention: `V6CLANG_ISR`

- All registers saved/restored (PUSH PSW, PUSH B, PUSH D, PUSH H).
- Returns with `EI` + `RET`.
- No arguments or return values.
- Marked via `__attribute__((interrupt))`.

---

## 7. Frame Lowering

### 7.1 Design

The 8080 has no frame pointer register and no base+offset addressing. This makes stack frame access expensive.

**Strategy: SP-relative access via HL computation.**

To access a stack slot at offset `N` from SP:

```asm
; Materialize address:  HL = SP + N
  LXI  H, N          ; 12cc — load offset
  DAD  SP             ; 12cc — HL += SP
; Now [HL] points at the slot
  MOV  A, M           ;  8cc — load byte
```

Cost: 32cc for a single byte load from stack. This is expensive, reinforcing the need for aggressive register allocation and promotion.

### 7.2 Frame Pointer Option

For functions with variable-length arrays or `alloca`, a dedicated frame pointer is required. `BC` is reserved as the frame pointer in this mode, reducing allocatable registers further. Enabled via `-fno-omit-frame-pointer` or automatically when needed.

### 7.3 Prologue / Epilogue

**Prologue (frame setup):**
```asm
; Allocate N bytes of stack:
  LXI  H, -N
  DAD  SP
  SPHL                ; SP = SP - N
```

**Epilogue (frame teardown):**
```asm
; Deallocate N bytes:
  LXI  H, N
  DAD  SP
  SPHL                ; SP = SP + N
  RET
```

For trivial leaf functions with no locals, prologue/epilogue are omitted entirely (shrink-wrapping).

---

## 8. Optimization Strategy

### 8.1 Pass Pipeline

The optimization pipeline is organized in three phases:

```
Phase 1: IR-Level (Target-Independent + V6CLANG-Aware)
  ├── Standard -O2 pipeline (mem2reg, SROA, GVN, licm, etc.)
  ├── V6ClangPromoteToRegisters        — Aggressive alloca promotion
  ├── V6ClangLoopStrengthReduce        — Pointer-increment loops → INX
  └── V6ClangTypeNarrowing             — Narrow i16/i32 to i8 where safe

Phase 2: CodeGen (Pre-RA)
  ├── ISel (§5)
  ├── V6ClangPeephole                  — Pattern-based local optimizations
  ├── V6ClangAccumulatorPlanning       — Schedule A-register usage
  ├── MachineLICM                  — Hoist invariants out of loops
  └── MachineCSE                   — Eliminate redundant computations

Phase 3: CodeGen (Post-RA)
  ├── V6ClangLoadStoreOpt              — Merge adjacent loads/stores
  ├── V6ClangXchgOpt                   — Insert XCHG to avoid MOV chains
  ├── V6ClangBranchOpt                 — Branch relaxation, tail calls
  ├── V6ClangZeroTestOpt               — CPI 0 → ORA A
  └── V6ClangSPTrickOpt                — SP-based block copy for memcpy/memset
```

### 8.2 Custom Optimization Passes

#### 8.2.1 `V6ClangAccumulatorPlanning` (MachineFunction Pass)

*Problem*: Nearly all ALU operations route through register A. Naive scheduling causes excessive MOV-to-A / MOV-from-A traffic.

*Approach*: Analyze data-flow graphs within basic blocks. Reorder instructions to maximize the time a value remains live in A, reducing save/restore moves.

*Interface*:
```
Input:  MachineFunction (post-ISel, pre-RA)
Output: Reordered MachineFunction
Preserved: CFG, liveness (updated)
```

#### 8.2.2 `V6ClangXchgOpt` (MachineFunction Pass)

*Problem*: Many operations need values in HL (for memory access) or DE (for DAD). Moving 16-bit values between pairs costs 2×MOV = 16cc. XCHG costs 4cc.

*Approach*: Post-RA, scan for patterns where swapping DE↔HL via XCHG is cheaper than the emitted MOV pair. Track the "logical" assignment of DE and HL and defer physical assignment, inserting XCHG at boundaries.

*Interface*:
```
Input:  MachineFunction (post-RA)
Output: MachineFunction with XCHG insertions, redundant MOV pairs removed
Preserved: Register liveness (updated)
```

#### 8.2.3 `V6ClangSPTrickOpt` (MachineFunction Pass)

*Problem*: The 8080 has no block-move instruction. Copying N bytes naively requires N×(MOV+MOV) = 16cc/byte.

*Approach*: For aligned 2-byte blocks, use the SP trick:
```asm
; Save SP, point SP at source
  LXI H, 0     ; save old SP
  DAD SP
  XCHG          ; DE = old SP
  LXI SP, src   ; SP = source address
  POP H         ; HL = [src], src += 2   (12cc)
  SHLD dst      ; [dst] = HL             (20cc)
  ; ... repeat, adjusting dst
  XCHG
  SPHL          ; restore SP
```

32cc/2 bytes vs 16cc/byte — beneficial for copies ≥6 bytes. Interrupts must be disabled (DI/EI bracketing).

*Interface*:
```
Input:  MachineFunction with expanded memcpy/memset sequences
Output: MachineFunction with SP-trick sequences where profitable
Constraint: Wraps sequence in DI/EI; not applicable inside ISRs
```

#### 8.2.4 `V6ClangZeroTestOpt` (Peephole, MachineFunction Pass)

Replace `CPI 0` (8cc) with `ORA A` (4cc) when testing the accumulator against zero. Generalized: replace `CMP r` where r is known-zero with `ORA A`.

#### 8.2.5 `V6ClangTypeNarrowing` (IR Pass)

Analyze i16 computations where the upper byte is unused (e.g., loop counters bounded < 256). Narrow to i8 operations, halving register pressure and cycle cost.

### 8.3 Register Allocation Strategy

**Allocator**: LLVM's Greedy Register Allocator with V6CLANG-specific weight adjustments.

**Key customizations:**
- **Spill cost inflation**: Stack access costs ~32cc minimum. Spill weights must reflect this to force the allocator to try harder before spilling.
- **A-register interference**: Model the implicit use of A in ALU operations. The allocator sees these constraints via the instruction descriptions.
- **Pair allocation**: 16-bit values must be allocated to valid register pairs. Use LLVM's register pair / sub-register mechanism to enforce this.
- **Rematerialization**: Prefer rematerializing cheap loads (`MVI r, imm` = 8cc) over spilling/reloading (≥64cc round-trip).
- **Live range splitting**: Aggressively split live ranges to make short intervals fit in the scarce register file.

---

## 9. MC Layer & Code Emission

### 9.1 Assembly Printer

Standard Intel 8080 mnemonics. Output compatible with common 8080 assemblers.

```asm
        ORG  0100H
START:  LXI  SP, 0FFFFH
        CALL _main
        HLT
```

### 9.2 Object Code Emission

Binary output format: **raw flat binary** (`.bin`).

No object file format (no ELF, no COFF). The Vector 06c loads programs as flat memory images. The linker produces a single binary blob loaded at the configured start address.

An optional **Intel HEX** (`.hex`) output is provided for EPROM programmers and emulator compatibility.

### 9.3 Start Address Configuration

Command-line option:

```
-mv6clang-start-address=0x100    (default)
```

Accepted range: `0x0000`–`0xFFFF`. The emitted binary's origin (`ORG`) directive and all absolute address relocations are adjusted accordingly.

### 9.4 Linker

A minimal custom linker (or LLD with a V6CLANG-specific target) that:

- Resolves symbol references across compilation units.
- Lays out sections (`.text`, `.data`, `.rodata`, `.bss`) contiguously starting at the configured origin.
- Produces a flat binary with an optional memory map file.
- Validates total size ≤ 65536 bytes and detects overlaps.

**Memory layout (default):**

```
0x0000 ┌──────────────────┐
       │  (reserved/ROM)  │  Below start address
0x0100 ├──────────────────┤  ← Start address (configurable)
       │  .text           │  Code
       │  .rodata         │  Read-only data
       │  .data           │  Initialized data
       │  .bss            │  Uninitialized data (zero-filled)
       │  (heap ↑)        │  Optional: grows upward
       │       ...        │
       │  (stack ↓)       │  Grows downward from top of RAM
0xFFFF └──────────────────┘
```

---

## 10. Frontend Integration

### 10.1 Approach: Clang with V6CLANG Target

Use Clang as the C frontend. Register `i8080-unknown-v6clang` as a target, providing:

| Clang Component | V6CLANG Implementation |
|-----------------|--------------------|
| `TargetInfo` | Defines type sizes, alignments, endianness, built-in macros |
| `TargetCodeGenInfo` | ABI lowering for function calls |
| Built-in macros | `__V6CLANG__`, `__I8080__`, `__CHAR_UNSIGNED__` |

### 10.2 Language Restrictions

The frontend enforces constraints appropriate for the target:

| Feature | Status | Rationale |
|---------|--------|-----------|
| `long long` (64-bit) | Warning / Error | Prohibitively expensive |
| `float` / `double` | Soft-float only | No FPU; warn about performance |
| Variable-Length Arrays | Supported (with FP) | Requires frame pointer |
| `_Thread_local` | Unsupported | Single-threaded system |
| Inline assembly | Supported | 8080 syntax via `asm()` |
| `volatile` | Supported | Critical for I/O ports |
| Bit-fields | Supported | Lowered to shift/mask sequences |

### 10.3 Built-in Functions / Intrinsics

| Intrinsic | Maps To | Purpose |
|-----------|---------|---------|
| `__builtin_v6clang_in(port)` | `IN port` | Read I/O port |
| `__builtin_v6clang_out(port, val)` | `OUT port` | Write I/O port |
| `__builtin_v6clang_di()` | `DI` | Disable interrupts |
| `__builtin_v6clang_ei()` | `EI` | Enable interrupts |
| `__builtin_v6clang_hlt()` | `HLT` | Halt processor |
| `__builtin_v6clang_nop()` | `NOP` | No-operation |

---

## 11. Runtime Support Library

A minimal freestanding runtime (`libv6clangrt`) provides:

| Component | Contents |
|-----------|----------|
| `crt0.s` | Startup: set SP, zero `.bss`, call `main`, `HLT` |
| `libv6clang_math` | `__mulhi3` (8×8→16), `__mulsi3` (16×16→32), `__divhi3`, `__modhi3`, `__udivhi3`, `__umodhi3` |
| `libv6clang_shift` | `__ashlhi3`, `__ashrhi3`, `__lshrhi3` for variable-count shifts |
| `libv6clang_mem` | `memcpy`, `memset`, `memmove` (with SP-trick optimization) |
| `libv6clang_io` | Thin wrappers for Vector 06c I/O ports (keyboard, display, sound) |

All runtime functions follow `V6CLANG_CConv` (§6.1).

---

## 12. Project Structure

```
llvm-v6clang/
├── llvm/
│   └── lib/
│       └── Target/
│           └── V6Clang/
│               ├── CMakeLists.txt
│               ├── V6Clang.td                      # Top-level TableGen
│               ├── V6ClangTargetMachine.h/.cpp      # TargetMachine subclass
│               ├── V6ClangSubtarget.h/.cpp          # Subtarget features
│               ├── V6ClangRegisterInfo.td           # Register descriptions
│               ├── V6ClangRegisterInfo.h/.cpp       # Register info implementation
│               ├── V6ClangInstrInfo.td              # Instruction descriptions
│               ├── V6ClangInstrFormats.td           # Encoding formats
│               ├── V6ClangInstrInfo.h/.cpp          # Instruction info implementation
│               ├── V6ClangSchedule.td              # Scheduling model
│               ├── V6ClangCallingConv.td            # Calling conventions
│               ├── V6ClangISelLowering.h/.cpp       # Legalization & custom lowering
│               ├── V6ClangISelDAGToDAG.h/.cpp       # Instruction selection
│               ├── V6ClangFrameLowering.h/.cpp      # Prologue/epilogue, stack access
│               ├── V6ClangAsmPrinter.h/.cpp         # Assembly output
│               ├── V6ClangMCInstLower.h/.cpp        # MachineInstr → MCInst
│               ├── V6ClangTargetObjectFile.h/.cpp   # Section layout
│               ├── MCTargetDesc/
│               │   ├── V6ClangMCAsmInfo.h/.cpp      # Assembly syntax config
│               │   ├── V6ClangMCCodeEmitter.h/.cpp  # Binary encoding
│               │   ├── V6ClangMCTargetDesc.h/.cpp   # MC layer registration
│               │   └── V6ClangAsmBackend.h/.cpp     # Fixups & relocations
│               └── TargetInfo/
│                   └── V6ClangTargetInfo.h/.cpp     # Target registration
│
├── clang/
│   └── lib/
│       └── Basic/
│           └── Targets/
│               └── V6Clang.h/.cpp                   # Clang TargetInfo
│
├── compiler-rt/
│   └── lib/
│       └── builtins/
│           └── v6clang/                             # Runtime library (§11)
│               ├── crt0.s
│               ├── mulhi3.s
│               ├── divhi3.s
│               ├── shift.s
│               └── memory.s
│
├── lld/                                         # Linker support (§9.4)
│   └── V6Clang/
│       ├── V6ClangLinker.h/.cpp
│       └── V6ClangLinkerScript.ld
│
├── tests/
│   ├── unit/
│   │   ├── optimization/                        # Standalone C optimization tests
│   │   │   ├── test_zero_test_opt.c
│   │   │   ├── test_xchg_opt.c
│   │   │   ├── test_sp_trick.c
│   │   │   └── test_accumulator_planning.c
│   │   ├── codegen/
│   │   │   ├── test_alu_i8.c
│   │   │   ├── test_alu_i16.c
│   │   │   ├── test_load_store.c
│   │   │   └── test_branch.c
│   │   └── abi/
│   │       ├── test_calling_convention.c
│   │       └── test_struct_return.c
│   ├── lit/
│   │   ├── CodeGen/V6Clang/                         # LLVM IR → asm FileCheck tests
│   │   │   ├── add-i8.ll
│   │   │   ├── add-i16.ll
│   │   │   ├── call-conv.ll
│   │   │   ├── frame-lowering.ll
│   │   │   ├── branch.ll
│   │   │   └── peephole-ora.ll
│   │   └── MC/V6Clang/                              # Assembler/disassembler tests
│   │       ├── encoding.s
│   │       └── relocations.s
│   └── integration/
│       ├── hello_v6clang.c                          # End-to-end: C → binary → emulator verify
│       ├── fibonacci.c
│       └── memcpy_benchmark.c
│
└── docs/
    ├── README.md
    ├── V6ClangArchitecture.md
    ├── V6ClangBuildGuide.md
    ├── V6ClangProjectStructure.md
    ├── V6ClangCallingConvention.md
    ├── V6ClangOptimization.md
    └── V6ClangInstructionTimings.md
```

---

## 13. Testing Strategy

### 13.1 Test Layers

| Layer | Tool | Scope | Count Target |
|-------|------|-------|-------------|
| TableGen validation | `llvm-tblgen` | Register/instruction descriptions parse without error | Per-file |
| Instruction encoding | `llvm-mc` + FileCheck | Every opcode encodes correctly | One test per instruction |
| Instruction selection | `llc` + FileCheck | IR patterns select expected instructions | Per operation per type |
| Optimization passes | `llc` + FileCheck | Custom passes produce expected transforms | Per pass, per pattern |
| Calling convention | `llc` + FileCheck | Arguments/returns in correct locations | Per convention variant |
| Frame lowering | `llc` + FileCheck | Prologue/epilogue correct for various frame sizes | Parameterized |
| Unit tests (C) | Standalone `.c` files | Optimization correctness at the C level | Per optimization (§tests/unit/) |
| End-to-end | Clang → binary → emulator | Programs produce correct output | Integration suite |
| Runtime library | Emulator | Math/memory functions return correct results | Per library function |

### 13.2 Emulator-Based Testing

A Vector 06c emulator executes the compiled binaries and validates output against expected results. This is the final correctness oracle. The test harness:

1. Compiles C source → flat binary.
2. Loads binary into emulator at the configured start address.
3. Runs until `HLT`.
4. Inspects memory/registers for expected state.
5. Optionally counts total cycles for performance regression testing.

---

## 14. Key Interfaces & Extension Points

### 14.1 TargetMachine

```
V6ClangTargetMachine : LLVMTargetMachine
  ├── getSubtargetImpl(Function&) → V6ClangSubtarget&
  ├── createPassConfig(PassManagerBase&) → V6ClangPassConfig
  └── Options:
        ├── StartAddress : uint16_t = 0x0100
        ├── UseFramePointer : bool = false
        └── OptLevel : CodeGenOptLevel
```

### 14.2 Subtarget

```
V6ClangSubtarget : TargetSubtargetInfo
  ├── getInstrInfo()      → V6ClangInstrInfo&
  ├── getRegisterInfo()   → V6ClangRegisterInfo&
  ├── getFrameLowering()  → V6ClangFrameLowering&
  ├── getTargetLowering() → V6ClangTargetLowering&
  └── getSelectionDAGInfo() → SelectionDAGTargetInfo&
```

### 14.3 Custom Pass Registration

```
V6ClangPassConfig : TargetPassConfig
  ├── addPreISel()          → { V6ClangTypeNarrowing }
  ├── addInstSelector()     → { V6ClangDAGToDAGISel }
  ├── addPreRegAlloc()      → { V6ClangAccumulatorPlanning, V6ClangPeephole }
  ├── addPostRegAlloc()     → { V6ClangXchgOpt, V6ClangLoadStoreOpt }
  └── addPreEmitPass()      → { V6ClangZeroTestOpt, V6ClangSPTrickOpt, V6ClangBranchOpt }
```

---

## 15. Risk Assessment & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Register pressure causes excessive spilling | Major performance degradation | Aggressive inlining, type narrowing, rematerialization, SP-trick for bulk moves |
| Accumulator bottleneck serializes ALU ops | Suboptimal scheduling | V6ClangAccumulatorPlanning pass; consider A as conflict resource |
| Stack access cost (32cc/byte) | Slow function calls | Promote aggressively; favor leaf functions; inline small functions |
| 16-bit operations are synthesized | 2× cost of native ops | Type narrowing pass; prefer i8 where possible |
| Multiply/divide are library calls | Very slow | Strength reduction: shift for power-of-2, repeated add for small constants |
| SP-trick requires DI/EI | Incompatible with latency-sensitive interrupts | Mark as unsafe in ISR context; gate behind cost threshold |
| 64KB address space exhaustion | Cannot compile large programs | Warn on section size; support overlays as future extension |

---

## 16. Build Configuration

The backend integrates into the LLVM build system:

```cmake
# llvm/lib/Target/V6Clang/CMakeLists.txt
set(LLVM_TARGET_DEFINITIONS V6Clang.td)

tablegen(LLVM V6ClangGenRegisterInfo.inc   -gen-register-info)
tablegen(LLVM V6ClangGenInstrInfo.inc      -gen-instr-info)
tablegen(LLVM V6ClangGenDAGISel.inc        -gen-dag-isel)
tablegen(LLVM V6ClangGenCallingConv.inc    -gen-callingconv)
tablegen(LLVM V6ClangGenSubtargetInfo.inc  -gen-subtarget)
tablegen(LLVM V6ClangGenMCCodeEmitter.inc  -gen-emitter)
tablegen(LLVM V6ClangGenAsmWriter.inc      -gen-asm-writer)
tablegen(LLVM V6ClangGenDisassemblerTables.inc -gen-disassembler)

add_llvm_target(V6ClangCodeGen
  V6ClangTargetMachine.cpp
  V6ClangSubtarget.cpp
  V6ClangRegisterInfo.cpp
  V6ClangInstrInfo.cpp
  V6ClangISelLowering.cpp
  V6ClangISelDAGToDAG.cpp
  V6ClangFrameLowering.cpp
  V6ClangAsmPrinter.cpp
  V6ClangMCInstLower.cpp
  V6ClangTargetObjectFile.cpp
  # Custom passes
  V6ClangAccumulatorPlanning.cpp
  V6ClangXchgOpt.cpp
  V6ClangSPTrickOpt.cpp
  V6ClangZeroTestOpt.cpp
  V6ClangBranchOpt.cpp
  V6ClangLoadStoreOpt.cpp
  V6ClangTypeNarrowing.cpp
  V6ClangPeephole.cpp
)
```

Build command:
```bash
cmake -G Ninja ../llvm \
  -DLLVM_TARGETS_TO_BUILD="V6Clang" \
  -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD="V6Clang" \
  -DCMAKE_BUILD_TYPE=Release
ninja
```

---

*End of design document.*
