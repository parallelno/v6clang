# O68. Wide Shift-Left / Rotate by 1 via `DAD H`

*Companion to [O67 — i8 Rotate ISel via RLC/RRC](O67_i8_rotate_isel_via_rlc_rrc.md)
(extends the rotate idea from i8 to i16/i24/i32) and to
[O62 — Efficient i16/i8 Shift Expansion (constant amount)](O62_efficient_shift_expansion.md)
(O62 covers byte-lane shifts only; this plan covers shift-left **by 1**, an amount O62 leaves untouched).*

## Problem

The 8080 has no multi-byte left-shift or rotate instruction, so today
LLVM expands `i16 x << 1`, `i24 x << 1`, and `i32 x << 1` (and the
matching `rotl` / `rotr` by 1) as a chain of byte-wise rotates through
the accumulator and carry:

```
;--- i16 x <<= 1 (current expansion, DstReg == SrcReg path) ---
MOV  A, L      ; 8cc
RAL            ; 4cc  ; CY <- bit7(L), L <- (L<<1)|0
MOV  L, A      ; 8cc
MOV  A, H      ; 8cc
RAL            ; 4cc  ; H <- (H<<1)|CY
MOV  H, A      ; 8cc
```

6 instructions, 6 bytes, **40cc** — and that is the **best-case** path
already. For `i24` / `i32` it grows to 9 / 12 bytes and 60 / 80cc.
Worse, the same pattern is used to synthesise `rotl x, 1` from
`(x << 1) | (x >> (N-1))` because LLVM expands `ISD::ROTL` for wide
types into shift-or pairs — making `rotl i16 x, 1` cost roughly twice
the shift.

But the i8080 has a *single-byte, single-instruction* idiom for this
exact case: **`DAD H`** (`HL = HL + HL`, **12cc, 1B**) — equivalent to
`HL <<= 1` with `CY ← old bit 15`. The bit that fell out is captured
in `CY`, which makes it a near-perfect primitive both for wider
shifts (chain `RAL`s above the low 16 bits) and for rotates (fold
`CY` into bit 0 of the low byte). All cycle counts in this plan use
[Vector-06c timings](../../docs/V6ClangInstructionTimings.md): `DAD`=12,
`MOV r,r`=8, `INR r`=8, `RAL`/`RLC`=4, `XCHG`=4, `ACI`=8, `JNC`=12
(fixed, regardless of taken/not-taken).

## Pattern

### `i16 x << 1`

```
DAD  H            ; HL <<= 1, CY = old bit15           (12cc, 1B)
```

**1 instruction, 1 byte, 12cc** — vs. 6B / 40cc today. Δ = **−5B, −28cc**.
Also: A is **not** clobbered (the current expansion routes through A).

### `i24 x << 1` (low 16 in `HL`, high byte in `A`)

```
DAD  H            ; HL <<= 1, CY = old bit15           (12cc, 1B)
RAL               ; A   = (A<<1) | CY, CY = old bit23  (4cc, 1B)
```

**2 instructions, 2 bytes, 16cc** — *if* the high byte is already in
`A`. The carry chains naturally from `DAD H` into `RAL`. Δ vs. the
byte-wise lowering (3× MOV/RAL pair = 60cc / 9B): **−7B, −44cc**.

If the high byte is in some other register `r` (not `A`), add
`MOV A,r` (8cc) + `MOV r,A` (8cc) framing → 32cc / 4B. Still **−5B,
−28cc** vs. today.

### `i32 x << 1` (low 16 in `HL`, high 16 in `DE`)

With the *high* half in `HL` and the *low* half in `DE` on entry,
`DAD H` + `XCHG` chains the shift across both halves without ever
touching `A`:

```
; Entry: HL = high16, DE = low16
DAD  H            ; HL = high<<1, CY = bit31 (lost — ok, this is a shift)
                  ;                                    (12cc, 1B)
XCHG              ; HL = low16,   DE = high<<1         ( 4cc, 1B)
DAD  H            ; HL = low<<1,  CY = bit15(low)      (12cc, 1B)
JNC  .done        ;                                    (12cc, 3B, fixed)
INX  D            ; DE += 1  → sets bit0(E) = bit16    ( 8cc, 1B)
.done:
; Result: DE = high half of (i32 << 1), HL = low half.
```

**5 instr, 7 bytes, 40cc not-taken / 48cc taken**, and `A` is
preserved.

This sequence is **shift-only** — it relies on `bit31` being
discarded. A rotate would need `bit31` to wrap into `bit0` of the
low half, but it has to survive the second `DAD H`, which overwrites
`CY`. There is no cheap way to stash and restore `CY` across a `DAD`
on the 8080, so `rotl i32, 1` is **out of scope** for this plan and
stays on the existing Expand path.

### `rotl i16 x, 1` (carry-fold variant)

After `DAD H` the bit that fell out is in `CY` and bit 0 of `L` is
zero. Folding `CY` back into bit 0 of `L` completes the rotation.
Two equivalent lowerings:

```
;--- branchless (clobbers A) ---
DAD  H            ; HL <<= 1, CY = old bit15           (12cc, 1B)
MOV  A, L         ;                                    ( 8cc, 1B)
ACI  0            ; A = L + 0 + CY = L | CY (bit0 was 0)( 8cc, 2B)
MOV  L, A         ;                                    ( 8cc, 1B)
; total: 4 instr, 5B, 36cc
```

```
;--- branchful (does NOT clobber A) ---
DAD  H            ;                                    (12cc, 1B)
JNC  .done        ;                                    (12cc, 3B, fixed)
INR  L            ; safe: bit0(L) = 0 here             ( 8cc, 1B)
.done:
; total: 24cc not-taken / 32cc taken, 5B; A preserved
```

**3 instr + label, 5B, 24–32cc**. Both win heavily over today’s
shift-or-pair expansion (a `V6CLANG_SHL16` + `V6CLANG_SRL16,15` + `OR` chain
of ~12B / ~80cc).

The **branchful form has a real secondary advantage**: it does **not
clobber `A`**. Today every wide shift goes through `A`, so the
caller's accumulator value must be re-materialised after the shift.
A preserved-`A` rotate slots into longer expressions without forcing
an extra spill/reload — a win the cost model should recognise even
when raw cycle counts tie. (The branchless `ACI 0` form clobbers `A`
like today's expansion, so it has no liveness advantage.)

### `rotl i24 x, 1`

Same shape as `rotl i16`: do the i24 shift-left chain (`DAD H; RAL`),
then fold the *final* `CY` (the wrap bit) into bit 0 of `L` via
`JNC .done; INR L; .done:`. The branchless `ACI 0` form is awkward
here because the carry has to be transported from the high byte (where
the chain ends) back down to `L`; the branchful form is the correct
choice.

`rotl i32, 1` is **not** covered by this plan — see the note in the
i32 shift section above.

### Direction & ROTR

`rotr x, 1` on i16 is `rotl x, N-1` and is normally lowered the other
way. Two options:

1. **Reuse**: canonicalise `rotr x, 1` → `rotl x, N-1` and reuse this
   pattern. For `N=16` that means 15 left rotates — *not* a win.
2. **Direct**: implement `rotr x, 1` separately as
   `RAR`-chain-from-top-down + carry-fold into bit 7 of the high byte.
   Same shape, mirrored. Profile data should determine whether to ship
   this; common code rotates *left* by 1 (CRC, hashes) far more often
   than right by 1 on multi-byte values, so phase 1 implements only
   `rotl …, 1`.

### Why not extend `DAD` higher?

The 8080 has no `DAD-with-carry`, so chaining `DAD` for the upper
halves is impossible. The `RAL` chain is the correct next step above
the bottom 16 bits.

## Implementation

Two coordinated edits, both confined to the V6CLANG target.

### 1. `expandPostRAPseudo` in [V6ClangInstrInfo.cpp](../../llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp)

For `V6CLANG_SHL16` with constant amount `1`, replace the existing
`MOV A,L; RAL; MOV L,A; MOV A,H; RAL; MOV H,A` sequence with:

```cpp
case V6CLANG::V6CLANG_SHL16:
  if (Amt == 1 && DstReg == SrcReg) {       // common after coalescing
    BuildMI(MBB, MI, DL, get(V6CLANG::DADrp), V6CLANG::HL)
        .addReg(V6CLANG::HL).addReg(V6CLANG::HL);
    MI.eraseFromParent();
    return true;
  }
  // … existing fallback for Amt ∈ 1..7 with DstReg ≠ SrcReg, and
  //    O62 byte-lane path for Amt ≥ 8.
```

Same site handles the `DstReg ≠ SrcReg` case after a 16-bit copy
(`MOV DstHi,SrcHi; MOV DstLo,SrcLo`) — not worth a special case unless
benchmarks demand it.

### 2. `LowerROTL` for i16 (and optionally i24) in `V6ClangISelLowering.cpp`

Mirror the `LowerROTL` path introduced by [O67](O67_i8_rotate_isel_via_rlc_rrc.md):

```cpp
SDValue V6ClangTargetLowering::LowerROTL(SDValue Op, SelectionDAG &DAG) const {
  EVT VT = Op.getValueType();
  SDValue X   = Op.getOperand(0);
  ConstantSDNode *NCst = dyn_cast<ConstantSDNode>(Op.getOperand(1));
  if (!NCst) return SDValue();          // variable amount → keep Expand
  unsigned N = NCst->getZExtValue() % VT.getSizeInBits();
  if (N != 1) return SDValue();         // only ±1 lowered today

  if (VT == MVT::i16) {
    // Custom node V6ClangISD::SHL16_1_CARRY — defs (i16, glue), lowered to DAD H.
    // Then carry-fold via JNC/INR L pseudo, or via ACI 0 + MOV L,A.
    …
  }
  // i24: emit V6ClangISD::SHL_WIDE_1 with multi-result + glue. i32 rotate stays Expand.
  return SDValue();
}
```

The carry fold itself is best implemented as a small post-RA pseudo
expansion (it needs a fresh local label) rather than at SDAG level.

### 3. `V6ClangInstrInfo.td` — Pat<> entries

```
def : Pat<(shl GR16:$x, (i8 1)),
          (DADrp $x, $x)>;             // routed via copyPhysReg if not in HL
```

A wider `Pat<>` for `rotl GR16:$x, 1` requires the carry-fold pseudo
described above and so lives in C++ rather than TableGen.

## Complexity & Risk

- **Complexity:** Low for the i16 `shl 1` case (~10 LOC in
  `expandPostRAPseudo`). Medium for the rotate path (needs the
  carry-fold pseudo and label-creating expansion). Medium-High for
  the i24/i32 cases (multi-result SDAG nodes with glue).
- **Risk:** Very Low for `i16 shl 1` (`DAD H` is encoding-clean and
  flag side effects match `RAL`-chain output for the bits the chain
  defined; CY is already considered clobbered by either lowering).
  Low-Med for the rotate path: needs careful interaction with
  `V6ClangRedundantFlagElim` so the carry consumed by the fold is not
  optimised away.
- **Dependencies:** None hard. Composes naturally with:
  - **[O40 — ADD16 DAD-Based Expansion](O40_add16_dad_expansion.md)** (✅): same
    `DAD` infrastructure already wired in.
  - **[O62](O62_efficient_shift_expansion.md)** (✅): O62 handles
    `Amt ∈ 8..15`; this plan handles `Amt == 1`. Disjoint.
  - **[O67](O67_i8_rotate_isel_via_rlc_rrc.md)** (✅): provides the
    `LowerROTL` skeleton this plan extends to i16/i24 (i32 rotate
    stays on Expand).
  - **[O17 — Redundant Flag Elimination](O17_redundant_flag_elimination.md)** (✅):
    add `DAD H` to its CY-clobber whitelist (same treatment as
    `DAD rp`).

## Expected Savings

All cycle counts use the canonical [V6ClangInstructionTimings.md](../../docs/V6ClangInstructionTimings.md)
values (`DAD`=12, `MOV r,r`=8, `INR r`=8, `RAL`=4, `JNC`=12, `XCHG`=4, `ACI`=8).

| Pattern               | Before (B / cc) | After (B / cc)        | Δ              |
|-----------------------|-----------------|-----------------------|----------------|
| `i16 x << 1`          | 6 / 40          | 1 / 12                | −5B / −28cc   |
| `i24 x << 1` (hi in A)| 9 / 60          | 2 / 16                | −7B / −44cc   |
| `i24 x << 1` (hi in r)| 9 / 60          | 4 / 32                | −5B / −28cc   |
| `i32 x << 1` (preserves A) | 12 / 80    | 7 / 40–48             | −5B / −32–40cc |
| `rotl i16 x, 1` (br)  | ~12 / ~80       | 5 / 24–32             | −7B / −48cc   |
| `rotl i16 x, 1` (br-less) | ~12 / ~80   | 5 / 36                | −7B / −44cc   |
| `rotl i24 x, 1`       | ~16 / ~100      | 4–6 / 28–40           | −10B / −60cc  |

Beyond raw size/cycles, the **branchful rotate path preserves `A`**,
which the cost model should reward when `A` is live across the rotate.

**Frequency:**
- `i16 x << 1` and `x + x` of i16: **High**. Common in pointer math,
  fixed-point doubling, table indexing where the index is an i16.
  Already shows up in `bsort` / `sieve` benchmarks.
- `rotl i16 x, 1`: **Low–Medium**. CRC and hash kernels.
- i24/i32 cases: **Low**. Mostly long-arithmetic helpers and
  fixed-point routines.

The high-frequency `i16 << 1` win alone justifies the plan; the
rotate/wide cases ride on the same primitive at incremental cost.

## Pitfalls

- **`DAD H` requires HL.** If the value is in `DE` or `BC`, an
  `XCHG` (1B/4cc) brings it to `HL`, costing back some of the win.
  Net is still positive (`MOV+RAL` chain at 40cc is worse than
  `XCHG; DAD H; XCHG` at 20cc), but the cost model needs the right
  answer. RA already prefers HL for shifted/added i16 values after
  O40, so this is rarely the deciding factor.
- **No `DAD`-with-carry on the 8080.** Crossing a 16-bit boundary
  needs a carry-in, and `DAD H` doesn’t accept one. For `i32 << 1`
  the carry is sidestepped by the `XCHG`-between-two-`DAD`s trick,
  which works *because* `bit31` is discarded by a shift. The same
  trick does **not** extend to `rotl i32, 1` (where `bit31` must
  survive), so wide rotates above i24 are left on the existing
  Expand path.
- **Flag side effects.** `DAD H` writes only `CY`; `RAL` writes only
  `CY`. The existing chain also clobbered only `CY` (the `MOV` and
  `ORA A` framing on the SRL path do *not* appear in SHL). No
  flag-elim regression expected, but add `DAD H` / `DAD rp` to the
  whitelist if not already there ([O17](O17_redundant_flag_elimination.md)).
- **Rotate by 1 vs. rotate by N-1.** Phase 1 lowers `rotl i16 x, 1`
  only; `rotr i16 x, 1` keeps Expand (or reuses i16 SHL+SRL fallback).
  Adding the symmetric path is mechanical follow-up.
- **`i32 x << 1` is not the headline.** It saves 5B and ~36cc —
  real, but smaller in relative terms than the i16/i24 cases because
  half the work still depends on the `XCHG`/`JNC` framing. The
  `A`-preservation property may matter more than the cycle delta in
  practice.

## Comparison With Other Backends

- **AVR.** `add Rd, Rd; adc Rd+1, Rd+1` is the exact analogue of
  `DAD H` and is already used by AVR's expander. V6CLANG is closing a
  parity gap.
- **Z80 (llvm-z80).** Uses `add hl, hl` (same opcode as 8080's
  `DAD H`) for `i16 << 1`. The llvm-z80 backend has it; we don't.
- **6502 (llvm-mos).** No equivalent — the 6502 ALU is byte-only,
  so it falls back to a per-byte `ASL`/`ROL` chain identical to our
  current expansion.

## Estimated Effort

- **Phase 1** — `i16 x << 1`: **already de-facto implemented** at
  `-O2` and not worth a dedicated patch. The chain `LowerSHL_i16`
  ([V6ClangISelLowering.cpp lines 778-810](../../llvm/lib/Target/V6Clang/V6ClangISelLowering.cpp#L778))
  rewrites `shl x, 1` as `add x, x` (an i16 SDAG `ADD`), which is
  legal; the post-RA `V6CLANG_ADD16` expander already contains the
  `DstReg == HL && (Lhs == HL || Rhs == HL) → DAD rp` fast path
  ([V6ClangInstrInfo.cpp ≈ line 670](../../llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp#L670))
  introduced by [O40](O40_add16_dad_expansion.md). RA already prefers
  HL for shifted/added i16 values, so the predominant shape is
  `add hl, hl` → `DAD H` (1B / 12cc). Verified end-to-end on a
  driver where `unsigned short dbl(unsigned short x){return x<<1;}`
  emits exactly `DAD H; RET`. The unrolled ADD-self chain inside
  `V6CLANG_SHL16` for `ShAmt < 8` is therefore **unreachable code** at
  `-O2`. No Phase 1 patch is needed.

- **Phase 2** — `i16 rotl x, 1` with carry-fold: ~30–50 LOC
  spread across `V6ClangInstrInfo.{cpp,td}` and `V6ClangISelLowering.{h,cpp}`.
  The branchless `DAD H; MOV A,L; ACI 0; MOV L,A` (4 instr / 5 B /
  36 cc, clobbers A like today's expand) is the recommended landing:
  no labels, no MBB split, single `expandPostRAPseudo` arm. The
  branchful `DAD H; JNC .done; INR L; .done:` form preserves A but
  needs label emission this backend has no precedent for; ship it
  as a follow-up only if profile data shows A-liveness across the
  rotate is common.

- **Phase 3** — i24/i32 shift + i24 rotate: revised estimate
  **~150–200 LOC**, not the original ~80. Deeper investigation of
  the V6CLANG target ([V6ClangISelLowering.cpp:53](../../llvm/lib/Target/V6Clang/V6ClangISelLowering.cpp#L53))
  shows there is **no existing i32 ALU customisation at all**: no
  `setOperationAction` for any i32 op, no `ReplaceNodeResults` hook,
  no `ADDC`/`ADDE`/`UADDO`/`SHL_PARTS` handling, no `SHL_I32`/`SRL_I32`
  RTLIB names registered. The default integer type-legalizer splits
  `i32 << 1` into `(lo<<1, srl(lo,15)|hi<<1)` — i.e. a **`V6CLANG_SRL16`
  by 15** (byte-lane move + 7×RAR) plus an **i16 OR** — yielding
  the ~12B/80cc baseline cited above. Replacing it with the target
  `DAD H; XCHG; DAD H; JNC; INX D` sequence requires:
  1. a new `V6ClangISD::SHL32_1` SDNode with `SDTypeProfile<2, 2, ...>`
     and `SDNPOutGlue` to thread CY across two `DAD H`s;
  2. a `ReplaceNodeResults` override (currently absent) intercepting
     the type-legalizer before it produces the SRL+OR sequence;
  3. a new post-RA pseudo whose expansion creates a fresh `MCSymbol`
     and either splits the MBB (CFG mutation — cannot live in
     `expandPostRAPseudo`, needs a dedicated post-RA pass like
     `V6ClangSPTrickOpt`) or invents a `V6CLANG_LABEL` pseudo (no precedent
     in the V6CLANG backend);
  4. cost-model gating to handle suboptimal RA placement (low-half
     in BC adds `MOV` framing that erodes the win, mirroring the
     `V6CLANG_ADD16` non-HL framing logic);
  5. fixing or working around the pre-existing i32 sub-register
     livein verifier issue flagged in `add-i32.ll`.

  In addition, **i24 has no IR shape today** — C has no `_BitInt(24)`
  shape that survives type promotion to i32, no `MVT::i24` references
  in the V6CLANG tests, and no benchmark exercises a 24-bit integer.
  The plan's i24 cases would be unreachable in practice; recommend
  dropping them from Phase 3 scope. `rotl i32, 1` remains out of
  scope (CY cannot survive the second `DAD H`).

Recommended landing order: skip Phase 1 (already covered);
implement Phase 2 (small, self-contained, real CRC/hash win);
defer Phase 3 indefinitely unless an `i32 << 1` pattern appears
in a benchmark, since it costs ~200 LOC and inventing a label-
emission idiom for a code shape that isn't currently exercised.

## Summary

`DAD H` is the missing primitive for wide left shift / rotate by 1 on
the 8080. **Phase 1** (i16 `shl` by 1) turns out to be already covered
at `-O2` by the chain of `LowerSHL_i16` (rewrites to `add x, x`) +
O40's `V6CLANG_ADD16 → DAD rp` fast path — no patch is needed.
**Phase 2** (`rotl i16 x, 1` carry-fold) is the actual headline
landing: ~30–50 LOC for a **7–9B / 50cc** win on every CRC/hash
rotate. **Phase 3** (i24/i32 wide shift) is much larger than the
original ~80 LOC estimate — ~200 LOC of net-new infrastructure
(custom multi-result SDAG node, `ReplaceNodeResults` override,
label-emission idiom or new post-RA pass) for code shapes (i24,
`i32 << 1`) that do not appear in any current benchmark. Defer
Phase 3 indefinitely; `rotl i32, 1` stays out of scope permanently
— `bit31` cannot survive the second `DAD H`.
