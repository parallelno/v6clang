# O54c. Stack-Arg Passing via `PUSH rp` (caller side)

*Sibling of [O54](O54_optimal_stack_adjustment.md) (prologue/epilogue),
[O54b](O54b_per_call_frame_cleanup.md) (per-call cleanup),
[O54d](O54d_alloca_constant_size_push.md) (constant-size alloca).*

## Problem

When a call has more arguments than the V6CLANG ABI can pass in registers
(>3 register-eligible values, or i32-tail values), the overflow goes on the
stack. Today `LowerCall` materialises each stack arg via SP-relative store:

```asm
; per i16 stack arg, current code (≈ V6ClangISelLowering.cpp ~line 1140)
LXI  H, off       ; 3B 12cc
DAD  SP           ; 1B 12cc
MOV  M, lo        ; 1B  7cc
INX  H            ; 1B  6cc
MOV  M, hi        ; 1B  7cc
                  ; 7B 44cc total
```

This is wasteful: `PUSH rp` does the same thing in 1B / 16cc *and* moves SP
along the way (so the next stack arg doesn't need its own offset
recomputation).

## Strategy

Rewrite the overflow-arg path to push args **right-to-left** so the first
stack arg ends up at the lowest stack address — matching the layout
`LowerFormalArguments` already expects via `MFI.CreateFixedObject`.

### Cost comparison

| Arg width | Current | Proposed | Savings |
|-----------|---------|----------|---------|
| i16       | 7B / 44cc | `PUSH rp` (1B / 16cc) | −6B / −28cc |
| i8 (in A) | ~6B / 32cc | `PUSH PSW` (1B / 16cc) — high byte garbage | −5B / −16cc |
| i8 (other) | ~6B / 32cc | `MOV A, src; PUSH PSW` (2B / 20cc) | −4B / −12cc |

For i8 args, the pushed high byte is garbage; the callee's matching slot
(also i8) only reads the low byte, so this is correct.

### Constraints

- Args must be pushed **right-to-left** (last arg first). The current
  store-via-offset code already iterates in order; the push variant must
  reverse only the overflow tail.
- Pushes must come **before** the register-arg `CopyToReg` chain. Once
  register args are live in their physregs, moving SP underneath them risks
  triggering spill/reload across the call seq window.
- Each `PUSH rp` requires the value already live in a GR16All pair
  (`BC`/`DE`/`HL`). For arbitrary i16 SDValues this means a `CopyToReg` to a
  virtual GR16 vreg immediately before each push, or a custom ISel pattern
  that emits PUSH directly.
- For non-reserved-call-frame mode, the matching cleanup is `POP × n/2`
  (see [O54b](O54b_per_call_frame_cleanup.md)). For reserved-call-frame
  mode (current default), the prologue's `MaxCallFrameSize` reservation
  already covers it — but the prologue must then **not** also reserve those
  bytes, otherwise SP ends up double-decremented. Two options:
  1. Leave reserved-call-frame on; subtract the pushed amount from the
     reservation in `MaxCallFrameSize` accounting.
  2. Switch to per-call-frame for functions that use `PUSH`-arg passing,
     coupling this plan with O54b.

## Implementation sketch

In `V6ClangISelLowering::LowerCall`, replace the overflow-store loop with:

```cpp
// 1. Partition Outs into RegArgs (assigned a physreg by V6ClangArgAllocator)
//    and StackArgs (allocator returned NoRegister).
// 2. For StackArgs, emit pushes in REVERSE order (last stack arg pushed first):
for (auto It = StackArgs.rbegin(); It != StackArgs.rend(); ++It) {
  SDValue Arg = It->Val;
  MVT VT     = It->VT;

  if (VT == MVT::i16) {
    // CopyToReg into a fresh GR16 vreg, then PUSH it.
    Register VReg = MRI.createVirtualRegister(&V6CLANG::GR16AllRegClass);
    Chain = DAG.getCopyToReg(Chain, DL, VReg, Arg, Glue);
    Glue  = Chain.getValue(1);
    Chain = DAG.getNode(V6ClangISD::PUSH, DL, MVT::Other,
                        Chain, DAG.getRegister(VReg, MVT::i16), Glue);
  } else {                                  // i8
    // MOV A, Arg; PUSH PSW.
    Chain = DAG.getCopyToReg(Chain, DL, V6CLANG::A, Arg, Glue);
    Glue  = Chain.getValue(1);
    Chain = DAG.getNode(V6ClangISD::PUSH_PSW, DL, MVT::Other, Chain, Glue);
  }
  Glue = Chain.getValue(1);
}
// 3. Then the existing register-arg CopyToReg chain runs.
```

`V6ClangISD::PUSH` and `PUSH_PSW` are new SDNodes lowered to the existing
`V6CLANG::PUSH` MachineInstr. Alternatively a single `V6CLANG_STACK_ARG_PUSH` pseudo
that takes any GR16All / GR8 and gets expanded post-RA, sidestepping the
GR16All-vreg dance.

## Impact

High for ABI-heavy code (functions with >3 register-eligible args or i32 +
several i16 args). Hand-checked: most current bsort/sieve/fib_crc benchmarks
pass ≤3 args, so the immediate impact on cycles is modest. Real wins surface
in:

- C library entry points (`memcpy`, `memmove`, varargs-style helpers).
- Inter-module calls in larger programs once libv6clang-builtins is rebuilt.
- Functions returning structs by value (sret pointer + several scalars).

Code-size win is meaningful even at low frequency: −6B per i16 stack arg.

## Complexity

Medium. ~120 LOC across `LowerCall`, plus a new SDNode + Pat<> for `PUSH`,
plus the `V6ClangArgAllocator` interaction (no change needed — the allocator
already returns NoRegister for overflow args).

## Risk

Medium. The CALLSEQ window must be tight: SP-changing pushes inside it can
confuse the register allocator if a spill/reload references SP-relative
slots. Verify by enabling `-verify-machineinstrs` on the existing
`call-conv-overlap.ll` lit test plus a new test exercising 4-i16-arg calls.

## Dependencies

- **Soft**: O54a (`emitSPAdjustment` helper for cleanup; alternatively go
  via O54b's per-call cleanup).
- **Coupling**: O54b — cleanup of pushed args needs per-call-frame mode, OR
  the reserved-call-frame accounting must subtract the pushed bytes from the
  prologue reservation.

## Status

Pending. Highest-impact piece of the O54 family in real-world C code; depends
on O54a landing first to share helpers.
