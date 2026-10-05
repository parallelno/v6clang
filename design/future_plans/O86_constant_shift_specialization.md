# O86: Constant-Amount i16 Shift Specialization (Rotate-And-Mask + DAD H + 24-bit Trick)

Builds on [O62](O62_efficient_shift_expansion.md) (whole-byte specialization
for ShAmt ≥ 8) and supersedes [O57](O57_shift_rotate_chaining.md) for the
constant-amount case.

## Problem

The current `V6CLANG_SHL16` / `V6CLANG_SRL16` / `V6CLANG_SRA16` expansions
([V6ClangInstrInfo.cpp](../../llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp), case
`V6CLANG_SHL16` ~line 2255, `V6CLANG_SRL16` ~line 2311) handle two regimes:

* **ShAmt 1..7** — per-bit unrolled loop in the A register
  (`MOV A,r / ADD A,r / MOV r,A` for SHL; `MOV A,r / ORA A / RAR / MOV r,A`
  for SRL). **Each bit costs 40cc (SHL) or 44cc (SRL)**.
* **ShAmt 8..15** — O62 byte-lane move + per-bit loop on the surviving
  half (3 + (ShAmt−8) per-bit iterations).

Both regimes ignore two cheap 8080 idioms:

1. **`DAD H` shifts HL left by 1 in 12cc** — vs. 40cc for the A-domain
   per-bit step. Only HL supports it directly; DE can use it via a
   2× `XCHG` wrap (+8cc total).
2. **Rotate-and-mask in A** — when the result has ≤ N bits surviving in
   a single byte, `RRC`/`RLC` + `ANI mask` collapses the per-bit loop
   into 4cc per rotation (vs. 24cc for RAR-in-place or 20cc for ADD A,A
   in-place).
3. **The 24-bit left shift trick for short right shifts**:
   `DAD H` shifts HL left and the carry-out is bit 15. `ADC A` (with
   A=0) captures that bit into A. After `(8−N)` iterations, `A` holds
   the top `(8−N)` bits of `x` and `H` holds bits `[N+7..N]` — exactly
   `x >> N` distributed across `A:H`. Final `MOV L,H ; MOV H,A` lands
   the result in HL.

The result is large pessimisations for several common shift amounts.

## Concrete cost comparison

All values in Vector-06c cycles
([docs/V6ClangInstructionTimings.md](../../docs/V6ClangInstructionTimings.md)).

### `SHL16` (logical / arithmetic left shift)

| ShAmt | Today (HL) | Today (DE) | Optimal (HL) | Optimal (DE) | Mechanism (optimal) |
|------:|-----------:|-----------:|-------------:|-------------:|---------------------|
| 1     | 40         | 40         | **12**       | **20**       | `DAD H` (DE: XCHG wrap) |
| 2     | 80         | 80         | **24**       | **32**       | `DAD H` × 2 |
| 3     | 120        | 120        | **36**       | **44**       | `DAD H` × 3 |
| 4     | 160        | 160        | **48**       | **56**       | `DAD H` × 4 |
| 5     | 200        | 200        | **60**       | **68**       | `DAD H` × 5 |
| 6     | 240        | 240        | **72**       | **80**       | `DAD H` × 6 |
| 7     | 280        | 280        | **84**       | **92**       | `DAD H` × 7 |
| 8     | 16 (O62)   | 16         | 16           | 16           | byte move (implemented) |
| 9     | 36         | 36         | **28** / 20  | **28** / 20  | `MOV A,Lo; ADD A; MOV Hi,A; [MVI Lo,0]` |
| 10    | 56         | 56         | **32** / 24  | **32** / 24  | `ADD A` × 2 |
| 11    | 76         | 76         | **36** / 28  | **36** / 28  | `ADD A` × 3 |
| 12    | 96         | 96         | **40** / 32  | **40** / 32  | `ADD A` × 4 |
| 13    | 116        | 116        | **44** / 36  | **44** / 36  | `ADD A` × 5 |
| 14    | 136        | 136        | **40** / 32  | **40** / 32  | `MOV A,Lo; RRC×2; ANI 0xC0; MOV Hi,A; [MVI Lo,0]` |
| 15    | 156        | 156        | **36** / 28  | **36** / 28  | `MOV A,Lo; RRC×1; ANI 0x80; MOV Hi,A; [MVI Lo,0]` |

*Second cost column (after `/`) is when `DstLo` has no consumers and `MVI Lo,0` is dropped (item 1 / 2).*

### `SRL16` (logical right shift)

| ShAmt | Today | Optimal (HL) | Optimal (DE) | Mechanism (optimal) |
|------:|------:|-------------:|-------------:|---------------------|
| 1     | 44    | 44           | 44           | keep current (per-bit RAR; trick loses — see below) |
| 2     | 88    | 88           | 88           | keep current per-bit RAR |
| 3     | 132   | **100**      | **108**      | 24-bit trick: `XRA A; (DAD H; ADC A)×5; MOV L,H; MOV H,A` |
| 4     | 176   | **84**       | **92**       | 24-bit trick, 4 iters |
| 5     | 220   | **68**       | **76**       | 24-bit trick, 3 iters |
| 6     | 264   | **52**       | **60**       | 24-bit trick, 2 iters |
| 7     | 308   | **36**       | **44**       | 24-bit trick, 1 iter |
| 8     | 16 (O62) | 16        | 16           | byte move (implemented) |
| 9     | 40    | **36** / 28  | **36** / 28  | `MOV A,Hi; RRC; ANI 0x7F; MOV Lo,A; [MVI Hi,0]` |
| 10    | 64    | **40** / 32  | **40** / 32  | rotate-and-mask, 2 RRC |
| 11    | 88    | **44** / 36  | **44** / 36  | rotate-and-mask, 3 RRC |
| 12    | 112   | **48** / 40  | **48** / 40  | rotate-and-mask, 4 RRC |
| 13    | 136   | **44** / 36  | **44** / 36  | `MOV A,Hi; RLC×3; ANI 0x07; MOV Lo,A; [MVI Hi,0]` |
| 14    | 160   | **40** / 32  | **40** / 32  | rotate-and-mask, 2 RLC |
| 15    | 184   | **36** / 28  | **36** / 28  | rotate-and-mask, 1 RLC |

*Second cost column (after `/`) is when `DstHi` has no consumers and `MVI Hi,0` is dropped (item 4).*

### `SRA16` (arithmetic right shift)

Same opportunities as `SRL16` but the high-half fill is sign-extension
instead of zero. Two adaptations:

* **Byte-lane + one arithmetic step (`ShAmt = 9`)**: keep the cheaper
  special case used by the backend instead of forcing the generic
  rotate-and-mask path. In HL form:
  `MOV A,H; MOV L,H; RLC; SBB A,A; MOV H,A; MOV A,L; RLC; MOV A,L; RAR; MOV L,A`.
  This is **64cc / 10B**, versus **72cc / 13B** for the generic mask-and-merge
  scheme.
* **Rotate-and-mask form (`ShAmt = 10..14`)**: after computing the surviving
  bits in `A`, store that masked low result in `DstLo`, then rebuild the full
  sign splat with `MOV A,SrcHi; RLC; SBB A,A` (+16cc). `MOV Hi,A` writes the
  high byte, and `ANI high-mask ; ORA Lo` splats sign into the discarded low-byte
  bits when the top bit of the result is bit 15 of `x`.
  For `ShAmt = 15` the result is `0 or -1` and reduces to
  `MOV A,Hi; RLC; SBB A,A; MOV Hi,A; MOV Lo,A`.
* **24-bit trick form (3..7)**: pre-load `A` with `sign(SrcHi)`
  (`MOV A,SrcHi; RLC; SBB A,A` — 16cc) instead of `XRA A`. `ADC A`
  then correctly propagates sign through the rotation. Net: +12cc vs
  the SRL version, still 100..200cc cheaper than today for N ≥ 3.

## Pseudo redesign (item 9 / item 10)

Today a single pseudo per direction (`V6CLANG_SHL16` / `V6CLANG_SRL16` /
`V6CLANG_SRA16`) implicitly clobbers `A` and `FLAGS` because *some* of its
expansion paths use the accumulator. The DAD-H-based paths do not need
A. Conflating them blocks the register allocator from keeping a hot i8
value in A across the shift.

Split each pseudo by codegen strategy:

| New pseudo | Inputs | Clobbers | Strategy |
|------------|--------|----------|----------|
| `V6CLANG_SHL16_DAD_HL` | HL | HL, FLAGS | `DAD H × N` (N=1..7) — leaves A alone |
| `V6CLANG_SHL16_DAD_DE` | DE | DE, HL_tmp, FLAGS | `XCHG ; DAD H × N ; XCHG` (N=1..7) — leaves A alone |
| `V6CLANG_SHL16_AVIA`   | any GR16 | DstPair, A, FLAGS | current per-bit ADD A,A loop (only as fallback when both HL and DE busy) |
| `V6CLANG_SHL16_BYTE`   | any GR16 | DstPair, FLAGS | byte-lane (N == 8) |
| `V6CLANG_SHL16_RAM_HI` | any GR16 | DstPair, A, FLAGS | rotate-and-mask in A (N = 9..15) |
| `V6CLANG_SRL16_RAR_DE` | any GR16 | DstPair, A, FLAGS | current RAR loop (N = 1..2 only) |
| `V6CLANG_SRL16_24BIT_HL` | HL | HL, A, FLAGS | 24-bit trick (N = 3..7) — requires HL |
| `V6CLANG_SRL16_24BIT_DE` | DE | DE, HL_tmp, A, FLAGS | XCHG-wrapped 24-bit trick (N = 3..7) |
| `V6CLANG_SRL16_BYTE`   | any GR16 | DstPair, FLAGS | N = 8 |
| `V6CLANG_SRL16_RAM_LO` | any GR16 | DstPair, A, FLAGS | rotate-and-mask (N = 9..15) |
| `V6CLANG_SRA16_…`      |          |          | symmetric variants |

* Instruction selection picks the strategy from the constant `ShAmt`
  and the available physical register (or emits a copy hint preferring
  HL/DE).
* `V6CLANG_*_DAD_DE` variants explicitly mark `HL` as clobbered to expose
  the XCHG wrap to the allocator (item 10) — allows DE pairs to be
  shifted without spilling, easing register pressure that a strict
  `requires HL` policy would create.
* Adding a non-HL path for the DAD strategies (item 10) prevents the
  "out of regs" failures already observed in regression tests when the
  shift target is forced into HL.

## Rotate-and-mask cookbook (per ShAmt)

Let `lo = SrcLo`, `hi = SrcHi`, `Dlo = DstLo`, `Dhi = DstHi`.

### SHL16 N=9..13 — ADD A method (cheapest for left shift within byte)

```
MOV A, Lo              ; 8cc
ADD A     × (N - 8)    ; 4cc each
MOV Hi, A              ; 8cc
MVI Lo, 0              ; 8cc      — OMIT if DstLo has no consumers (item 1)
```

Total: 24 + 4·(N−8) cc with `MVI Lo,0`, 16 + 4·(N−8) cc without. Range
**28..44cc** (or **20..36cc** with omitted MVI).

`ADD A` is preferred over `RLC` here because it shifts a 0 into bit 0
— exactly what left shift needs — so no `ANI` mask is required. `RLC`
wraps bit 7 into bit 0 and would need an extra 8cc `ANI` to clean up.

### SHL16 N=14..15 — RRC + ANI method (fewer surviving bits than rotations needed)

At N=14 only 2 bits survive in Hi; at N=15 only 1. `RRC` reaches them
in fewer cycles than `ADD A` can shift them up.

```
MOV A, Lo              ; 8cc
RRC       × (8 - (N % 8))  ; 4cc each  — N=14: 2 RRC, N=15: 1 RRC
ANI mask               ; 8cc        — N=14: 0xC0, N=15: 0x80
MOV Hi, A              ; 8cc
MVI Lo, 0              ; 8cc        — OMIT if DstLo has no consumers (item 2)
```

Total:
* N=14: 8+8+8+8+8 = **40cc**, or **32cc** without `MVI Lo,0`.
* N=15: 8+4+8+8+8 = **36cc**, or **28cc** without `MVI Lo,0`.

### SHL16 N=9..15 (single live byte = high)

*Strategy chosen by ShAmt:* N≤1– ADD A method above; N≥14– RRC+ANI
method above. The two are equal-cost at N=13 (44cc); choose ADD A there
for mask-free simplicity.

### SRL16 N=9..15 (single live byte = low)

```
MOV A, hi              ; 8cc
<RRC × (N-8)>          if N ≤ 12       4cc each
<RLC × (16-N)>         if N ≥ 13       4cc each
ANI ((1<<(16-N)) - 1)  ; 8cc           mask = bottom (16-N) bits
MOV Lo, A              ; 8cc
MVI Hi, 0              ; 8cc           OMIT if DstHi has no consumers (item 4)
```

Total: 32 + 4·min(N−8, 16−N) cc with `MVI Hi,0`,
24 + 4·min(N−8, 16−N) cc without. Range **36..48cc** (or **28..40cc**).

### SRL16 N=1..2 — keep current per-bit RAR loop (24-bit trick loses)

For `N ∈ {1, 2}` the 24-bit trick is **more expensive** than the
current per-bit RAR loop:

| N | per-bit RAR (current) | 24-bit trick (HL) | winner |
|---|----------------------:|------------------:|--------|
| 1 | 44cc                  | 132cc             | per-bit (88cc cheaper) |
| 2 | 88cc                  | 116cc             | per-bit (28cc cheaper) |
| 3 | 132cc                 | 100cc             | trick   |

The trick has a fixed overhead of `20cc` (`XRA A` + `MOV L,H` + `MOV H,A`)
plus `16cc × (8-N)` iterations. The per-bit RAR cost is roughly `44cc × N`.
Crossover is at N ≈ 2.47, so N=1, N=2 stay with the current sequence:

```
; current SRL16 N=1..2 expansion (unchanged from V6ClangInstrInfo.cpp)
for i in 0..N:
    MOV A, Hi         ; 8cc
    ORA A             ; 4cc    (skipped on first iter if priorClearsCarry)
    RAR               ; 4cc
    MOV Hi, A         ; 8cc
    MOV A, Lo         ; 8cc
    RAR               ; 4cc
    MOV Lo, A         ; 8cc
```

Per iter: 44cc (or 40cc on the first one when CY is already clear).

### SRL16 N=3..7 — 24-bit trick (HL form)

```
XRA A                   ; A = 0    (4cc)
<DAD H ; ADC A> × (8-N) ; (16cc each)
MOV L, H                ; result_lo = bits [N+7..N]   (8cc)
MOV H, A                ; result_hi = bits [15..N+8]  (8cc)
```

Total: 20 + 16·(8−N) cc.

When source/dest is DE: `XCHG ; XRA A ; ((DAD H; ADC A) × (8-N)) ; MOV L,H ; MOV H,A ; XCHG` = 28 + 16·(8−N) cc.

### SHL16 N=1..7 — DAD H form

```
DAD H × N
```
12·N cc when HL; +8cc XCHG wrap when DE.

## Worked example — `x << 15` (matches user item 3, item 2)

```asm
; SrcReg = HL, DstReg = HL
MOV A, L     ; 8
RRC          ; 4
ANI 0x80     ; 8
MOV H, A     ; 8
MVI L, 0     ; 8    ; OMIT if low byte of result has no consumer
; 36cc total, 7B  (28cc, 5B with omitted MVI)
```

vs. current `<<15` path (byte move + 7 × ADD A,A on DstHi):
`MOV H,L ; MVI L,0 ; (MOV A,H ; ADD A,A ; MOV H,A) × 7` = 16 + 7·20 = 156cc.
**Saves 120cc per occurrence.**

## Worked example — `x >> 7` (matches user item 8)

```asm
; SrcReg = HL, DstReg = HL, A clobbered
XRA A        ; 4
DAD H        ; 12
ADC A        ; 4
MOV L, H     ; 8
MOV H, A     ; 8
; 36cc total, 5B  (32cc if A known 0 on entry)
```

vs. current 7-iter RAR loop = 308cc. **Saves 272cc per occurrence.**

## Benefit summary

* **SHL16 N=1..7**: 28..196cc per shift (DAD H replaces A-domain loop).
* **SHL16 N=9..13**: 8..72cc per shift (ADD A method, no mask).
* **SHL16 N=14..15**: 96..120cc per shift (RRC + ANI).
* **SRL16 N=3..7**: 32..272cc per shift (24-bit trick).
* **SRL16 N=9..15**: 4..148cc per shift (rotate-and-mask).
* **Bonus**: omitting the trailing `MVI Lo,0` / `MVI Hi,0` saves an
  extra **8cc + 2B** per occurrence whenever the discarded half has no
  consumers — common when the result is immediately narrowed (cast to
  `int8_t` / `uint8_t`) or used only by another shift that overwrites
  the half.
* **SRA16 N=3..15** (excluding N=8): comparable savings minus 12..16cc
  sign-prep overhead.

In aggregate this is the largest per-occurrence saving in the V6CLANG
shift pipeline — shifts of 7, 14, 15 (common in bit-packing /
unpacking, scaling by 128, pixel index math) drop by an order of
magnitude.

## Implementation notes

1. **Selection point**: extend `LowerSHL_i16` / `LowerSRL_i16` /
   `LowerSRA_i16` in
   [V6ClangISelLowering.cpp](../../llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp)
   to emit a strategy-specific `V6ClangISD::*` node carrying `(Val, ShAmt)`.
   The strategy is chosen purely from the constant `ShAmt`.
2. **Pseudo expansion**: implement each `V6CLANG_*` variant in
   `V6ClangInstrInfo::expandPostRAPseudo`. The DAD-H pseudos use neither
   A nor the per-bit loop, so their `Defs` list omits `A` (item 9).
3. **DE-via-XCHG path** (item 10): pseudo expansion wraps the DAD
   sequence in `XCHG / XCHG`. List `HL` as a clobber so the allocator
   accounts for the temporary.
4. **Mask folding / SRA edge cases**: for logical shifts, `ShAmt = 9`
  and `ShAmt = 15` still fall naturally out of the mask formulas with
  one RLC/RRC. For arithmetic shifts, keep a dedicated `ShAmt = 9`
  byte-lane + one-step path, while `ShAmt = 15` reduces to the direct
  sign-splat sequence above.
5. **Dead high/low half elimination** (items 1, 2, 4): when the discarded
   half (`DstLo` for SHL N≥9, `DstHi` for SRL N≥9) has no consumers,
   omit the final `MVI r, 0`. Two implementations possible:
   * **Selection-time** (preferred): at `LowerSHL_i16` / `LowerSRL_i16`,
     when the SDNode's only user is an `EXTRACT_SUBREG` of the surviving
     half (or a `TRUNCATE` to i8), emit a strategy variant whose pseudo
     produces an i8 result, not an i16 pair. The dead half never exists.
   * **Post-RA peephole**: after expansion, scan for `MVI r, 0` whose
     def is dead at the next instruction and erase it. Cheaper to
     implement but slightly less reliable than the selection-time path.
6. **Variable-amount fallback**: unchanged — still routed through
   `__ashlhi3` / `__lshrhi3` / `__ashrhi3`.
7. **Interaction with O75** (flag-producing arith): the rotate-and-mask
   path leaves the Z flag set by the final `ANI`, which O75 may
   consume for a following compare-against-zero. Document as a side
   benefit, no new code required.

## Risk

Medium. Many small code paths, all selected by constant amount.
The strategy choice is purely a cost-table lookup; once the per-amount
expansion is correct, the optimization is provably profitable (no
phase-ordering interactions because the rewriting happens at lowering
time).

## Test plan

* For each `(direction, ShAmt)` with ShAmt ∈ 1..15, compile a tiny
  function and check the emitted byte/cycle count against the table.
* Reuse [temp/o57_shr16_chain.c](../../temp/o57_shr16_chain.c),
  [temp/o57_all_shifts.c](../../temp/o57_all_shifts.c) and
  [temp/o57_shift_chain_16bit.c](../../temp/o57_shift_chain_16bit.c)
  as smoke tests.
* New benchmark: shift-heavy kernel (pixel scaling, CRC) under
  `tests/benchmarks_c/`.
* Re-run full benchmark suite (`tests/benchmarks_c/run_benchmarks.py`)
  and confirm no regressions; expect measurable gains on `bsort`,
  `fib_crc`, `sieve`, anything that touches `>> 1` / `<< N` in inner
  loops.

## Dependencies

* O62 (whole-byte specialization) — already merged; this builds on it.
* O75 (flag-producing arithmetic) — neutral; rotate-and-mask path
  preserves Z-from-ANI for downstream use.
* No conflict with O57 (variable-amount cross-BB chaining); O86
  obsoletes the constant-amount portion of O57's motivation.

## Status

Proposed.
