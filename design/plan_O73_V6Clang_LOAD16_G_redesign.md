# Plan: V6CLANG_LOAD16_G Redesign — `dst=BC` Shape Dispatch

Source design: [O73 V6CLANG_LOAD16_G Redesign](future_plans/O73_V6CLANG_LOAD16_G_redesign.md)

## 1. Problem

### Current behavior

`V6CLANG_LOAD16_G` is the 16-bit load-from-global-address pseudo:

```tablegen
let mayLoad = 1 in
def V6CLANG_LOAD16_G : V6ClangPseudo<(outs GR16:$dst), (ins imm16:$addr),
    "# LOAD16G $dst, $addr", []>;
```

The post-RA expander in `V6ClangInstrInfo::expandPostRAPseudo()`
(`case V6CLANG::V6CLANG_LOAD16_G:`, ~line 1883) handles three `dst` shapes:

| dst | Current expansion                                        | Bytes / Cycles |
|-----|----------------------------------------------------------|----------------|
| HL  | `LHLD addr`                                              | 3B / 20cc      |
| DE  | `XCHG; LHLD addr; XCHG` (always, even when HL dead)      | 5B / 28cc      |
| BC  | `[PUSH H;] LHLD; MOV B,H; MOV C,L; [POP H]`              | 7B / 64cc (HL live), 5B / 36cc (HL dead via O42) |

The `dst=HL` arm is already optimal. The `dst=DE` arm pays a leading
`XCHG` (4cc / 1B) unconditionally, even when HL is dead and the
leading swap is unnecessary. The `dst=BC` arm is one-size-fits-all:
when HL is live across the pseudo it unconditionally pays the
`PUSH H` / `POP H` round-trip, even when a strictly cheaper LDA-pair
shape is available.

### Desired behavior

For `dst=DE`, the expander dispatches on observable post-RA
liveness of `HL`:

| Predicate            | Shape                          | Bytes / Cycles |
|----------------------|--------------------------------|----------------|
| `HL` dead            | `LHLD addr; XCHG`              | 4B / 24cc      |
| `HL` live (fallback) | `XCHG; LHLD addr; XCHG`        | 5B / 28cc      |

For `dst=BC`, the expander dispatches on observable post-RA
liveness of `HL` and `A`:

| Predicate                        | Shape                                                     | Bytes / Cycles |
|----------------------------------|-----------------------------------------------------------|----------------|
| `HL` dead                        | `LHLD addr; MOV B,H; MOV C,L`                             | 5B / 36cc      |
| `HL` live, `A` dead              | `LDA addr; MOV C,A; LDA addr+1; MOV B,A`                  | 8B / 48cc      |
| `HL` live, `A` live              | `PUSH H; LHLD; MOV B,H; MOV C,L; POP H` (unchanged)       | 7B / 64cc      |

Saves 16cc (at +1B) on the common middle row vs the current
unconditional 64cc fallback. The `HL` dead row matches today's O42
fast path.

### Root cause

The original expander considers only one preservation lever
(`PUSH H`/`POP H`) and one predicate (`isRegDeadAtMI(HL)`). On V6CLANG,
`LDA addr` directly reads any 16-bit absolute address byte into `A`
in 16cc — splitting a 16-bit absolute load into two 8-bit absolute
loads when `A` is free is strictly cheaper than wrapping the
16-bit load in PUSH/POP HL whenever `A` is unused.

The structural reason the choice belongs in the expander (not in
the pseudo's `Defs` declaration) is identical to O71's: RA cannot
selectively spill `A` per-instance; declaring `Defs = [A, HL]`
would force `A` spills across every global load even on the
dst=HL shape that does not touch `A` at all.

---

## 2. Strategy

### Approach: per-shape expansion with cheap-first preservation

Keep `V6CLANG_LOAD16_G` exactly as declared today (`(outs GR16:$dst),
(ins imm16:$addr)`, no `Defs`). Replace the body of the `dst=BC`
arm in `case V6CLANG::V6CLANG_LOAD16_G:` with a three-way dispatch on
`(HLDead, ADead)`:

1. **HL dead** → `LHLD; MOV B,H; MOV C,L`. Already today's O42 path;
   unify it under the new dispatch.
2. **HL live, A dead** → emit two `LDA` with the second addressing
   `addr+1`. Never touches HL.
3. **HL live, A live** → unchanged `PUSH H` / `POP H` wrap. Universal
   fallback.

`dst=HL` and `dst=DE` arms are unchanged.

### Why this works

- **Pressure-friendly.** RA still sees the pseudo as preserving
  every non-`$dst` register, so it does not insert spills around
  global loads.
- **Honest at expansion time.** All three shapes are clobber-free
  for the registers each leaves alone (`A` for the `LHLD` shapes;
  `HL` for the `LDA`-pair shape). When a shape's clobbered register
  is live, the expander either picks a different shape or wraps
  PUSH/POP.
- **Reuses existing liveness machinery.** `isRegDeadAtMI` (already
  used by O42 for the `HLDead` skip) covers both predicates. No
  new helper is needed.

### Summary of changes

| Step | What                                                                 | Where                                          |
|------|----------------------------------------------------------------------|------------------------------------------------|
| Rewrite expander | Three-way dispatch in `dst=BC` arm                       | V6ClangInstrInfo.cpp `case V6CLANG::V6CLANG_LOAD16_G:`     |
| (No change) | `V6CLANG_LOAD16_G` td declaration unchanged                       | V6ClangInstrInfo.td                                |
| Test coverage | Lit test pinning each row + integration runtime guard        | tests/lit/, tests/features/55/                 |
| Doc updates | Mark O73 done in `design/future_plans/README.md`,              | design/future_plans/                           |

---

## 3. Implementation Steps

### Step 3.1 — Rewrite expander: `dst=BC` arm three-way dispatch [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`,
`case V6CLANG::V6CLANG_LOAD16_G:` (currently line ~1883).

Replace the existing `dst=BC` branch with:

```cpp
} else {
  // BC: three-way dispatch on (HLDead, ADead).
  MCRegister DstLo = RI.getSubReg(DstReg, V6CLANG::sub_lo);
  MCRegister DstHi = RI.getSubReg(DstReg, V6CLANG::sub_hi);

  bool HLDead = isRegDeadAtMI(V6CLANG::HL, MI, MBB, &RI);
  bool ADead  = isRegDeadAtMI(V6CLANG::A,  MI, MBB, &RI);

  if (HLDead) {
    // 5B / 36cc: LHLD addr; MOV B,H; MOV C,L
    emitLHLD(MI);
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), DstHi).addReg(V6CLANG::H);
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), DstLo).addReg(V6CLANG::L);
  } else if (ADead) {
    // 8B / 48cc: LDA addr; MOV C,A; LDA addr+1; MOV B,A
    auto emitLDA = [&](int64_t Bias) {
      auto MIB = BuildMI(MBB, MI, DL, get(V6CLANG::LDA))
                     .addReg(V6CLANG::A, RegState::Define);
      if (AddrOp.isGlobal())
        MIB.addGlobalAddress(AddrOp.getGlobal(),
                             AddrOp.getOffset() + Bias);
      else
        MIB.addImm(AddrOp.getImm() + Bias);
    };
    emitLDA(0);
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), DstLo).addReg(V6CLANG::A);
    emitLDA(1);
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), DstHi).addReg(V6CLANG::A);
  } else {
    // 7B / 64cc: PUSH H; LHLD; MOV B,H; MOV C,L; POP H
    BuildMI(MBB, MI, DL, get(V6CLANG::PUSH))
        .addReg(V6CLANG::HL, RegState::Kill)
        .addReg(V6CLANG::SP, RegState::ImplicitDefine);
    emitLHLD(MI);
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), DstHi).addReg(V6CLANG::H);
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), DstLo).addReg(V6CLANG::L);
    BuildMI(MBB, MI, DL, get(V6CLANG::POP), V6CLANG::HL)
        .addReg(V6CLANG::SP, RegState::ImplicitDefine);
  }
}
```

> **Design Notes**: The `addr+1` operand for the second `LDA` reuses
> `AddrOp` with `getOffset() + 1` for `GlobalAddress` operands and
> `getImm() + 1` for plain `imm` operands. The clang driver only
> generates `tglobaladdr` operands for `V6CLANG_LOAD16_G` today (see the
> isel pattern in V6ClangInstrInfo.td:907), but the immediate path is
> kept for completeness so direct `llc` IR with numeric addresses
> still works.

> **Implementation Notes**: <to be filled>

### Step 3.2 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

Fix any compile errors, then proceed.

> **Implementation Notes**: <to be filled>

### Step 3.3 — Lit test: load16g_shapes.ll [x]

**File**: `llvm-project/llvm/test/CodeGen/V6CLANG/load16g_shapes.ll`

Construct the three dispatch outcomes directly in IR. Use a
3-i16-arg call site to force `dst=BC` allocation; vary which other
registers are live across the load to pin each shape.

```llvm
; RUN: llc -march=v6clang -O2 < %s | FileCheck %s

@g = external dso_local global i16
declare void @sink3_i16(i16 %a, i16 %b, i16 %c)
declare void @sink2_i16_i8(i16 %a, i16 %b, i8 %c)

; CHECK-LABEL: case3a_hl_dead:
;   HL dead at the V6CLANG_LOAD16_G site (no live i16 carried into the
;   call besides the BC slot, others materialised after).
; CHECK:      LHLD g
; CHECK-NEXT: MOV B, H
; CHECK-NEXT: MOV C, L
; CHECK-NOT:  PUSH
define void @case3a_hl_dead() {
  %v = load i16, ptr @g, align 1
  call void @sink3_i16(i16 0, i16 0, i16 %v)
  ret void
}

; CHECK-LABEL: case3b_a_dead:
;   HL live (carries hl_keep into call's HL slot), A dead.
; CHECK:      LDA g
; CHECK:      LDA g+1
; CHECK-NOT:  PUSH    H
define void @case3b_a_dead(i16 %hl_keep) {
  %v = load i16, ptr @g, align 1
  call void @sink3_i16(i16 %hl_keep, i16 0, i16 %v)
  ret void
}

; CHECK-LABEL: case3c_a_live:
;   HL live (hl_keep), A live (a_keep flows through to A-arg).
; CHECK:      PUSH    H
; CHECK:      LHLD g
; CHECK:      MOV B, H
; CHECK:      MOV C, L
; CHECK:      POP     H
define void @case3c_a_live(i16 %hl_keep, i8 %a_keep) {
  %v = load i16, ptr @g, align 1
  call void @sink2_i16_i8(i16 %hl_keep, i16 %v, i8 %a_keep)
  ret void
}
```

> **Design Notes**: The test relies on the V6CLANG calling convention
> (HL, DE, BC for i16 args; A is the i8 slot). The 3-i16-arg sink
> forces RA to materialise the BC slot. `sink3_i16` and
> `sink2_i16_i8` are external declarations so the optimizer does
> not inline them away.

> **Implementation Notes**: <to be filled>

### Step 3.4 — Run lit tests [x]

```
cd llvm-project
llvm-build\bin\llvm-lit -v llvm/test/CodeGen/V6CLANG
```

Diagnose and fix any failure. Pre-existing global-load lit tests
that pin the BC shape may need updates.

> **Implementation Notes**: <to be filled>

### Step 3.5 — Run regression tests [x]

```
python tests\run_all.py
```

Diagnose and fix any regression. Re-run until clean.

> **Implementation Notes**: <to be filled>

### Step 3.6 — Verification assembly steps from `tests\features\README.md` [x]

Compile `tests\features\55\v6clang.c` to `v6clang_new01.asm` and
analyze:

- `case1_dst_hl` — single `LHLD` (unchanged).
- `case2_dst_de` — `XCHG; LHLD; XCHG` (unchanged, may fold via
  `foldXchgDad`).
- `case3_dst_bc` — `A` is dead at the load, `HL` is live (carries
  `g_a` value into the upcoming call's HL slot). The redesigned
  expander should emit `LDA g_c; MOV C, A; LDA g_c+1; MOV B, A`
  (8B / 48cc) instead of the old `PUSH H; LHLD g_c; MOV B,H; MOV
  C,L; POP H` (7B / 64cc). Net: −16 cc, +1 B.

Iterate to `v6clang_new02.asm`, … if needed.

> **Implementation Notes**: <to be filled>

### Step 3.7 — Make sure `result.txt` is created (`tests\features\README.md`) [x]

Document c8080 vs v6clang cycles/bytes per function, plus the
shape-by-shape dispatch matrix.

> **Implementation Notes**: <to be filled>

### Step 3.8 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: <to be filled>

### Step 3.9 — Mark O73 complete in `design/future_plans/README.md` [x]

Add the **DONE** marker on the O73 row.

> **Implementation Notes**: <to be filled>

---

## 4. Expected Results

### Example 1 — `case3_dst_bc` from `tests/features/55/v6clang.c`

**Before** (current expander, HL live across BC-slot global load):
```asm
case3_dst_bc:
        LHLD    g_a            ; -> HL arg
        XCHG                   ;    DE = g_a
        LHLD    g_b            ;    HL = g_b
        XCHG                   ;    HL = g_a, DE = g_b
        PUSH    H              ;    +16cc / +1B
        LHLD    g_c            ;    HL = g_c
        MOV     B, H
        MOV     C, L           ;    BC = g_c
        POP     H              ;    +12cc / +1B
        JMP     add3           ; total dst=BC overhead: 64cc / 7B
```

**After** (LDA-pair, A dead at the load):
```asm
case3_dst_bc:
        LHLD    g_a
        XCHG
        LHLD    g_b
        XCHG
        LDA     g_c            ;    +16cc / +3B
        MOV     C, A           ;    + 8cc / +1B
        LDA     g_c+1          ;    +16cc / +3B
        MOV     B, A           ;    + 8cc / +1B
        JMP     add3           ; total dst=BC overhead: 48cc / 8B
```

Net: **−16 cc, +1 B** for the `dst=BC` slot when `A` is dead and
`HL` is live (the dominant scenario for global-load BC-slot
materialisation under the V6CLANG calling convention).

### Example 2 — Hot-loop reduction

A loop that calls a 3-i16-arg function with the third arg coming
from a global, while the first arg lives in HL across the call:

- Per iteration before: 64 cc on the `dst=BC` materialisation.
- Per iteration after: 48 cc on the same materialisation.
- Saved: 16 cc/iter at +1 B static cost.

### Example 3 — Already-optimal paths preserved

- `dst=HL` (case 1): one `LHLD`. No change.
- `dst=DE` (case 2): `XCHG; LHLD; XCHG`. No change.
- `dst=BC, HL dead` (case 3a): `LHLD; MOV B,H; MOV C,L`. Already
  emitted by O42 today; redesign keeps it.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `addr+1` operand construction is wrong for `tglobaladdr` (offset must apply to the symbol, not the relocation) | Lit test `case3b_a_dead` asserts the literal `LDA g+1` text in the emitted assembly, exercising the V6CLANG MC printer path. |
| `isRegDeadAtMI(A)` reports A dead when in fact a successor reads A through a callee-saved path | A is never callee-saved on V6CLANG (empty preserved mask, see `getCallPreservedMask`). The helper already handles successor live-ins for HL in O42's existing dst=BC path; the same machinery covers A. |
| Existing lit tests pin the old `PUSH H/POP H` shape | Update affected lit tests; for tests where the assertion was incidental to a different feature, prefer relaxing the CHECK to accept either shape. |
| Increased expander branch count makes the case harder to maintain | Three-way dispatch with one shared `emitLHLD` helper plus a small `emitLDA(Bias)` lambda local to the BC arm. ~30 LOC total. |
| Regression on hot paths that previously got "lucky" with the PUSH/POP shape | `python tests\run_all.py` covers golden + lit; `tests\features\55` exercises the dispatch end-to-end. |

---

## 6. Relationship to Other Improvements

- **O71 (V6CLANG_LOAD16_P Redesign)** — same structural problem on the
  through-pointer load; O73 ports the cheap-first dispatch idea to
  the global-address variant. The `(no Defs) + per-shape expansion`
  pattern is shared.
- **O42 (Liveness-Aware Pseudo Expansion)** — provides
  `isRegDeadAtMI`, the foundation for both the existing `HLDead`
  skip and the new `ADead` predicate.
- **O72 (V6CLANG_STORE16_P Redesign)** — companion plan for the
  through-pointer store; an analogous `V6CLANG_STORE16_G` redesign is
  the natural follow-up after this plan.

---

## 7. Future Enhancements

- Sequential `V6CLANG_LOAD16_G` peephole: two adjacent BC-slot loads
  from `addr` / `addr+2` could share an LDA chain
  (`LDA addr; MOV C,A; LDA addr+1; MOV B,A; LDA addr+2; …`),
  saving the second 16cc / 3B `LHLD`. Requires a peephole over
  expanded MIs.
- `V6CLANG_STORE16_G` parallel redesign: same shape-conflation pattern
  but for stores; emit `LDA addr; STA dst; LDA addr+1; STA dst+1`
  variants when applicable.

---

## 8. References

* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md)
* [Future Improvements](future_plans/README.md)
* [Source design: O73](future_plans/O73_V6CLANG_LOAD16_G_redesign.md)
* [Companion plan: O71](plan_O71_V6CLANG_LOAD16_P_redesign.md)
