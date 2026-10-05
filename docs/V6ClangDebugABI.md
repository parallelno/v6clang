# V6CLANG Debugger ABI and DWARF Register Map

**Contract version:** 1
**Target:** `i8080-unknown-v6clang`
**Object format:** ELF32 little-endian, `EM_V6Clang` (`0x8080`)
**DWARF format:** DWARF v5, 16-bit target addresses

This document is normative for V6CLANG debug metadata producers and consumers.
Changing a register number or frame rule requires a contract-version change,
compiler tests, and matching debugger compatibility tests.

## Machine and Stack

- The address space is 16 bits and byte-addressed.
- Multi-byte integer and address values are little-endian.
- The stack grows toward lower addresses and has byte alignment.
- `CALL` pushes the 16-bit address of the instruction after the call.
- At callee entry, `SP` points to the low return-address byte; `[SP+1]` is the
  high byte.
- `RET` pops that little-endian address into PC.
- The default startup value is `SP=0x0000`; the first two-byte push wraps to
  `0xfffe` as defined by 8080 arithmetic.

## Arguments and Results

Arguments use type-specific free lists. Assigning a byte register removes its
containing pair from the word list; assigning a pair removes both halves from
the byte list.

- i8 arguments: `A`, `B`, `C`, `D`, `E`, `L`, `H`.
- i16 and pointer arguments: `HL`, `DE`, `BC`.
- Overflow arguments occupy the caller-allocated outgoing area in source
  argument order, starting at caller `SP+0` before `CALL`.
- At callee entry, the first stack argument is at `SP+2`, after the return
  address. Later stack arguments follow at increasing addresses.
- The caller removes the outgoing argument area after return.
- i8 results use `A`.
- i16 and pointer results use `HL`.
- i32 results use `DE:HL`, with `DE` holding the high word.
- All allocatable registers are caller-saved. There are no ordinary
  callee-saved registers.

Aggregates are lowered by the frontend/backend ABI rules in force for their
component widths. A debugger must consume the emitted parameter location and
must not infer an aggregate convention from this summary.

## Frames

The stack frame is selected from the actual machine function shape:

- Leaf functions with no frame may have no prologue or epilogue adjustment.
- Fixed allocation may use dead-pair `PUSH`/`POP`, repeated `DCX SP`/`INX SP`,
  or `LXI HL,offset; DAD SP; SPHL`.
- When a frame pointer is required, `BC` is reserved. The prologue saves the
  incoming `BC`, captures the pre-local-allocation SP in `BC`, and the epilogue
  restores SP and then `BC`.
- Prologues may temporarily save live `HL`/`DE` argument values while forming
  addresses. Final-stream CFI tracks every resulting SP change.
- Static-stack allocation and alloca promotion may place locals or spills in
  per-function global storage rather than the runtime stack.
- O61 may store spill values in the immediate bytes of patched reload
  instructions. Debug locations must describe the actual surviving register
  or address and must not pretend these values use a conventional stack slot.

`DW_AT_frame_base`, frame-relative variable expressions, and call-frame rules
must follow the emitted prologue variant. A consumer must not decode prologue
instruction patterns.

## Baseline Variable Locations

At `-O0`, the compiler emits recoverable formal-parameter and local-variable
locations using the final machine state. Byte and word registers use the
numbers below; stack homes use `DW_OP_fbreg` from a CFA-derived
`DW_AT_frame_base`; proven constants use `DW_AT_const_value`.

V6CLANG may promote a source alloca to a per-function `__v6clang_a.*` global home.
Its location is its final linked address, encoded as `DW_OP_addr` or
`DW_OP_addrx` and, for a subobject, `DW_OP_plus_uconst`. In debug modules the
compiler keeps these homes materialized. O43 remains active, but does not fold
loads or stores of these debug homes into transient stack values. Non-debug
code generation retains the normal promotion and O43 behavior.

Location changes, spill/reload lifetimes, O61 patched reloads, split values,
and unavailable-range gaps are outside this baseline and are specified by
later milestones.

## Tail Calls and Special Frames

- V6CLANG post-RA optimization may replace a terminal `CALL; RET` shape with a
  tail jump. The callee reuses the caller's frame and return address.
- Naked runtime helpers define their own instruction bodies and do not receive
  compiler-generated frame setup.
- Interrupt/trampoline frames are not ordinary C frames. Unwinding stops at
  such a boundary unless the final ELF contains explicit rules for that exact
  frame shape.
- Naked and interrupt-marked functions use an undefined return-PC rule, which
  is an explicit unwind boundary. Absence of usable CFI is not permission to
  scan stack words.

## Call-Frame Information

Debug builds emit `.debug_frame`; V6CLANG does not emit `.eh_frame` for this
debugger-only contract. The CIE uses code alignment 1, data alignment -2,
16-bit addresses, and return-address column 11 (`PC`).

At ordinary function entry:

- `CFA = SP + 2`.
- `PC = [CFA - 2]`.

For SP-based frames, each final PUSH, POP, INX/DCX SP, and recognized
LXI/DAD/SPHL adjustment updates the CFA offset at the following PC. For
frame-pointer functions, saved BC is described relative to the CFA and the
body uses `CFA = BC + offset`; epilogues switch back to SP after restoring BC.
The complex two-live-pair prologue uses `BC + 8`, while the ordinary FP shape
uses `BC + 4`.

When an optimization temporarily repurposes SP and the old CFA cannot be
expressed safely, the return-PC rule becomes undefined. The recognized
SP-trick restoration re-establishes the previous CFA and return-PC rule.

## DWARF Register Numbers

| Number | Register | Width | Overlap |
|-------:|----------|------:|---------|
| 0 | `A` | 8 | accumulator half of unnumbered `PSW` |
| 1 | `B` | 8 | high byte of `BC` |
| 2 | `C` | 8 | low byte of `BC` |
| 3 | `D` | 8 | high byte of `DE` |
| 4 | `E` | 8 | low byte of `DE` |
| 5 | `H` | 8 | high byte of `HL` |
| 6 | `L` | 8 | low byte of `HL` |
| 7 | `BC` | 16 | `B:C` |
| 8 | `DE` | 16 | `D:E` |
| 9 | `HL` | 16 | `H:L` |
| 10 | `SP` | 16 | stack pointer |
| 11 | `PC` | 16 | program counter and CFI return-address column |

Pairs have distinct numbers from their byte registers. A complete i16 value in
a physical pair uses the pair number. A byte value uses its byte-register
number. Split values may use pieces only when the published producer/consumer
operation table enables that representation.

`FLAGS` and `PSW` intentionally have no DWARF numbers in contract version 1.
They are not valid C variable locations or independently recoverable caller
state.

## Producer Compatibility Table

Contract version 1 freezes the following final-ELF producer surface. Consumers
must feature-detect unsupported data and must not infer values or frames from
V6CLANG instruction patterns.

| Category | Version 1 output | Consumer rule |
|----------|------------------|---------------|
| Container | ELF32 little-endian, `EM_V6Clang`, 16-bit code/data addresses | The final ELF is authoritative; the ROM is its executable projection. |
| DWARF | DWARF v5 | Accept 16-bit addresses and DWARF32 unit offsets. |
| Core sections | `.debug_info`, `.debug_abbrev`, `.debug_line`, `.debug_str`, `.debug_str_offsets`, `.debug_addr` | Lines and symbols remain independently useful if semantic data is unavailable. |
| Range/location sections | `.debug_rnglists`, `.debug_loclists` when required | Treat PC intervals as half-open; a missing active entry is unavailable. |
| Frame section | `.debug_frame`, no `.eh_frame` contract | Use only emitted CIE/FDE rules; stop at unsupported boundaries. |
| Scope/type tags | Compile units, subprograms, lexical blocks, formal parameters, variables, inline subroutines, and tested C type DIEs | Use DIE identity and emitted ranges; do not merge shadowed names. |
| Locations | Register pairs/bytes, `DW_OP_fbreg`, `DW_OP_call_frame_cfa`, `DW_OP_addrx`, `DW_OP_plus_uconst`, and constant values | Evaluate only the selected active range with the register map in this document. |
| O61 storage | `DW_OP_addrx; DW_OP_plus_uconst 1` for patched immediate bytes | The address is mutable code storage only for its emitted live interval. |
| Unsupported values | No active location entry | Report unavailable/optimized out; never scan arbitrary stack words. |

Changing an entry in this table requires a contract-version update, a
final-ELF producer test, and a matching consumer test.

## Unwind Boundary Policy

A physical unwind may continue only when an FDE covers the current PC and its
rules recover a valid CFA, return PC, and caller SP. It stops on missing or
unsupported CFI, naked/interrupt/trampoline boundaries without explicit rules,
invalid memory, unchanged CFA, cycles, or addresses outside the 16-bit target
space.

## Verification

Use the final linked ELF as the authoritative metadata artifact. Verify it with
`llvm-dwarfdump --verify`, correlate symbols/ranges with executable sections,
and compare evaluated locations or unwind rules with coherent emulator
register and memory snapshots. The flat ROM contains executable bytes only;
debug sections remain in the companion ELF.
