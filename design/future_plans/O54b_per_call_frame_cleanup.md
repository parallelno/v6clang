# O54b. Per-Call Frame Cleanup via `POP rp`

*Sibling of [O54](O54_optimal_stack_adjustment.md) (prologue/epilogue),
[O54c](O54c_stack_arg_passing_push.md) (caller-side stack args),
[O54d](O54d_alloca_constant_size_push.md) (constant-size alloca).*

## Problem

When a callee receives stack-passed arguments, the caller must release that
space after the CALL returns. Today V6CLANG runs in **reserved-call-frame** mode:
[`V6ClangFrameLowering::eliminateCallFramePseudoInstr`](../../llvm-project/llvm/lib/Target/V6CLANG/V6ClangFrameLowering.cpp#L268-L275)
simply erases the `ADJCALLSTACKDOWN`/`UP` pseudos because the prologue already
reserved `MFI.getMaxCallFrameSize()` for the entire function.

If reserved-call-frame mode is ever flipped to **per-call** (releasing the
reservation between calls — useful when the worst-case call frame dwarfs the
typical case and peak stack pressure matters), each ADJCALLSTACKUP becomes a
real `SP += N` site. The naïve lowering would be `LXI HL, N; DAD SP; SPHL`
(5B/32cc). For small N, `POP rp × n/2` is much cheaper.

## Scope

Only meaningful **after** `hasReservedCallFrame()` is changed to return
`false` (or per-function as decided by a heuristic). Until then there are no
real ADJCALLSTACKUP sites to optimise.

## Strategy

Reuse the same cost table as O54 prologue/epilogue (epilogue side, since this
is always SP-increment / deallocate):

| SP +N | `POP×n` (1B/12cc each) | LXI+DAD+SPHL | Verdict |
|-------|------------------------|--------------|---------|
| +2    | 1B, 12cc               | 5B, 32cc     | POP wins |
| +4    | 2B, 24cc               | 5B, 32cc     | POP wins |
| +6    | 3B, 36cc               | 5B, 32cc     | size-only |
| ≥8    | ≥4B, ≥48cc             | 5B, 32cc     | LXI wins on cc |

## Liveness rules (post-CALL site)

- **FLAGS**: CALL clobbers FLAGS unconditionally → always free → `POP PSW` is
  flag-safe.
- **A**: live iff the call returns i8. Otherwise dead.
- **HL**: live iff the call returns i16 / pointer. Otherwise dead.
- **BC, DE**: never return registers under V6CLANG ABI; both halves are
  call-clobbered → always dead after CALL → `POP B` and `POP D` are
  unconditionally safe.

Implementation should call `LivePhysRegs::stepBackward` from the
ADJCALLSTACKUP point (or look at the operands of the preceding CALL +
post-call `CopyFromReg` chain if the analysis is done before
`addPreEmitPass`):

| Return type | Safe POP target |
|-------------|-----------------|
| void        | `POP PSW` (or `POP B`/`POP D`) |
| i8          | `POP B` or `POP D` (A is live) |
| i16 / ptr   | `POP B` or `POP D` (HL is live; A is dead but PSW would also be fine) |
| i32 (HL+DE) | `POP B` (DE is live) |

## Implementation sketch

`V6ClangFrameLowering::eliminateCallFramePseudoInstr` is rewritten to actually
emit cleanup when the pseudo is `ADJCALLSTACKUP` and the amount is non-zero:

```cpp
MachineBasicBlock::iterator
V6ClangFrameLowering::eliminateCallFramePseudoInstr(
    MachineFunction &MF, MachineBasicBlock &MBB,
    MachineBasicBlock::iterator I) const {
  if (hasReservedCallFrame(MF))
    return MBB.erase(I);                          // unchanged path

  unsigned Opc = I->getOpcode();
  int64_t Amount = I->getOperand(0).getImm();
  DebugLoc DL = I->getDebugLoc();

  if (Opc == V6CLANG::ADJCALLSTACKUP && Amount > 0) {
    Register DeadPair = pickDeadPairAfterCall(MBB, I);   // see below
    emitSPAdjustment(MBB, I, +Amount, DL,
                     V6ClangCost::getOptMode(MF), DeadPair);
  }
  // ADJCALLSTACKDOWN: stack args have already been pushed via O54c, so the
  // marker is consumed by them. Erase here.
  return MBB.erase(I);
}
```

`pickDeadPairAfterCall` inspects the preceding CALL's regmask + the
`CopyFromReg` chain to choose between `PSW`, `BC`, `DE` per the table above.

## Impact

Depends entirely on whether per-call-frame mode is adopted. **If adopted**,
this composes with O54c (push-arg passing) — a call with K i16 stack args
goes from `K × 7B / 44cc` (push) + `5B / 32cc` (cleanup) to `K × 1B / 16cc` +
`(K × 2)/2 × 1B / 12cc`, i.e. roughly `K × 1B + Kcc` extra after the push
itself.

If reserved-call-frame stays the default, this plan is a no-op and should be
dropped.

## Complexity

Medium. ~80 LOC for the cleanup emitter plus a `pickDeadPairAfterCall`
helper. Most of the complexity is the liveness analysis at the cleanup site.

## Risk

Medium-low. The liveness rules above are mechanical, but per-call-frame mode
itself is the bigger risk: it changes how stack offsets are computed in
`eliminateFrameIndex` (offsets become CALL-window-relative).

## Dependencies

- **Hard**: a separate decision (and patch) flipping `hasReservedCallFrame()`
  to return `false`. Without it this plan is dead code.
- **Soft**: O54a (prologue/epilogue) — share the `emitSPAdjustment` helper
  and the cost-mode plumbing.
- **Composes with**: O54c (caller-side `PUSH rp` for arg passing).

## Status

Pending. Gated on a separate decision about reserved-call-frame mode.
