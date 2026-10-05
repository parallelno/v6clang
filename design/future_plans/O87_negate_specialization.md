# O87 — Register-Pressure-Aware Negate Specialization (`-x`, `-1*x`, `x*(-1)`)

## Problem

The current backend already canonicalizes all three source spellings

- `-x`
- `-1 * x`
- `x * (-1)`

to the same machine-level shape: subtract `x` from a materialized zero.

That is semantically fine, but the current lowering burns more registers than
necessary, which is especially expensive on i8080/V6CLANG because there are only
three usable 16-bit pairs (`HL`, `DE`, `BC`) and very few spare 8-bit
registers once `A` and live pair halves are spoken for.

The primary design constraint for this optimization is therefore not just
cycles and bytes, but also **avoiding extra live temporaries through RA**.

All cycle counts below use `docs/V6ClangInstructionTimings.md`:

- `MOV r,r` / `MVI r,imm8`: 8cc
- `XRA r` / `SUB r` / `SBB r` / `CMA`: 4cc
- `INR r`: 8cc
- `LXI rp,imm16`: 12cc

## Current observed emission

### i16 result (`int` on V6CLANG)

Observed in `temp/negate_mulminus_probe.s` for all three spellings:

```asm
LXI D, 0
;--- V6CLANG_SUB16 ---
MOV A, E
SUB L
MOV L, A
MOV A, D
SBB H
MOV H, A
```

Cost: `12 + 8 + 4 + 8 + 8 + 4 + 8 = 52cc`, `9B`.

Problems:

1. A whole extra register pair is occupied just to hold zero.
2. That zero pair must survive through RA, worsening the already-tight pair
   pressure on `HL`/`DE`/`BC`.
3. The final expansion is slower than necessary even after the pair has been
   allocated.

### i8 result when source is already in `A`

Observed in `temp/negate_mulminus_probe.s` for signed `char` return:

```asm
MOV L, A
XRA A
SUB L
```

Cost: `8 + 4 + 4 = 16cc`, `3B`.

Problems:

1. A spare GR8 is consumed only to preserve the original `A`.
2. The scratch register increases pressure on the tiny GR8 file.
3. A faster accumulator-only sequence exists when the source is already in `A`.

### i8 memory-source negate is different

For example, current global-byte negate lowers to:

```asm
LXI H, addr
XRA A
SUB M
```

Cost after address materialization: `12 + 4 + 8 = 24cc`, `4B`.

This is already better than `LDA addr; CMA; INR A` (`16 + 4 + 8 = 28cc`).
So the i8 optimization must be **shape-specific** and must not pessimize
memory-input cases.

## Proposed optimization

## 1. i16: dedicated `NEG16` pseudo selected before RA

Introduce a dedicated negate pseudo for the canonical DAG shape
`(sub 0, x)`:

```tablegen
let isPseudo = 1, Defs = [A, FLAGS] in
def V6CLANG_NEG16 : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src),
    "# NEG16 $dst, $src", []>;
```

Important: this should be selected from the canonical subtract form before RA,
not recovered later from `LXI rp, 0` plus `V6CLANG_SUB16`.

Reason: a post-RA peephole would recover some byte/cycle savings, but it would
still force the extra zero pair to participate in register allocation, which is
the main architectural problem on V6CLANG.

### Expansion

For any source pair and any destination pair:

```asm
XRA A
SUB src_lo
MOV dst_lo, A
SBB A
SUB src_hi
MOV dst_hi, A
```

Cost: `4 + 4 + 8 + 4 + 4 + 8 = 32cc`, `6B`.

`SBB A` computes `A − A − CY = 0 − CY`, giving `0x00` when there is no
borrow and `0xFF` when there is. The subsequent `SUB src_hi` then yields
`0 − src_hi − borrow`, which is the correct high byte of the two's-complement
negate in both cases.

Savings vs current emission:

- `-20cc` per fire
- `-3B` per fire
- eliminates one full GR16 live range (the zero pair)

This is the main win.

### Why this shape is good for V6CLANG

1. It clobbers only `A`, `FLAGS`, and the destination pair.
2. It does not require a scratch pair.
3. It works for both `dst == src` and `dst != src`.
4. It matches the current subtract-from-zero flag behavior, because it is still
   a true low-byte `SUB` followed by high-byte `SBB` with the borrow carried
   through.

### Why not use complement-then-`INX` for i16?

The runtime helper `__v6clang_neg_hl_body` already uses:

```asm
MOV A, L
CMA
MOV L, A
MOV A, H
CMA
MOV H, A
INX H
```

Cost: `8 + 4 + 8 + 8 + 4 + 8 + 8 = 48cc`, `7B`.

This is better than the current 52cc subtract-from-zero expansion, but still
strictly worse than the proposed 32cc `SBB A`/`SUB` shape. So it is not the best
backend lowering for this case.

## 2. i8: dedicated result-only `NEG8` pseudo, but only for safe shapes

The i8 improvement is real, but it is much narrower.

When the source value is already in `A`, two's-complement negate can be formed
as:

```asm
CMA
INR A
```

Cost: `4 + 8 = 12cc`, `2B`.

That beats the observed scratch form:

```asm
MOV spare, A
XRA A
SUB spare
```

Cost: `16cc`, `3B`.

However, `CMA; INR A` is **not** a general replacement for `0 - x`:

1. It only wins when the source is already in `A`.
2. It does not match subtraction's `CY`/`AC` behavior.
3. It is worse for non-`A` sources, and worse for memory-input negates.

So the correct design is a dedicated **result-only** negate pseudo, selected
only for ordinary arithmetic `sub 0, x` where machine flags are not relied on
as subtraction flags.

```tablegen
let isPseudo = 1, Defs = [A, FLAGS] in
def V6CLANG_NEG8 : V6ClangPseudo<(outs GR8:$dst), (ins GR8:$src),
    "# NEG8 $dst, $src", []>;
```

### Expansion table for `V6CLANG_NEG8`

| Shape | Expansion | Cost |
|---|---|---|
| `src == A`, `dst == A` | `CMA; INR A` | `12cc`, `2B` |
| `src == A`, `dst != A` | `CMA; INR A; MOV dst, A` | `20cc`, `3B` |
| `src != A`, `dst == A` | `XRA A; SUB src` | `8cc`, `2B` |
| `src != A`, `dst != A` | `XRA A; SUB src; MOV dst, A` | `16cc`, `3B` |

Only the `src == A` rows are new wins. The other rows should deliberately keep
the current subtract-from-zero strategy because forcing `MOV A, src; CMA; INR A`
would be slower.

### Flag semantics caveat

`CMA` does not write flags, and `INR` does not write `CY`.

Therefore `V6CLANG_NEG8` must be used only for **result-only** arithmetic. Any
flag-producing i8 subtract/compare shape must remain on the existing subtract
path.

This is the central legality boundary for the i8 part of the plan.

## Where to implement it

## Canonical trigger: `sub 0, x`

The temp probe already shows that Clang/LLVM canonicalizes all three source
spellings (`-x`, `-1*x`, `x*(-1)`) to the same subtract-from-zero shape.

So the backend should target the canonical node `sub 0, x`, not the front-end
spelling of multiply-by-minus-one.

That keeps the implementation surface small and robust.

## Recommended pipeline placement

### i16

Select `V6CLANG_NEG16` before RA, either by:

1. a direct TableGen pattern for `(sub (i16 0), i16:$src)`, or
2. a small custom-lowering helper if the generic subtract pattern wins too
   often and needs an explicit priority bump.

The crucial point is that RA must never see the extra zero pair.

### i8

Select `V6CLANG_NEG8` only for result-only subtracts. Keep flag-producing i8 nodes
on the existing subtract path.

This likely means wiring it through ordinary arithmetic lowering rather than the
existing flag-producing O75 `*F` family.

## Files likely touched

- `llvm/lib/Target/V6CLANG/V6ClangISelLowering.h`
- `llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp`
- `llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td`
- `llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`
- `llvm/test/CodeGen/V6CLANG/...` (source of truth)

The annotator path in `V6ClangInstrInfo.cpp` should also learn the new pseudo names
so `-mllvm -mv6clang-annotate-pseudos` prints `V6CLANG_NEG16` / `V6CLANG_NEG8` instead of
opaque instruction sequences.

## Why a pure peephole is not enough

For both widths, a late peephole can recover some local code-quality benefit.
But it misses the most important V6CLANG constraint:

- i16 peephole: RA already paid for the zero pair.
- i8 peephole: RA already paid for the scratch GR8 in the `src == A` case.

Because register pressure is the first-class constraint here, the design should
create dedicated pseudos early enough that RA never has to allocate those extra
temporaries in the first place.

## Expected benefit

### Direct benefit

- i16 negate: `-20cc`, `-3B`, and one fewer live GR16 pair.
- i8 negate, `src == A`: typically `-4cc`, `-1B`, and one fewer scratch GR8.

### Indirect benefit

On V6CLANG the indirect gain may matter as much as the direct one:

- fewer live pairs in tight i16 code
- fewer scratch bytes in accumulator-heavy i8 code
- lower spill probability around arithmetic kernels

This is exactly the sort of change that can outperform its local cycle savings
on a 3-pair machine.

## Risks and guards

### 1. i8 flags mismatch

`CMA; INR A` does not reproduce subtract `CY`/`AC` semantics.

Guard:

- use `V6CLANG_NEG8` only for result-only arithmetic nodes
- keep all flag-producing or compare-related paths on existing subtract logic

### 2. Pessimizing non-`A` or memory i8 inputs

Guard:

- only use the `CMA; INR A` row when `src == A`
- keep the existing `XRA A; SUB src` / `SUB M` shapes elsewhere

### 3. Implementing too late

Guard:

- do not frame this as a post-RA cleanup only
- make sure the i16 zero pair and the i8 scratch are removed from the IR/MIR
  shape before RA has to allocate them

## Verification plan

Add a new lit test, for example:

- `llvm/test/CodeGen/V6CLANG/negate-specialization.ll`

Coverage should include:

1. i16 `-x`
2. i16 `-1*x`
3. i16 `x*(-1)`
4. i8 `-x` with source already in `A`
5. i8 non-`A` source case to prove no pessimization
6. i8 global/memory source case to prove no pessimization
7. a flag-sensitive i8 subtract shape to prove `NEG8` does not fire there

Checks should assert:

- no `LXI ?, 0` for the i16 negate path
- `V6CLANG_NEG16` annotated expansion uses the 32cc `XRA/SUB/SBB A/SUB` shape
- `CMA; INR A` appears for the accumulator i8 negate case
- memory-source i8 negate remains on the `SUB M` shape

## Summary

This is a good optimization target, but the two widths are not symmetric.

- **i16**: clear win, broad applicability, and should be implemented as an
  early dedicated negate pseudo so the extra zero pair never reaches RA.
- **i8**: real win only when the source is already in `A`; must be designed as
  a result-only specialization and must not be generalized to non-`A` or
  memory-source shapes.

The common theme is the same in both cases: on i8080/V6CLANG, avoiding unnecessary
temporary registers is as important as shaving raw cycles.