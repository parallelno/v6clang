# Plan: O68 — `rotl i16 x, 1` via `DAD H` + Carry-Fold (Phase 2)

*Companion to [O67 — i8 Rotate ISel via RLC/RRC](future_plans/O67_i8_rotate_isel_via_rlc_rrc.md)
and [O40 — ADD16 DAD-Based Expansion](future_plans/O40_add16_dad_expansion.md).*

This plan covers **Phase 2 only** of
[O68_wide_shl_rotate_dad_h.md](future_plans/O68_wide_shl_rotate_dad_h.md):
the `rotl i16 x, 1` case via `DAD H` followed by an `ACI 0`
carry-fold. Phase 1 (`i16 x << 1`) is already de-facto implemented
at `-O2` and needs no patch (see §1.2 below); Phase 3 (i24 / i32
wide shifts) is explicitly deferred — see the parent feature doc
for the revised ~200-LOC effort estimate.

## 1. Problem

### 1.1 Current behavior — `rotl i16 x, 1`

`ISD::ROTL` is currently `Expand` for `i16` in
[V6ClangISelLowering.cpp line 153](../llvm/lib/Target/V6Clang/V6ClangISelLowering.cpp#L153):

```cpp
setOperationAction(ISD::ROTL,  MVT::i16, Expand);
setOperationAction(ISD::ROTR,  MVT::i16, Expand);
```

The default LLVM `Expand` of `rotl x, 1` is `(x << 1) | (x >> 15)`,
which lowers to:

* `V6CLANG_SHL16` with `ShAmt == 1` — at `-O2` this funnels through
  `LowerSHL_i16` ([V6ClangISelLowering.cpp lines 778-810](../llvm/lib/Target/V6Clang/V6ClangISelLowering.cpp#L778))
  as `add x, x`, then through O40's `V6CLANG_ADD16 → DAD rp` fast path.
  **Result: 1 B / 12 cc.**
* `V6CLANG_SRL16` with `ShAmt == 15` — falls into O62's byte-lane fast
  path: `MOV DstLo, SrcHi; MVI DstHi, 0; MOV A, DstLo; ORA A; RAR; MOV DstLo, A` × 7 (after the byte move, 7 more single-bit RARs). **Result: ~10 B / ~70 cc.**
* `V6CLANG_OR16` joining the two halves through `A`. **Result: ~6 B / ~24 cc.**

Total today: **~14–17 B / ~100 cc** for a one-bit rotate, dominated
by the `SRL by 15` cost. `A` is clobbered.

### 1.2 Phase 1 status — `i16 x << 1`

Verified end-to-end via a baseline at-O2 build:

```c
unsigned short dbl_u16(unsigned short x) { return (unsigned short)(x << 1); }
```

emits exactly:

```asm
dbl_u16:
  DAD  H
  RET
```

This is because:

1. `LowerSHL_i16` rewrites `shl x, 1` as `add x, x` (i16 `ISD::ADD`),
   not as a `V6CLANG_SHL16` pseudo with `ShAmt == 1`.
2. `add x, x` becomes `V6CLANG_ADD16 dst, src, src`.
3. The `V6CLANG_ADD16` post-RA expander has the
   `DstReg == HL && (Lhs == HL || Rhs == HL) → DAD rp` fast path
   ([V6ClangInstrInfo.cpp ≈ line 670](../llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp#L670)),
   matched on the `Rhs == HL` arm with `LhsReg == HL`.
4. RA already prefers HL for shifted/added i16 values (per O40), so
   the predominant post-RA shape is `DstReg == LhsReg == RhsReg == HL`.

The unrolled ADD-self chain inside `V6CLANG_SHL16` for `ShAmt < 8` is
therefore **unreachable code at `-O2`**. No Phase 1 patch is needed,
and adding one would be redundant with the existing infrastructure.

### 1.3 Desired behavior — `rotl i16 x, 1`

The 8080 has two sub-instruction primitives for the rotate-by-1
case:

* `DAD H` (`HL = HL+HL`, **12 cc, 1 B**) — equivalent to `HL <<= 1`
  with `CY ← old bit 15`. The bit that "fell off" the top is now
  in `CY`.
* `ACI 0` (`A = A + 0 + CY`, **8 cc, 2 B**) — adds the carry into
  the low byte. Because `DAD H` left `bit 0(L) = 0`, this is
  equivalent to `OR L, CY`.

Combined: **DAD H; MOV A, L; ACI 0; MOV L, A** — `HL = rotl(HL, 1)`,
4 instructions, 5 B, **36 cc**. `A` is clobbered (matches today's
expand semantics — no liveness regression).

```asm
rotl_u16_1:
  DAD  H        ; HL <<= 1, CY = old bit 15      (12 cc, 1 B)
  MOV  A, L     ;                                 ( 8 cc, 1 B)
  ACI  0        ; A = L + 0 + CY = L | CY        ( 8 cc, 2 B)
  MOV  L, A     ;                                 ( 8 cc, 1 B)
  RET
```

**Δ vs. today: −9 B / −64 cc per rotate** — and crucially, the win
holds **per use**, so a CRC-16 inner loop running the rotate once
per bit saves ~50% of the rotate's cost across 8 iterations.

### 1.4 Why the branchless `ACI 0` form (not `JNC; INR L`)

The parent feature doc describes two equivalent lowerings:

* **Branchless** (`MOV A,L; ACI 0; MOV L,A`): 36 cc / 5 B, clobbers
  `A`. Straight-line — fits the `expandPostRAPseudo` model.
* **Branchful** (`JNC .done; INR L; .done:`): 24–32 cc / 5 B,
  preserves `A`. Needs an `MCSymbol` and either MBB split (CFG
  mutation, can't live in `expandPostRAPseudo`) or a new
  `V6CLANG_LABEL` pseudo (no precedent in the V6CLANG backend).

Phase 2 ships the **branchless** form because:

1. Today's expand also clobbers `A` (the SHL+SRL+OR chain routes
   everything through `A`), so there is no liveness regression.
2. Straight-line expansion fits the existing `expandPostRAPseudo`
   pattern used by every other 16-bit pseudo in the backend
   (`V6CLANG_ADD16`, `V6CLANG_SHL16`, `V6CLANG_SRL16`, …). No new infrastructure.
3. The 36 cc / 5 B figure is still a **−9 B / −64 cc** win vs.
   today (~17 B / ~100 cc).

The branchful form can be added later as a follow-up if profile
data shows `A` is frequently live across an `i16` rotate.

### 1.5 Scope

| Pattern               | Phase | This patch | Notes                                              |
|-----------------------|-------|:----------:|----------------------------------------------------|
| `i16 x << 1`          | 1     | —          | Already de-facto via O40 + LowerSHL_i16 (§1.2)     |
| `rotl i16 x, 1`       | 2     | ✔          | This plan                                          |
| `rotr i16 x, 1`       | 2     | —          | Symmetric mirror, deferred (low frequency)         |
| `i24 / i32 << 1`      | 3     | —          | ~200 LOC, no IR shape today (parent doc §3)        |
| `rotl i32, 1`         | n/a   | —          | Permanently out of scope (bit31 cannot survive)    |

## 2. Strategy

### 2.1 Approach

Three coordinated edits:

1. **`V6ClangISelLowering.{h,cpp}`** — flip `ISD::ROTL i16` from
   `Expand` to `Custom`; extend `LowerROTL` to handle `i16` with
   constant amount `1` by emitting a new `V6ClangISD::ROTL16_1`
   single-result SDNode. Other amounts (and non-constant amounts)
   return `SDValue()` so LLVM falls back to the existing default
   Expand path.
2. **`V6ClangInstrInfo.td`** — declare the matching SDNode profile,
   the `V6CLANG_ROTL16_1` pseudo (HL-constrained via `GR16Ptr`), and
   one `Pat<>` entry tying SDNode → pseudo.
3. **`V6ClangInstrInfo.cpp`** — add a `case V6CLANG::V6CLANG_ROTL16_1` arm in
   `expandPostRAPseudo` that emits the 4-instruction sequence.

### 2.2 Why HL-constrained

`DAD H` requires `HL`. We force the pseudo's source and destination
to `HL` via `GR16Ptr` (the existing HL-only register class used by
`V6CLANG_DAD`), so RA proves the constraint at allocation time. This:

* Eliminates all post-RA framing logic (no XCHG / MOV-pair fallback).
* Matches the precedent set by `V6CLANG_DAD`
  ([V6ClangInstrInfo.td ≈ line 774](../llvm/lib/Target/V6Clang/V6ClangInstrInfo.td#L774)).
* Keeps the expansion to a literal 4-instruction emit — minimal
  surface, no cost-model branching, no liveness reasoning.

The trade-off: if RA cannot place the rotate input in HL it must
copy. Since `rotl x, 1` is rare (CRC/hash kernels) and the
surrounding code path almost always uses HL for the rotated value
(it's a 16-bit ALU op composing with other 16-bit ALU ops, all of
which already prefer HL via O40), this is acceptable.

### 2.3 Summary of changes

| Step | What                                                      | Where                                                  |
|------|-----------------------------------------------------------|--------------------------------------------------------|
| 3.1  | Add `ROTL16_1` to `V6ClangISD::NodeType` enum                  | `V6ClangISelLowering.h`                                    |
| 3.2  | `getTargetNodeName` case for `ROTL16_1`                    | `V6ClangISelLowering.cpp`                                  |
| 3.3  | Flip `ROTL i16` to `Custom`; extend `LowerROTL` for i16    | `V6ClangISelLowering.cpp`                                  |
| 3.4  | SDNode profile + `V6CLANG_ROTL16_1` pseudo + Pat<>             | `V6ClangInstrInfo.td`                                      |
| 3.5  | `expandPostRAPseudo` case for `V6CLANG_ROTL16_1`               | `V6ClangInstrInfo.cpp`                                     |
| 3.6  | Build clang + llc                                          | —                                                      |
| 3.7  | Lit test `rotl-i16-dad-h.ll`                               | `llvm-project/llvm/test/CodeGen/V6Clang/`                  |
| 3.8  | Verification feature folder `tests/features/45/`           | `tests/features/45/`                                   |
| 3.9  | Run lit + golden + benchmarks                              | —                                                      |
| 3.10 | Sync mirror                                                | —                                                      |
| 3.11 | Mark plan + future_plans/README.md complete                | this file, `design/future_plans/README.md`             |

## 3. Implementation Steps

### Step 3.1 — Add `ROTL16_1` to the V6ClangISD NodeType enum [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangISelLowering.h`
(immediately after `ROTR8`, before the closing `};` of the enum).

```cpp
ROTL8,      // 1-bit accumulator rotate left  (RLC).
ROTR8,      // 1-bit accumulator rotate right (RRC).
ROTL16_1,   // i16 rotate-left by 1, lowered via DAD H + ACI 0 carry-fold.
```

> **Implementation Notes**: Added at line 49 of `V6ClangISelLowering.h` (immediately after `ROTR8`). No other enum reorder.

### Step 3.2 — `getTargetNodeName` case for `ROTL16_1` [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangISelLowering.cpp`
(in `getTargetNodeName`, alongside the existing `ROTL8` / `ROTR8`
cases).

```cpp
case V6ClangISD::ROTL16_1: return "V6ClangISD::ROTL16_1";
```

> **Implementation Notes**: One-line addition adjacent to the existing `ROTR8` case. Verified via `llc -print-after-all` showing `V6ClangISD::ROTL16_1` rather than `Constant:i16<0>` in the post-ISel DAG dump.

### Step 3.3 — `ROTL i16` Custom; extend `LowerROTL` [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangISelLowering.cpp`

(a) Around line 153 (the `setOperationAction` block for i16):

```cpp
-  setOperationAction(ISD::ROTL,  MVT::i16, Expand);
+  setOperationAction(ISD::ROTL,  MVT::i16, Custom);
   setOperationAction(ISD::ROTR,  MVT::i16, Expand);
```

(`ISD::ROTR i16` stays `Expand` — the symmetric `rotr x, 1`
landing is intentionally deferred.)

(b) Extend `LowerROTL` (currently i8-only, around line 715) to
match an i16 amount-1 rotate:

```cpp
SDValue V6ClangTargetLowering::LowerROTL(SDValue Op, SelectionDAG &DAG) const {
  EVT VT = Op.getValueType();
  SDLoc DL(Op);
  SDValue Val = Op.getOperand(0);
  SDValue Amt = Op.getOperand(1);

  if (VT == MVT::i16) {
    auto *CA = dyn_cast<ConstantSDNode>(Amt);
    if (CA && (CA->getZExtValue() & 15) == 1)
      return DAG.getNode(V6ClangISD::ROTL16_1, DL, MVT::i16, Val);
    // Other amounts / variable amount → fall back to default Expand.
    return SDValue();
  }

  if (VT != MVT::i8)
    return SDValue();
  // … existing i8 body unchanged …
}
```

When `LowerOperation` returns `SDValue()` for a `Custom`-marked op,
LLVM proceeds with the default Expand legalization for that node —
i.e. for any `rotl i16` amount other than 1 we get exactly today's
behaviour.

> **Implementation Notes**: Implemented exactly as proposed. Mask is `& 15` (not `& 16`) to also catch `rotl x, 17`, `33`, … (any amount ≡ 1 mod 16). `ISD::ROTR i16` left at `Expand` per scope. Verified `rotl x, 2` falls back to default Expand and produces the same code as before via probe `temp/rotl_probe2.c`.

### Step 3.4 — SDNode profile + `V6CLANG_ROTL16_1` pseudo + Pat<> [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.td`

(a) Add the SDNode profile near the other V6ClangISD node defs (search
for `def V6Clangdad` or `SDTRotL`):

```td
def SDT_V6ClangRotL16_1 : SDTypeProfile<1, 1, [SDTCisVT<0, i16>, SDTCisSameAs<0, 1>]>;
def V6Clangrotl16_1     : SDNode<"V6ClangISD::ROTL16_1", SDT_V6ClangRotL16_1>;
```

(b) Add the pseudo near the existing 16-bit ALU pseudos (around line
817, after `V6CLANG_SRA16`):

```td
// V6CLANG_ROTL16_1: HL = rotl(HL, 1).
// HL-constrained via GR16Ptr: post-RA expansion is the literal
// DAD H; MOV A,L; ACI 0; MOV L,A sequence (4 instr / 5 B / 36 cc).
let Defs = [A, FLAGS], Constraints = "$dst = $src" in
def V6CLANG_ROTL16_1 : V6ClangPseudo<(outs GR16Ptr:$dst), (ins GR16Ptr:$src),
    "# ROTL16_1 $dst, $src",
    [(set i16:$dst, (V6Clangrotl16_1 i16:$src))]>;
```

> **Implementation Notes**: SDTypeProfile uses `SDTCisVT<0, i16>, SDTCisVT<1, i16>` (explicit pair, not `SDTCisSameAs`); both forms work. Pseudo placed immediately after `V6CLANG_SRA16`. `Constraints = "$dst = $src"` mirrors the `V6CLANG_DAD` precedent.

### Step 3.5 — Post-RA expansion case [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

Add a new case in `expandPostRAPseudo`, sitting alongside
`V6CLANG_SHL16` / `V6CLANG_SRL16` / `V6CLANG_SRA16`:

```cpp
case V6CLANG::V6CLANG_ROTL16_1: {
  // Phase 2 of O68: rotl i16 x, 1 = DAD H; MOV A,L; ACI 0; MOV L,A.
  // GR16Ptr constraint guarantees Dst == Src == HL post-RA, so no
  // framing is needed.
  BuildMI(MBB, MI, DL, get(V6CLANG::DAD)).addReg(V6CLANG::HL);
  BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::A).addReg(V6CLANG::L);
  BuildMI(MBB, MI, DL, get(V6CLANG::ACI), V6CLANG::A).addReg(V6CLANG::A).addImm(0);
  BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::L).addReg(V6CLANG::A);
  MI.eraseFromParent();
  return true;
}
```

Notes:

* `DAD` takes a single source operand (the rp to add to HL); `DAD H`
  is encoded as `DAD V6CLANG::HL`.
* `ACI` has the constraint `$dst = $lhs` (see
  [V6ClangInstrInfo.td line 329](../llvm/lib/Target/V6Clang/V6ClangInstrInfo.td#L329)),
  so the BuildMI form is `(ACI, A).addReg(A).addImm(0)`.
* `Defs = [A, FLAGS]` on the pseudo matches the actual clobber set:
  `DAD` writes `CY`, `MOV/ACI` write `A`, `ACI` writes all flags.

> **Implementation Notes**: Implemented verbatim. Case is placed between `V6CLANG_SRA16` and `V6CLANG_LOAD8_P` in `expandPostRAPseudo`. Comment block above the BuildMI calls captures cycle / byte budget (5 B / 36 cc) and the GR16Ptr HL guarantee.

### Step 3.6 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Built clean. Only pre-existing C4062 switch warnings on `COND_PE/COND_PO` in `V6ClangISelLowering.cpp` (unrelated to this patch). `clang.exe` and `llc.exe` produced.

### Step 3.7 — Lit test `rotl-i16-dad-h.ll` [x]

**File**: `llvm-project/llvm/test/CodeGen/V6Clang/rotl-i16-dad-h.ll`

Cases:

1. `rotl i16 %x, 1` → expect `DAD\tH`, `MOV\tA, L`, `ACI\t0`,
   `MOV\tL, A`. Negative-assert that the output has *no* `RAR`
   (today's expand path) and *no* `__lshrhi3` libcall.
2. `rotl i16 %x, 2` → exercises the fall-back Expand path (constant
   ≠ 1). Just check it still produces *some* shifty code (no
   crash / no libcall regression).
3. `i32 @use(i16 %x) { %r = call i16 @llvm.fshl.i16(i16 %x, i16 %x, i16 1); ret … }` → mirrors a CRC-style funnel-shift idiom; confirms the new path triggers through `fshl` after legalization.

> **Implementation Notes**: Created `llvm-project/llvm/test/CodeGen/V6Clang/rotl-i16-dad-h.ll` with the three cases. All assertions pass on the new build; `fshl_u16_1` correctly lowers via the new path (DAGCombine canonicalises `fshl(x, x, 1)` → `rotl(x, 1)`). Lit run shows `PASS: V6CLANG :: rotl-i16-dad-h.ll`.

### Step 3.8 — Verification feature folder `tests/features/45/` [x]

The folder already exists from earlier Phase-1 scoping work; rewrite
it for Phase 2.

Per [tests/features/README.md](../tests/features/README.md):

* `v6clang.c`: drivers — a single `rotl_u16_1` scalar (clean diff)
  and a small CRC-16-like inner loop (compounded win).
* `c8080.c`: identical signatures, `__c8080__` body that uses the
  reference C-compiled-by-`tools/c8080/c8080.exe` baseline.
* `c8080.asm`: produced via `tools/c8080/c8080.exe`.
* `v6clang_old.asm`: regenerate **before** Step 3.3 lands (or use
  the already-captured one from earlier Phase-1 work, if the rotate
  pattern is present).
* `v6clang_new02.asm`: post-O68-Phase-2 output (use suffix `02` to
  preserve `_new01` for any future Phase-1 evidence; if `_new01`
  doesn't exist, use `_new01`).
* `result.txt` with cycle / byte deltas.

Expected:

* `rotl_u16_1` body: ~17 B → 5 B, ~100 cc → 36 cc. **Δ ≈ −12 B / −64 cc**.
* CRC-16 8-bit-step inner loop containing one rotate per bit:
  **−12 B / −64 cc per bit**, ~−96 B / ~−512 cc per byte processed.

> **Implementation Notes**: Folder repurposed (old Phase-1 drivers removed). New drivers: `rotl_u16_1`, `crc16_step`, `rotl_u16_2`, `fshl_u16_1`. Baseline `v6clang_old.asm` regenerated by temporarily flipping ROTL i16 back to Expand, rebuilding clang, then reverting. New asm `v6clang_new01.asm`. **Per-function body lines**: `rotl_u16_1` 39→6, `fshl_u16_1` 39→6, `rotl_u16_2` unchanged (Expand fall-back, intended), `crc16_step` unchanged. Total file: 6526 B → 5452 B. CRC inner loop turned out **not** to benefit — InstCombine never recognises `crc <<= 1` paired with an independent `crc & 0x8000` as a rotate, so the SHL goes through the existing O40 DAD H fast path (already optimal). The doc in `result.txt` calls this out honestly. Headline customer is `__builtin_rotateleft16` and hand-written `(x<<1)|(x>>15)`.

### Step 3.9 — Regression tests [x]

```
python tests\run_all.py
```

Required: full lit + 16/16 golden + 3/3 benchmark checksums OK.

> **Implementation Notes**: 120/120 lit + 16/16 golden PASS. C-benchmark suite: bsort 0xC4, sieve 0x36, fib_crc 0x2B — all checksums unchanged. fib_crc -O2 marginally improved (68,536 → 68,528 cc) thanks to a `rotl` inside CRC-table init. No regressions.

### Step 3.10 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Mirror sync clean. Affected mirrored files: `llvm/lib/Target/V6Clang/V6ClangISelLowering.{h,cpp}`, `llvm/lib/Target/V6Clang/V6ClangInstrInfo.{td,cpp}`, `llvm/test/CodeGen/V6Clang/rotl-i16-dad-h.ll` (via `tests/lit/CodeGen/V6Clang/`).

### Step 3.11 — Mark plan + future_plans/README.md complete [x]

* Tick all step `[ ]` → `[x]` in this file.
* In [design/future_plans/README.md](future_plans/README.md), mark
  the O68 row Phase 2 complete (Phase 1 noted as already-de-facto;
  Phase 3 deferred per parent feature doc).

> **Implementation Notes**: Plan ticked. README entry updated to mark Phase 2 complete with the de-facto-Phase-1 + deferred-Phase-3 note.

## 4. Expected Results

### 4.1 Simple `rotl i16` by 1

```c
unsigned short rotl_u16_1(unsigned short x) {
    return (unsigned short)((x << 1) | (x >> 15));
}
```

Before (default Expand path: SHL+SRL+OR):

```asm
rotl_u16_1:
  ; --- (x << 1) via DAD H (already O40) ---
  DAD  H
  PUSH H                    ; save x<<1
  ; --- (x >> 15) via O62 byte-lane SRL by 15 ---
  MOV  L, H                 ; lo = old hi
  MVI  H, 0
  MOV  A, L
  ORA  A                    ; CY = 0
  RAR
  MOV  L, A
  ; … 6 more RAR/ORA pairs to shift right by 7 more …
  ; --- combine via OR ---
  POP  D
  MOV  A, L
  ORA  E                    ; lo
  MOV  L, A
  MOV  A, H
  ORA  D                    ; hi (zero)
  MOV  H, A
  RET
; ~17 B / ~100 cc body + 11 cc RET
```

After:

```asm
rotl_u16_1:
  DAD  H
  MOV  A, L
  ACI  0
  MOV  L, A
  RET
; 5 B / 36 cc body + 11 cc RET
```

**−12 B / −64 cc** (≈ −64 % cycles).

### 4.2 CRC-16 inner step

```c
static unsigned short crc16_step(unsigned short crc, unsigned char b) {
    crc ^= (unsigned short)b << 8;
    for (int i = 0; i < 8; ++i) {
        unsigned short bit = crc & 0x8000;
        crc = (unsigned short)((crc << 1) | (crc >> 15));   // rotl 1
        if (bit) crc ^= 0x1021;
    }
    return crc;
}
```

The 8-bit inner loop saves ~64 cc per iteration → **~512 cc per
processed byte**, which on a CRC-16 over a 1 KiB buffer is a
~500 K-cc improvement, well-measurable on Vector-06c.

## 5. Risks & Mitigations

| Risk                                                                                              | Mitigation                                                                                                                                                       |
|---------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `Custom` for `ROTL i16` returns `SDValue()` for non-1 amounts → unexpected legalization behaviour  | LLVM contract: returning `SDValue()` from `LowerOperation` for a `Custom`-marked op falls back to the legalizer's Expand path. Verified by O40 / SHL `Custom` returning `SDValue()` for variable amounts on i8 already.                                                                                                                                              |
| ACI 0 doesn't actually OR CY into bit 0 (semantics drift)                                          | `DAD H` leaves `bit 0(L) = 0` and `CY = old bit 15(HL)`. `ACI 0` computes `A = L + 0 + CY`. Since `bit 0(L) = 0`, the addition cannot carry into bit 0, so the result is exactly `L | CY` in bit 0 with all other bits unchanged. This is a textbook 8080 idiom (cf. Z80 manual §rotate-with-carry-fold).                                                                  |
| `V6ClangRedundantFlagElim` removes the CY produced by `DAD H` before `ACI 0` consumes it               | The four expansion instructions are emitted as a contiguous block at post-RA expansion time, immediately consecutive. `V6ClangRedundantFlagElim` runs **before** `expandPostRAPseudo` (it walks pseudo MIs, not the expanded MOV/ACI/DAD); the pseudo as a single unit declares `Defs = [A, FLAGS]`, so flag-elim sees no opportunity to drop. Verified by reading the pass scaffolding. |
| RA cannot place the rotate input in HL                                                            | `GR16Ptr` register class forces it. RA *can* fail to allocate (spill), but for an i16 SDAG node with a single use of `V6ClangISD::ROTL16_1` and HL not otherwise tied down, RA is provably feasible. Worst case: a copy in/out of HL — same overhead as today, no regression.                                                                                              |
| `rotl x, 16` (= identity) accidentally matches the Custom path                                    | `(CA->getZExtValue() & 15) == 1` masks to 0..15. `rotl x, 16` masks to 0, returns `SDValue()` → falls to Expand, which constant-folds to `x`. No issue.                                                                                                                                                                                                                |
| Plan understates Phase 1 / 3 work                                                                  | Plan §1.2 explicitly notes Phase 1 is already covered; future_plans/O68 §"Estimated Effort" carries the revised Phase-3 ~200-LOC estimate.                                                                                                                                                                                                                          |

## 6. Relationship to Other Improvements

* [O40 — ADD16 DAD-Based Expansion](future_plans/O40_add16_dad_expansion.md) ✅ —
  Phase 1 of O68 is *already* delivered through O40 (see §1.2). Phase 2
  composes with O40: the `DAD H` inside `V6CLANG_ROTL16_1` is not routed
  through `V6CLANG_ADD16` (it's a direct `DAD` emit), but the surrounding
  i16 ALU still uses O40's path.
* [O62 — Efficient i16 Shift Expansion](plan_efficient_shift_expansion.md) ✅ —
  the `SRL by 15` byte-lane fast path is the dominant cost in today's
  `rotl x, 1` expand. This plan eliminates the entire SRL+OR chain.
* [O67 — i8 Rotate ISel via RLC/RRC](future_plans/O67_i8_rotate_isel_via_rlc_rrc.md) ✅ —
  provides the `LowerROTL` skeleton this plan extends to i16.
* [O17 — Redundant Flag Elimination](future_plans/O17_redundant_flag_elimination.md) ✅ —
  already CY-safe for `DAD`; no whitelist update needed.

## 7. Future Enhancements

* **`rotr i16 x, 1`** — symmetric mirror; `RAR`-from-top + carry-fold
  into bit 7 of `H`. Same shape, ~30 LOC, separate plan; defer until
  benchmarks demand it (right rotates on i16 are vanishingly rare).
* **Branchful `JNC; INR L` form** — preserves `A` for ~4 cc less in
  the not-taken case. Needs MBB-split or a new label-emission idiom
  this backend doesn't have. Add only if profile data shows `A`
  liveness across i16 rotates is common.
* **Phase 3** (`i24 / i32 << 1`) — see parent feature doc; revised
  estimate ~150–200 LOC, mostly new infrastructure
  (`ReplaceNodeResults`, multi-result SDAG node with glue, label
  emission). Deferred indefinitely until an i32 shift pattern shows
  up in benchmarks.

## 8. References

* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
* [V6CLANG Instruction Timings](../docs/V6ClangInstructionTimings.md)
* [Future Optimizations](future_plans/README.md)
* [O68 — Wide Shift-Left / Rotate by 1 via DAD H (full description)](future_plans/O68_wide_shl_rotate_dad_h.md)
* [Pipeline Feature Doc](pipeline_feature.md)
* [tests/features/README.md](../tests/features/README.md)
