# O69: Direct Frame-Index Memory Pseudos

## Status

Implemented.

## Motivation

Stack argument access can currently produce a redundant pointer copy through a non-HL pair when `V6CLANG_LEA_FI` feeds a pointer load/store pseudo. The deeper problem is not just the copy pair after register allocation: the register allocator sees a temporary address value in a general 16-bit register, which increases pressure and can force unnecessary copies/spills.

Example from `tests/features/47/v6clang_stack_args.c` after fixing stack-passed arguments:

```asm
;--- V6CLANG_LEA_FI ---
LXI     H, 2
DAD     SP
MOV     B, H
MOV     C, L
;--- V6CLANG_LOAD16_P ---
MOV     H, B
MOV     L, C
MOV     A, M
INX     H
MOV     H, M
MOV     L, A
```

The `MOV B,H; MOV C,L` pair is emitted because `V6CLANG_LEA_FI` computes the frame-index address in `HL` (`DAD SP` always writes `HL`) and the register allocator selected `BC` as the result register. The following `V6CLANG_LOAD16_P` then needs the pointer in `HL` because the 8080 memory operand `M` is addressed only through `HL`, so it copies `BC` back to `HL`.

For single-use stack loads and stores, this round trip is unnecessary. The backend should expose direct frame-index memory pseudos before register allocation, so the allocator sees only the real value operand/result and no address temporary.

Unlike spill/reload pseudos, these direct FI memory pseudos are ordinary value operations. They should not preserve scratch registers internally. Instead, they should model their clobbers honestly and let register allocation insert copies if a live value must survive the `HL` scratch use. This avoids the cascade-spill concern that motivates the conservative spill/reload expansions, while keeping the pressure model visible to RA.

For `dst=HL`, the desired expansion is:

```asm
;--- V6CLANG_LOAD16_FI dst=HL ---
LXI     H, 2
DAD     SP
MOV     A, M
INX     H
MOV     H, M
MOV     L, A
```

For `dst!=HL`, the desired expansion is:

```asm
;--- V6CLANG_LOAD16_FI dst=DE/BC ---
LXI     H, 2
DAD     SP
MOV     RPlow, M
INX     H
MOV     RPhigh, M
```

For `V6CLANG_LOAD8_FI`, the desired expansion is:

```asm
;--- V6CLANG_LOAD8_FI dst=r8 ---
LXI     H, Offset
DAD     SP
MOV     dst, M
```

If `dst` is `H` or `L`, the address scratch is overwritten by the loaded value. That is acceptable for this pseudo: `HL` is modeled as clobbered, and RA is responsible for keeping any live pre-existing `HL` value elsewhere.

For `V6CLANG_STORE8_FI`, the desired expansion is:

```asm
;--- V6CLANG_STORE8_FI src=r8 ---
LXI     H, Offset
DAD     SP
MOV     M, src
```

If `src` is `H` or `L`, RA should copy it to a non-`HL` register before the pseudo because the pseudo clobbers `HL` to form the address.

For `V6CLANG_STORE16_FI`, the desired expansion is:

```asm
;--- V6CLANG_STORE16_FI src=DE/BC/HL ---
LXI     H, Offset
DAD     SP
MOV     M, SrcLo
INX     H
MOV     M, SrcHi
```

If `src=HL`, RA should copy the value to `DE` or `BC` before the pseudo because address calculation clobbers `HL`.

## Scope

Introduce direct frame-index memory pseudos and select them when a load/store is known to be stack-relative:

- `V6CLANG_LOAD8_FI`
- `V6CLANG_LOAD16_FI`
- `V6CLANG_STORE8_FI`
- `V6CLANG_STORE16_FI`

Start with `V6CLANG_LOAD16_FI`, since it is the observed stack-argument case. Then add `V6CLANG_LOAD8_FI`, `V6CLANG_STORE8_FI`, and `V6CLANG_STORE16_FI` using the same frame-index offset path.

## Candidate Implementation

Preferred location: SelectionDAG/isel lowering, before register allocation.

The important design point is that this should not be only a post-RA peephole. A peephole can remove the visible `HL -> BC -> HL` round trip, but it does not solve the register-pressure problem because RA has already allocated a separate address register.

Implemented lowering for the direct FI pseudo family:

1. Add `V6CLANG_LOAD16_FI : V6ClangPseudo<(outs GR16:$dst), (ins i16imm:$fi), ...>`.
2. Add `V6CLANG_LOAD8_FI : V6ClangPseudo<(outs GR8:$dst), (ins i16imm:$fi), ...>`.
3. Add `V6CLANG_STORE8_FI : V6ClangPseudo<(outs), (ins GR8:$src, i16imm:$fi), ...>`.
4. Add `V6CLANG_STORE16_FI : V6ClangPseudo<(outs), (ins GR16:$src, i16imm:$fi), ...>`.
5. During address selection, recognize loads/stores whose base is a `FrameIndex` and select the direct FI pseudo instead of `V6CLANG_LEA_FI + V6CLANG_LOAD*_P/V6Clang_STORE*_P`.
6. Expand the direct FI pseudo in `V6ClangRegisterInfo::eliminateFrameIndex` after computing the normal frame-index `Offset`.
7. For `V6CLANG_LOAD16_FI dst=HL`, emit `LXI H, Offset; DAD SP; MOV A,M; INX H; MOV H,M; MOV L,A`.
8. For `V6CLANG_LOAD16_FI dst!=HL`, emit `LXI H, Offset; DAD SP; MOV DstLo,M; INX H; MOV DstHi,M`.
9. For `V6CLANG_LOAD8_FI`, emit `LXI H, Offset; DAD SP; MOV Dst,M`.
10. For `V6CLANG_STORE8_FI`, emit `LXI H, Offset; DAD SP; MOV M,Src`.
11. For `V6CLANG_STORE16_FI`, emit `LXI H, Offset; DAD SP; MOV M,SrcLo; INX H; MOV M,SrcHi`.

This keeps frame-index offset calculation centralized in `eliminateFrameIndex`, while removing the temporary address virtual register before RA.

## Correctness Conditions

- The direct FI pseudo must use the same `MFI.getObjectOffset(FI) + MFI.getStackSize() + SPAdj` offset model as existing frame-index pseudos.
- Do not preserve `HL` internally. These are not spill/reload pseudos; they are normal value operations. Model `HL` as clobbered and let RA handle values that must survive.
- Preserve the existing `V6CLANG_LOAD16_P` loaded-value semantics for destination overlap with `HL`:
  - `dst=HL`: use `A` as the low-byte temporary because `INX H` may change `H` before the high byte is read.
  - `dst=DE/BC`: load directly into low/high halves because `HL` is just the address scratch.
- For `V6CLANG_LOAD8_FI dst=H/L`, allow the load to overwrite the address scratch after the memory operand is read; RA must protect any previous `HL` value if needed.
- For `V6CLANG_STORE8_FI src=H/L` and `V6CLANG_STORE16_FI src=HL`, rely on RA to copy the source value out of `HL` before the pseudo, because `LXI+DAD SP` clobbers `HL` before the store.
- Model clobbers honestly. Every direct FI pseudo should define `HL` and `FLAGS` because `LXI+DAD SP` uses `HL` as scratch and `DAD` defines flags.
- Be careful with `dst=HL`: the final loaded value owns `HL`, so no restore of the address scratch is needed.

## Expected Savings

For the observed stack-argument load:

```asm
MOV     B, H
MOV     C, L
MOV     H, B
MOV     L, C
```

Savings for the observed first stack-argument load (`Offset == 2`, `dst=HL`): 4 bytes and 32 cycles versus the current `V6CLANG_LEA_FI + V6CLANG_LOAD16_P` sequence.

For `V6CLANG_LOAD8_FI`, the current stack-arg shape can be `V6CLANG_LEA_FI` plus `V6CLANG_LOAD8_P`, for example `LXI H,2; DAD SP; XCHG; LDAX D`. The direct FI form can become `LXI H,2; DAD SP; MOV A,M`, saving the address transfer and avoiding the temporary address register.

For `V6CLANG_STORE8_FI` and `V6CLANG_STORE16_FI`, the direct FI forms remove the need for the store itself to keep a frame address live in `DE`/`BC`. If the address is separately needed, such as for `escape(&slot)`, a separate `V6CLANG_LEA_FI` may still remain for that call argument, but the store no longer increases address-register pressure.

## Tests

Added `llvm-project/llvm/test/CodeGen/V6Clang/frame-index-direct-fi.ll` with coverage for all four direct FI pseudos:

- `V6CLANG_LOAD8_FI` for stack-passed i8 arguments.
- `V6CLANG_LOAD16_FI` for stack-passed i16 arguments.
- `V6CLANG_STORE8_FI` for volatile i8 stack locals.
- `V6CLANG_STORE16_FI` for volatile i16 stack locals.

The i16 load may be allocated to `HL`, `DE`, or `BC`; the important property is that the frame-index load is direct and does not materialize an address temporary through `V6CLANG_LEA_FI + V6CLANG_LOAD16_P`.

The feature artifact in `tests/features/48` exercises the same shapes from C.

Example source shape for the stack i16 load:

```c
__attribute__((noinline))
int f(int a, int b, int c, int d) {
  return a + b + c + d;
}
```

Check that the callee-side stack load for the first stack argument contains a direct FI load such as:

```asm
LXI H, 2
DAD SP
MOV C, M
INX H
MOV B, M
```

And does not contain the round-trip copy pattern near the load:

```asm
MOV B, H
MOV C, L
MOV H, B
MOV L, C
```

Also keep the runtime feature test in `tests/features/47/v6clang_stack_args.c` as an end-to-end guard. With the current expanded user repro, `error_stack_arg` outputs `15`, while `reg_args` outputs `6`.

## Risk

Medium. The optimization is local and mechanically verifiable, but it touches stack-relative addressing, pseudo selection, and pseudo expansion. The main risk is mishandling `HL` destination overlap or modeling the `HL`/`FLAGS` clobbers too weakly.

## Dependencies

- Existing stack-argument correctness fixes:
  - incoming stack args use `SPOffset = 2 + StackOffset`
  - `copyPhysReg` supports `SP -> BC/DE`
  - `V6CLANG_LOAD16_P` does not restore over a `dst=HL` load
- Existing `V6CLANG_LEA_FI` and `V6CLANG_LOAD16_P` pseudo expansion paths.
