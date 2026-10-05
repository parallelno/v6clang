# O54d. Constant-Size `alloca` via `PUSH rp`

*Sibling of [O54](O54_optimal_stack_adjustment.md) (prologue/epilogue),
[O54b](O54b_per_call_frame_cleanup.md) (per-call cleanup),
[O54c](O54c_stack_arg_passing_push.md) (caller-side stack args).*

## Problem

`__builtin_alloca(C)` with a compile-time constant `C`, and VLAs whose bound
folds to a constant after IR optimisation, lower today through
`ISD::DYNAMIC_STACKALLOC` to the same `LXI HL, -C; DAD SP; SPHL` sequence
the prologue uses (5B / 32cc) regardless of how small `C` is.

For `C ∈ {2, 4}` (and possibly `6` under `-Os`) the same `PUSH rp × C/2`
trick from O54a is cheaper.

## Where this fires

- Hand-written `__builtin_alloca(2)` / `(4)` for tiny scratch buffers
  (e.g. struct-return lowering, varargs frames).
- VLAs with constant bound after constant-folding (rare in real code; LLVM
  typically promotes them to fixed-size allocas in the entry block, which
  then go through O54a's prologue path — *not* this plan).

In practice the dynamic-alloca path is hit only by genuinely dynamic
size-expressions whose constant folding happens late. Frequency is **niche**.

## Strategy

When `ISD::DYNAMIC_STACKALLOC` has a `ConstantSDNode` size operand `C` with
`C > 0 && C ≤ 6 && (C % 2) == 0` (and ≤4 unconditionally; `==6` only under
`-Os`):

```asm
; Before:
LXI  H, -C        ; 3B 12cc
DAD  SP           ; 1B 12cc
SPHL              ; 1B  8cc
LXI  H, 0         ; 3B 12cc
DAD  SP           ; 1B 12cc      ; materialise pointer (= new SP) into HL
                  ; 9B 56cc

; After (C=4):
PUSH PSW          ; 1B 16cc
PUSH PSW          ; 1B 16cc
LXI  H, 0         ; 3B 12cc
DAD  SP           ; 1B 12cc      ; materialise pointer into HL
                  ; 6B 56cc      ; size: −3B; cycles: ±0
```

The `LXI 0; DAD SP` tail is needed in **both** sequences to deliver the
allocated pointer into HL. Audit current alloca lowering before committing —
if the existing code already uses `SPHL` to leave HL holding the new SP,
the materialisation is free in the current sequence and the comparison
shifts: 5B / 32cc vs `(C/2)B + 0cc` for the pointer (impossible — SPHL only
copies HL→SP, not the reverse). The reverse direction requires `LXI 0; DAD SP`,
so the tail cost applies to both.

### Cost table (with materialisation tail)

| C | Current (5B/32cc + 4B/24cc tail) | Proposed (`PUSH × C/2` + 4B/24cc tail) | Δ |
|---|----------------------------------|---------------------------------------|---|
| 2 | 9B / 56cc | 5B / 40cc | −4B / −16cc ✅ |
| 4 | 9B / 56cc | 6B / 56cc | −3B / ±0cc ✅ (size-only tie on cc) |
| 6 | 9B / 56cc | 7B / 72cc | −2B / +16cc → `-Os` only |
| ≥8 | unchanged | worse on cc | LXI wins |

### Liveness at the alloca site

Harder than prologue, easier than O54b (per-call). Mid-function code can
have FLAGS or A live.

- **FLAGS**: not generally dead. Walk forward from the alloca with
  `LivePhysRegs` to check. If FLAGS is live, fall back to LXI+DAD+SPHL.
  Note: that fallback also writes carry via `DAD`, so FLAGS-live + alloca
  is *already* incorrect in current lowering — this is a latent bug to
  audit, separately from this plan.
- **A**: typically live across an alloca only when the alloca's surrounding
  code is in an i8 expression context (rare — alloca is usually consumed by
  a pointer-typed user). Pick a dead GR16All pair (try BC, DE, then HL) if A
  is live, instead of `PUSH PSW`.

### Pointer materialisation

Standard tail:
```asm
LXI  H, 0
DAD  SP
```
4B / 24cc. V6CLANG has no "LD HL, SP" instruction, so this is the cheapest path.
The materialisation runs **after** the pushes, so HL is fine to clobber even
if it was used as the dead pair for the pushes.

## Constraints

- Size must be a `ConstantSDNode`, ≤6, even.
- Alloca alignment must be ≤1 (always true on V6CLANG — byte alignment).
- Must not occur inside an outstanding `ADJCALLSTACK` window. ISel doesn't
  form such overlaps in practice (alloca is its own pseudo, separate from
  call sequences), but assert it.

## Implementation

Custom lowering of `ISD::DYNAMIC_STACKALLOC` in `V6ClangISelLowering`. Pattern:

```cpp
SDValue V6ClangTargetLowering::LowerDYNAMIC_STACKALLOC(SDValue Op,
                                                   SelectionDAG &DAG) const {
  SDValue Size = Op.getOperand(1);
  if (auto *C = dyn_cast<ConstantSDNode>(Size)) {
    uint64_t N = C->getZExtValue();
    if (N > 0 && N <= 4 && (N % 2) == 0) {
      // Emit V6CLANG_PUSH_FOR_ALLOCA pseudo × N/2, then LXI 0; DAD SP.
      // The pseudo is expanded post-RA into PUSH PSW / PUSH B / PUSH D
      // depending on the dead-pair choice.
      ...
    }
    if (N == 6 && getV6ClangOptMode(MF) == V6ClangOptMode::Size) {
      // Same with N/2 = 3 pushes.
      ...
    }
  }
  // Fall through to default LXI/DAD/SPHL lowering.
  return SDValue();   // signals default expansion
}
```

The pseudo `V6CLANG_PUSH_FOR_ALLOCA` is expanded post-RA via the same dead-pair
chooser as O54a/O54b.

## Impact

Niche. Real-world bsort/sieve/fib_crc benchmarks contain **zero** dynamic
allocas. Matters only for code that genuinely uses `__builtin_alloca` with
small constant sizes. Worth implementing for completeness once the rest of
the O54 family is in, but should not be prioritised on its own.

## Complexity

Low-medium. ~50 LOC for the custom lowering, plus a new pseudo and post-RA
expansion that share the dead-pair helper from O54a.

## Risk

Low. The cost margin is small (`C=4` ties on cycles) so any miscount makes
the optimisation a no-op rather than a regression. The pre-existing
FLAGS-clobber audit (DAD writes carry) should land first, separately.

## Dependencies

- **Hard**: O54a (shares dead-pair chooser + post-RA push pseudo).
- **Soft**: a one-off audit of the existing FLAGS-live + alloca interaction
  in `LowerDYNAMIC_STACKALLOC`.

## Status

Pending. Lowest priority of the O54 family. Implement after O54a + O54c
have validated the liveness-checking helper and the dead-pair chooser.
