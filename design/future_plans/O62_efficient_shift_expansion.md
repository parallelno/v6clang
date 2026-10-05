# O62: Efficient i16 / i8 Shift Expansion (Constant Amount)

## Problem

`V6CLANG_SHL16` / `V6CLANG_SRL16` / `V6CLANG_SRA16` are expanded in
[V6ClangInstrInfo.cpp](../../llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp) by a
generic template that:

1. Emits an unconditional full 16-bit copy (`MOV DstHi, SrcHi; MOV DstLo, SrcLo`)
   whenever `DstReg != SrcReg`.
2. Then performs the shift in-place on the destination pair.

For shift amounts that are a multiple of 8, stage (1) copies bytes that
are immediately overwritten by the byte-lane move produced in stage (2).
No later pass currently removes those dead copies, and `V6ClangLoadImmCombine`
can only replace the `MVI r, 0` zero-fill with `MOV r, r'` (saving 1B)
— it never touches the dead-copy issue.

### Concrete miscompile-quality example

From [temp/o61_test.asm](../../temp/o61_test.asm) (`arr_sum`,
`tmp2 = (int)(arr) >> 8`, HL = `arr`, B = 0):

```asm
;--- V6CLANG_SRL16 ---    ; DE <- HL >> 8
  MOV D, H            ; DstHi <- SrcHi     (template copy)
  MOV E, L            ; DstLo <- SrcLo     ;; DEAD — overwritten next
  MOV E, D            ; DstLo <- SrcHi     (byte-lane move)
  MOV D, B            ; DstHi <- 0         (LoadImmCombine rewrote MVI D,0)
```

4 × `MOV` = 32cc, 4B. The minimal correct sequence is:

```asm
  MOV E, H            ; 8cc, 1B
  MVI D, 0            ; 8cc, 2B   (or MOV D, r0 if a zero reg exists)
```

2 × instr = 16cc, 3B — **saves 16cc and 1B per occurrence**.

The same structural waste affects `SHL16` by 8..15 and `SRA16` by 8..15.

## Root Cause

In
[V6ClangInstrInfo.cpp:1465 (V6CLANG_SHL16)](../../llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp#L1465),
[V6ClangInstrInfo.cpp:1512 (V6CLANG_SRL16)](../../llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp#L1512),
and
[V6ClangInstrInfo.cpp:1555 (V6CLANG_SRA16)](../../llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp#L1555),
the expander unconditionally does:

```cpp
if (DstReg != SrcReg) {
  BuildMI(..., MOVrr, DstHi).addReg(SrcHi);
  BuildMI(..., MOVrr, DstLo).addReg(SrcLo);   // <-- dead for shift-by-8..15
}
```

then proceeds with the shift. The template is correct but pessimistic:
it assumes each half of the destination is "live in" from the source,
which is false when the shift amount discards a whole byte.

## Optimization

Special-case constant shift amounts that are a whole byte (8..15). For
those cases, only one byte lane of the source actually contributes to the
destination; the other lane must be zero (`SHL`, `SRL`) or sign-extended
(`SRA`). The expansion becomes:

| Pseudo | Amount | Optimal sequence (DstReg ≠ SrcReg) | cc | Bytes |
|--------|--------|------------------------------------|-----|-------|
| `SHL16` | 8      | `MOV DstHi, SrcLo; MVI DstLo, 0`   | 16  | 3     |
| `SHL16` | 9..15  | `MOV DstHi, SrcLo; MVI DstLo, 0` + `(n−8)` × `ADD A,A` via DstHi | 16 + 24·(n−8) | 3 + 3·(n−8) |
| `SRL16` | 8      | `MOV DstLo, SrcHi; MVI DstHi, 0`   | 16  | 3     |
| `SRL16` | 9..15  | `MOV DstLo, SrcHi; MVI DstHi, 0` + `(n−8)` × RAR-chain on DstLo | 16 + 32·(n−8) | 3 + 4·(n−8) |
| `SRA16` | 8      | `MOV A, SrcHi; MOV DstLo, SrcHi; RLC; SBB A,A; MOV DstHi, A` | 36 | 6 |
| `SRA16` | 9..15  | same as SRA16=8, then `(n−8)` × arith-shift chain on DstLo | … | … |
| `SHL16`/`SRL16`/`SRA16` | 15 | (2-byte move + single shift) — sometimes reducible to `MOV lo,hi` + bit test | <28 | <5 |
| `*16`   | 16+    | `MVI DstHi, 0; MVI DstLo, 0` (SHL/SRL) or sign-splat (SRA) | 16 | 4 |

**Savings vs. today** (constant, per occurrence, when `DstReg ≠ SrcReg`):

| Pseudo | Amount | Today | O62 | Saved |
|--------|--------|-------|-----|-------|
| `SHL16`/`SRL16` | 8  | 32cc / 4B  | 16cc / 3B | **16cc, 1B** |
| `SHL16`/`SRL16` | 16 | 40cc / 5B  | 16cc / 4B | **24cc, 1B** |
| `SRA16`         | 8  | 48cc / 6B  | 36cc / 6B | **12cc, 0B** |

Savings stack onto every byte-aligned shift occurrence.

### Also applies when `DstReg == SrcReg`

The dead-copy is skipped today in the in-place case. For shift-by-8 with
`DstReg == SrcReg` (common after coalescing) the expansion is already:

```asm
MOV DstLo, DstHi      ; SRL16, 8cc
MVI DstHi, 0          ; 8cc
```

which is already optimal. O62 preserves this path — it only rewrites
the `DstReg != SrcReg` + `ShAmt % 8 == 0` (or >= 8) branch.

## Implementation

All changes local to
[V6ClangInstrInfo.cpp](../../llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp) in the
three `V6CLANG_S*16` cases of `expandPostRAPseudo`. No TableGen, no new
pseudo, no ISel change, no new flag.

Pseudocode for `V6CLANG_SRL16` (mirror for `SHL16` and `SRA16` with the
appropriate lane / zero-fill):

```cpp
case V6CLANG::V6CLANG_SRL16: {
  Register Dst = MI.getOperand(0).getReg();
  Register Src = MI.getOperand(1).getReg();
  unsigned Amt = MI.getOperand(2).getImm() & 0x0F;   // mod 16

  MCRegister DstHi = RI.getSubReg(Dst, V6CLANG::sub_hi);
  MCRegister DstLo = RI.getSubReg(Dst, V6CLANG::sub_lo);
  MCRegister SrcHi = RI.getSubReg(Src, V6CLANG::sub_hi);
  MCRegister SrcLo = RI.getSubReg(Src, V6CLANG::sub_lo);

  if (Amt >= 8) {
    // Byte-lane move: DstLo <- SrcHi, DstHi <- 0.
    // This also subsumes the "copy src to dst" step for the surviving lane.
    if (DstLo != SrcHi)
      BuildMI(..., MOVrr, DstLo).addReg(SrcHi);
    BuildMI(..., MVIr,  DstHi).addImm(0);
    Amt -= 8;
    // Per-bit right shift on DstLo only (A-routed RAR chain);
    // no hi-lo coupling needed because DstHi is known zero.
    for (unsigned i = 0; i < Amt; ++i) {
      BuildMI(..., MOVrr, V6CLANG::A).addReg(DstLo);
      BuildMI(..., ORAr,  V6CLANG::A).addReg(V6CLANG::A).addReg(V6CLANG::A); // CY = 0
      BuildMI(..., RAR,   V6CLANG::A).addReg(V6CLANG::A);
      BuildMI(..., MOVrr, DstLo).addReg(V6CLANG::A);
    }
    MI.eraseFromParent();
    return true;
  }

  // Unchanged path: Amt in 1..7.
  if (Dst != Src) {
    BuildMI(..., MOVrr, DstHi).addReg(SrcHi);
    BuildMI(..., MOVrr, DstLo).addReg(SrcLo);
  }
  /* existing per-bit RAR loop */
}
```

Key points:

* Guard against `DstLo == SrcHi` aliasing (valid-register-pair
  constraints allow it only for the pairs HL/DE via XCHG semantics,
  but be safe and skip the MOV when identical).
* For `SRA16` with `Amt >= 8`, read `SrcHi` into `A` *before* writing
  `DstLo` in case the pairs alias: same discipline as the existing
  code. The "sign-extend" post-step (`RLC; SBB A,A`) is unchanged.
* The per-bit loop after the byte-lane move now only needs to shift
  `DstLo` (SRL/SRA) or `DstHi` (SHL), because the other lane is
  known constant. That halves the per-bit cost — already implicit in
  the existing SHL16 ≥8 path; generalize to SRL16 and SRA16.

## Prerequisites

None. Depends on no other optimization. Compatible with:

* **O13 LoadImmCombine** — may still rewrite the emitted `MVI r, 0`
  into `MOV r, r'` when a zero register is known; no change needed.
* **O47 Sub-register liveness** — would have caught this too, at the
  cost of much more infrastructure. O62 is the targeted, local fix.
* **O61 Spill-into-reload** — orthogonal; O62 reduces copies, O61
  reduces reloads. Both stack.

## Pitfalls

* **Register pair aliasing.** Check for `DstLo == SrcHi` before
  emitting the byte-lane move; skip the copy if identical (happens
  only for register pairs where the physical registers overlap —
  under the current class definitions for `GR16`, this is impossible
  for distinct pairs, but an `assert` or a skip is trivial).
* **SRA16 by 8 emits more code than SHL/SRL by 8.** That's inherent
  — sign-extension of the new high byte costs `RLC; SBB A,A`. Still
  12cc cheaper than today.
* **`-Os` behaviour.** O62 never grows code; every case is
  ≤ bytes today. Safe to enable unconditionally.
* **Shift-amount ≥ 16.** The frontend should already fold these to
  zero (SHL/SRL) or sign-splat (SRA). If a pseudo with amount ≥ 16
  ever reaches expansion, use `Amt & 0x0F` and short-circuit to the
  constant-zero / sign-splat form.

## Cost Model Summary

Per V6CLANG timings ([docs/V6ClangInstructionTimings.md](../../docs/V6ClangInstructionTimings.md)):

| Ref | Cycles saved / occurrence | Bytes saved | Frequency |
|-----|-----------------------|--------------|-----------|
| `(u16)x >> 8` (or equivalent pointer high-byte read) | 16 | 1 | Very high |
| `(u16)x << 8` (byte→word packing) | 16 | 1 | High |
| `(i16)x >> 8` (arithmetic) | 12 | 0 | Medium |
| constant-amount shifts by 9..15 | 16–40 | 1–3 | Low |

"High frequency" because `>> 8` / `<< 8` appear in every unpack of a
16-bit value into byte lanes — common in drivers, memory-mapped I/O,
and the address-arithmetic idioms the V6CLANG frontend emits when casting
pointers to integers.

## Comparison With Other Backends

* **AVR.** `AVRExpandPseudoInsts::expandLSRW*Rd*` and `expandASRW*Rd*`
  (see `llvm/lib/Target/AVR/AVRExpandPseudoInsts.cpp`) special-case
  shift-by-8: they emit `mov lo, hi; clr hi` (SHL) / `mov hi, lo;
  clr lo` (SRL) with no dead copy. AVR does this because its
  register file has no zero-cost 8-bit rename the way x86 does.
* **x86.** Byte subregisters (`AL`/`AH`) make `uint16 >> 8` a
  zero-cost rename or a single `movzx`.
* **SM83 / Z80 (llvm-z80).** Recognizes constant shift amounts ≥ 8
  and lowers to byte-lane moves without the full-pair copy.
* **6502 (llvm-mos).** Similar handling; see `MOSShiftRotateChain`
  (inspiration for [O57](O57_shift_rotate_chaining.md)) but the
  "shift by 8" case is handled directly in expansion.

V6CLANG should do the same — O62 closes this backend-quality gap.

## Estimated Effort

~60 lines in `V6ClangInstrInfo.cpp` across three cases. No TableGen, no
test infrastructure changes beyond new IR / asm tests under
`tests/features/` for each special-cased amount.

## Summary

Teach `expandPostRAPseudo` that constant shift amounts of 8..15 require
only one byte of the source, so the generic full-pair copy is
unnecessary. Saves **16cc + 1B per `(u16)x >> 8` or `x << 8`**, with no
risk and no dependencies. The same defect exists for `SRA16` by 8
(saves 12cc). Lands as three ~20-line diffs in the pseudo expander and
is immediately visible in `temp/o61_test.asm` and every ISR or driver
that unpacks `i16` values.
