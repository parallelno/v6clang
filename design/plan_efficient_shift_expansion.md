# Plan: O62 — Efficient i16 Shift Expansion (Constant Amount) — DONE

Status: implemented and validated 2026-04-22. See
[tests/features/32/result.txt](../tests/features/32/result.txt) for the
before/after assembly diff and metrics. Lit coverage:
[shift-i16-byte-aligned.ll](../llvm-project/llvm/test/CodeGen/V6CLANG/shift-i16-byte-aligned.ll)
(new) and updated `srl10_i16` expectation in
[shift-i16.ll](../llvm-project/llvm/test/CodeGen/V6CLANG/shift-i16.ll).

## 1. Problem

### Current behavior

`V6CLANG_SHL16` / `V6CLANG_SRL16` / `V6CLANG_SRA16` in
[V6ClangInstrInfo.cpp](../llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp) expand with
an unconditional full 16-bit copy whenever `DstReg != SrcReg`:

```cpp
if (DstReg != SrcReg) {
  BuildMI(..., MOVrr, DstHi).addReg(SrcHi);
  BuildMI(..., MOVrr, DstLo).addReg(SrcLo);
}
```

For shift amounts `>= 8`, the expansion then moves a single byte lane
from one half to the other and zeroes (or sign-extends) the remaining
half. The first MOV of the leading copy is therefore overwritten and
**dead**, and one of the two halves of the source is never used.

Concrete `V6CLANG_SRL16` example with `SrcReg=HL, DstReg=DE, ShAmt=8`:

```asm
  MOV D, H            ; DEAD — overwritten by MVI D, 0
  MOV E, L            ; DEAD — never read (only Src.hi feeds dst)
  MOV E, D            ; DstLo <- SrcHi (=DstHi after first MOV)
  MVI D, 0            ; (or MOV D, r0 via O13)
```

That is 4 × `MOV` = 32 cc, 4 B. The minimal correct sequence is:

```asm
  MOV E, H            ; 8 cc, 1 B
  MVI D, 0            ; 8 cc, 2 B
```

= 16 cc, 3 B — saves **16 cc and 1 B per occurrence**.

For `V6CLANG_SRL16` and `V6CLANG_SRA16` with `ShAmt > 8`, the per-bit loop after
the byte-lane move continues to shift *both* halves even though one
half is known constant (`0` for SRL, sign byte for SRA). That doubles
the per-bit cost for shift amounts 9..15.

`V6CLANG_SHL16` already has a half-width per-bit loop after the byte move
(only `DstHi` is shifted, since `DstLo == 0`); only its dead-copy needs
fixing.

### i8 shift coverage (verified against [V6ClangISelLowering.cpp](../llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp) lines 601-770)

The i8 shift paths today, and how O62 affects each:

| i8 op | Constant amount lowering | Variable amount lowering | O62 effect |
|-------|--------------------------|--------------------------|------------|
| `shl i8`, 1..7 | `LowerSHL` unrolls into i8 `ADD A, A` repeated | `ZEXT→i16; SHL i16; TRUNCATE` (i16 var → libcall `__ashlhi3`) | **None** — pure i8 ALU, never touches `V6CLANG_SHL16` |
| `srl i8`, 1..7 | `LowerSRL`: `ZEXT i8→i16; V6ClangISD::SRL16(amt); TRUNCATE` | `ZEXT→i16; SRL i16; TRUNCATE` (libcall `__lshrhi3`) | **None** — `ShAmt` always 1..7, hits the unchanged `< 8` branch of `V6CLANG_SRL16` |
| `sra i8`, 1..7 | `LowerSRA`: `SEXT i8→i16; V6ClangISD::SRA16(amt); TRUNCATE` | `SEXT→i16; SRA i16; TRUNCATE` (libcall `__ashrhi3`) | **None** — `ShAmt` always 1..7, hits the unchanged `< 8` branch of `V6CLANG_SRA16` |

**Why O62 does not improve i8 shifts:**

* i8 `shl` constant uses pure i8 `ADD A, A` and never enters the
  16-bit pseudo path that O62 rewrites.
* i8 `srl` / `sra` constant *do* route through `V6CLANG_SRL16` /
  `V6CLANG_SRA16`, but only ever with `ShAmt` in 1..7 (the C standard
  caps i8 shift amounts at 7, and the lowering masks `& 7`). O62
  exclusively rewrites the `ShAmt >= 8` branch, which is unreachable
  from i8 inputs.
* i8 variable shifts are promoted to i16 then dispatched to the
  M11 compiler-rt libcall (`__ashlhi3` / `__lshrhi3` / `__ashrhi3`),
  which is its own runtime routine and unaffected by pseudo expansion.

The design-doc title "i16 / i8 Shift Expansion" is therefore
misleading: the underlying defect described in the doc body — a dead
leading 2-MOV copy followed by a byte-lane move — only exists for
`ShAmt >= 8`, and only i16 constant shifts can reach that branch.
O62 leaves the i8 paths bit-for-bit identical (verified by the
unchanged `srl1_i16` / `sra1_i16` / `srl3_i16` / `sra3_i16` lit
checks in [shift-i16.ll](../tests/lit/CodeGen/V6CLANG/shift-i16.ll), all
of which exercise `ShAmt < 8`).

A separate, future optimization — independent of O62 — could
short-circuit the i8 `srl` / `sra` path by lowering directly to an
i8 RAR/RLC chain instead of round-tripping through `V6CLANG_SRL16` /
`V6CLANG_SRA16` with a known-zero/known-sign high byte. That belongs in
Future Enhancements §7, not in O62 scope.

### Desired behavior

When `ShAmt >= 8`, skip the leading 2-MOV copy entirely and emit only
the byte-lane move from the surviving source half. Also shrink the
per-bit loop to operate on a single byte lane.

### Root cause

The expander uses one generic prologue (`copy Src to Dst if different`)
followed by a transformation that assumes both halves of `Dst` are
live-in from `Src`. For byte-aligned shift amounts the assumption is
false: only one source byte contributes to the result.

---

## 2. Strategy

### Approach: special-case `ShAmt >= 8` before the generic copy

Restructure each of the three pseudo expanders so that the `ShAmt >= 8`
branch is taken *before* the generic `DstReg != SrcReg` copy. The new
branch directly emits the byte-lane move from `SrcHi`/`SrcLo` to the
appropriate destination half, plus the constant fill (`MVI 0` for
SHL/SRL, sign-byte for SRA), and runs a half-width per-bit loop for the
remainder.

Aliasing safety: under V6CLANG's GR16 register classes (BC, DE, HL, PSW),
every pair uses distinct 8-bit registers, so `DstHi`, `DstLo`, `SrcHi`,
`SrcLo` are all distinct — no overlap analysis is required.

### Why this works

* Pure local rewrite of three cases in `expandPostRAPseudo`. No new
  pseudo, no TableGen change, no ISel change.
* Already-correct in-place case (`DstReg == SrcReg`) is preserved
  because the new fast path only emits MOVs that reduce to no-ops
  (skipped) when source and destination halves coincide.
* `expandPostRAPseudo` already runs late enough that physical registers
  and shift amounts are available.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Rewrite `V6CLANG_SHL16` `>=8` branch | Skip leading copy, byte-move directly from `SrcLo` | V6ClangInstrInfo.cpp |
| Rewrite `V6CLANG_SRL16` `>=8` branch | Skip leading copy, byte-move from `SrcHi`, half-width loop | V6ClangInstrInfo.cpp |
| Rewrite `V6CLANG_SRA16` `>=8` branch | Skip leading copy, sign-extend from `SrcHi`, half-width loop | V6ClangInstrInfo.cpp |
| Lit test | New `shift-i16-byte-aligned.ll` exercising `dst != src` cases | tests/lit/CodeGen/V6CLANG |
| Feature test | C test under `tests/features/32` | tests/features/32 |

---

## 3. Implementation Steps

### Step 3.1 — Rewrite `V6CLANG_SHL16` `ShAmt >= 8` path [ ]

**File**: `llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp` (case `V6CLANG::V6CLANG_SHL16`)

Hoist the `ShAmt >= 8` test above the `DstReg != SrcReg` copy. Inside
the byte-aligned branch:

```cpp
// Byte-lane move: DstHi <- SrcLo; DstLo <- 0. No leading full copy.
if (DstHi != SrcLo)
  BuildMI(..., MOVrr, DstHi).addReg(SrcLo);
BuildMI(..., MVIr, DstLo).addImm(0);
ShAmt -= 8;
// Existing per-bit loop on DstHi (already half-width) is reused.
```

When `DstReg == SrcReg`, `DstHi != SrcLo` still holds (e.g.
`H != L`, `D != E`, `B != C`), so this generates the same 2-instruction
sequence as today's in-place expansion.

> **Implementation Notes**: _empty — fill after completion_

### Step 3.2 — Rewrite `V6CLANG_SRL16` `ShAmt >= 8` path [ ]

**File**: same. Mirror the SHL16 change; surviving source half is
`SrcHi`, destination is `DstLo`, fill is `MVI DstHi, 0`. Replace the
post-byte-move per-bit loop with a half-width loop that only shifts
`DstLo` (since `DstHi` is provably 0, its RAR is a no-op):

```cpp
for (unsigned i = 0; i < ShAmt; ++i) {
  BuildMI(..., MOVrr, V6CLANG::A).addReg(DstLo);
  BuildMI(..., ORAr, V6CLANG::A).addReg(V6CLANG::A).addReg(V6CLANG::A); // CY = 0
  BuildMI(..., RAR,  V6CLANG::A).addReg(V6CLANG::A);
  BuildMI(..., MOVrr, DstLo).addReg(V6CLANG::A);
}
```

The `ShAmt < 8` branch is unchanged (full 2-byte per-bit RAR loop).

> **Implementation Notes**: _empty_

### Step 3.3 — Rewrite `V6CLANG_SRA16` `ShAmt >= 8` path [ ]

**File**: same. Surviving half is `SrcHi`, destination of byte move is
`DstLo`, sign-extend `SrcHi` into `DstHi` via `RLC; SBB A,A`. The
per-bit loop after the byte move only needs to shift `DstLo` while
preserving its top bit (sign-preserving 8-bit ASHR — the original sign
is bit 7 of `DstLo`):

```cpp
// Byte-aligned: read SrcHi via A first (it dies after).
BuildMI(..., MOVrr, V6CLANG::A).addReg(SrcHi);
if (DstLo != SrcHi)
  BuildMI(..., MOVrr, DstLo).addReg(SrcHi);
BuildMI(..., RLC,   V6CLANG::A).addReg(V6CLANG::A);          // CY = sign
BuildMI(..., SBBr,  V6CLANG::A).addReg(V6CLANG::A).addReg(V6CLANG::A);
BuildMI(..., MOVrr, DstHi).addReg(V6CLANG::A);
ShAmt -= 8;
// Half-width arithmetic right shift on DstLo only.
for (unsigned i = 0; i < ShAmt; ++i) {
  BuildMI(..., MOVrr, V6CLANG::A).addReg(DstLo);
  BuildMI(..., RLC,   V6CLANG::A).addReg(V6CLANG::A);        // CY = bit 7 = sign
  BuildMI(..., MOVrr, V6CLANG::A).addReg(DstLo);
  BuildMI(..., RAR,   V6CLANG::A).addReg(V6CLANG::A);
  BuildMI(..., MOVrr, DstLo).addReg(V6CLANG::A);
}
```

The `ShAmt < 8` branch is unchanged.

> **Implementation Notes**: _empty_

### Step 3.4 — Build [ ]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

### Step 3.5 — Lit test: shift-i16-byte-aligned [ ]

**File**: `tests/lit/CodeGen/V6CLANG/shift-i16-byte-aligned.ll`

Force `dst != src` by storing the original through a pointer kept live
across the shift:

```ll
define void @srl8_diff(i16 %x, ptr %p, ptr %q) {
  store i16 %x, ptr %p
  %y = lshr i16 %x, 8
  store i16 %y, ptr %q
  ret void
}
```

Add similar functions for `shl by 8`, `shl by 10`, `srl by 10`,
`ashr by 8`, `ashr by 10`. Each `CHECK-NOT` that the dead leading MOV
is gone and `CHECK` for the optimal byte-move sequence.

### Step 3.6 — Run lit subset [ ]

```
llvm-build\bin\llvm-lit -v tests\lit\CodeGen\V6CLANG\shift-i16.ll tests\lit\CodeGen\V6CLANG\shift-i16-byte-aligned.ll
```

### Step 3.7 — Run regression tests [ ]

```
python tests\run_all.py
```

### Step 3.8 — Verification assembly steps from `tests\features\README.md` [ ]

Compile `tests/features/32/v6clang.c` to `v6clang_new01.asm`, compare
with `v6clang_old.asm`, iterate if needed.

### Step 3.9 — Make sure result.txt is created [ ]

Per `tests\features\README.md` `result.txt` structure.

### Step 3.10 — Sync mirror [ ]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

---

## 4. Expected Results

### Example 1 — `unsigned x; ... = x >> 8;` with `dst != src`

Before: 4 × MOV / MVI (32 cc, 4 B).
After: `MOV DstLo, SrcHi; MVI DstHi, 0` (16 cc, 3 B).
Saves 16 cc, 1 B per occurrence.

### Example 2 — `int x; ... = (int)x >> 8;` with `dst != src`

Before: 2 × MOV (leading copy) + RLC/SBB/MOV sign-ext block (48 cc, 8 B).
After: sign-ext block routed through `SrcHi` directly (32 cc, 6 B).
Saves 16 cc, 2 B.

### Example 3 — `(u16)x >> 10`

Before: leading 2-MOV + byte move + 2 × full-pair RAR loop (16 instr).
After: byte move + 2 × single-byte RAR loop (10 instr).
Saves ~32 cc, 6 B.

### Example 4 — `unsigned x; ... = x << 8;` with `dst != src`

From the `shl8_diff` baseline in
[tests/features/32/v6clang_old.asm](../tests/features/32/v6clang_old.asm)
the current `V6CLANG_SHL16(BC←HL, 8)` expansion emits:

```asm
  MOV B, H        ; DEAD — overwritten by byte-move below
  MOV C, L        ; DEAD — value never read after the next MOV
  MVI A, 0        ; (O13 LoadImmCombine rewrote the post-byte-move MVI L,0)
  MOV H, C        ; DstHi <- SrcLo
  MOV L, A        ; DstLo <- 0
```

After O62 the leading 2-MOV pair vanishes:

```asm
  MOV H, C        ; DstHi <- SrcLo (single byte-lane move)
  MVI L, 0        ; (or MOV L, A via O13 if A=0 already)
```

Saves 16 cc, 1 B per occurrence — same magnitude as the SRL example.

### Non-improvement — i8 right shifts (for the record)

```c
unsigned char y = (unsigned char)((unsigned int)x >> 3);   // SRL16 amt=3
signed char   z = (signed char)((int)x >> 3);              // SRA16 amt=3
```

These reach `V6CLANG_SRL16` / `V6CLANG_SRA16` with `ShAmt = 3` — the unchanged
`< 8` branch. O62 emits exactly the same code as today for these.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Aliasing of `DstHi` with `SrcLo` (or `DstLo` with `SrcHi`) | GR16 pairs are disjoint; guard with `if (Dst != Src)` skip when identical. |
| Per-bit loop shrink miscompiles `SRA16` (sign bit lost) | Original sign bit is preserved in `DstLo` bit 7 after the byte move; per-bit loop uses `MOV A, DstLo; RLC` to materialise the sign each iteration. |
| In-place case (`DstReg == SrcReg`) regression | New code emits the same 2-instruction sequence (`MOV DstHi, SrcLo; MVI DstLo, 0`) as the old in-place path. |
| Existing lit tests fail | Existing `shift-i16.ll` tests use `dst == src` (in-place after coalesce) and remain unchanged. |

---

## 6. Relationship to Other Improvements

* **O13 LoadImmCombine** — may still rewrite the emitted `MVI r, 0`
  into `MOV r, r'` when a zero register is known; orthogonal.
* **O42 Liveness-Aware Pseudo Expansion** — orthogonal; O62 reduces
  copies, O42 elides PUSH/POP. Stack.
* **O47 Sub-register liveness** — would also catch this, at far
  greater infrastructure cost. O62 is the targeted local fix.
* **O61 Spill-into-reload** — orthogonal.

## 7. Future Enhancements

* Extend to `ShAmt == 15` special case using bit-test pattern.
* Apply the same byte-aligned fast path to `V6CLANG_SHL/SRL/SRA` i32 (when
  added).
* **Direct i8 right-shift lowering.** Today
  [LowerSRL](../llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp) and
  `LowerSRA` for i8 zero/sign-extend to i16 and route through
  `V6CLANG_SRL16` / `V6CLANG_SRA16` with `ShAmt` 1..7. The high byte is
  known constant (0 for SRL, sign for SRA) but that information is
  lost by post-RA expansion, so the per-bit loop pointlessly shifts
  both halves and a final `TRUNCATE` discards the high byte. A
  dedicated i8 lowering would emit a pure i8 `ORA A; RAR` (SRL) or
  `MOV A,r; RLC; MOV A,r; RAR` (SRA) chain and skip the i16 round
  trip, saving ~12 cc + 3 B per i8 right shift. **Out of O62 scope**
  — requires its own ISel work (new `V6ClangISD::SRL8` / `SRA8` nodes
  or pure-DAG expansion in `LowerSRL` / `LowerSRA`).
* **Pre-existing trunc-store ISel gap (discovered while building O62
  test 32).** Code like `unsigned char y = x >> 3; *q = y;` (where
  `x` is `unsigned char`) crashes ISel with
  `Cannot select: ch = store<...trunc to i8> ... SRL16 build_pair(reg, 0), 3`.
  The pattern reaches a `truncstore i8` of a `V6ClangISD::SRL16` result
  that has no selection rule. Same crash for `signed char y = x >> 3`.
  Workaround: introduce an explicit i16 temporary
  (`unsigned int t = x; *q = t >> 3;`). The fix belongs in
  `V6ClangInstrInfo.td` (add a truncstore pattern) or in `LowerSRL`/`LowerSRA`
  (return an i8-valued node directly when input is i8). **Filed as
  follow-up; not blocking O62.**

## 8. References

* [O62 design](future_plans/O62_efficient_shift_expansion.md)
* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md)
* [Future Improvements](future_plans/README.md)
* [Pipeline Feature Workflow](pipeline_feature.md)
