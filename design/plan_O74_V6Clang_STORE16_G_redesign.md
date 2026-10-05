# Plan: V6CLANG_STORE16_G Redesign — `val=BC/DE` Shape Dispatch

Source design: [O74 V6CLANG_STORE16_G Redesign](future_plans/O74_V6CLANG_STORE16_G_redesign.md)

## 1. Problem

### Current behavior

`V6CLANG_STORE16_G` is the 16-bit store-to-global-address pseudo:

```tablegen
let mayStore = 1, Defs = [HL] in
def V6CLANG_STORE16_G : V6ClangPseudo<(outs), (ins GR16:$val, imm16:$addr),
    "# STORE16G $val, $addr", []>;
```

Today the isel pattern for stores to a global goes through `SHLD`
directly (not through `V6CLANG_STORE16_G`):

```tablegen
def : Pat<(store i16:$val, (V6Clangwrapper tglobaladdr:$addr)),
          (SHLD i16:$val, tglobaladdr:$addr)>;
```

`SHLD` is `GR16Ptr` (HL-only), so RA must always materialise the
value in HL — even when DE or BC already holds it — incurring a
copy or swap.

The post-RA expander (`V6ClangInstrInfo.cpp::expandPostRAPseudo`,
`case V6CLANG::V6CLANG_STORE16_G:`, ~line 1968) has only two arms:

| val   | Current expansion                                | Bytes / Cycles |
|-------|--------------------------------------------------|----------------|
| HL    | `SHLD addr`                                      | 3B / 20cc      |
| DE/BC | `LXI H, addr; MOV M, lo; INX H; MOV M, hi`       | 5B / 36cc      |

The blanket `Defs = [HL]` is over-declared for the `val=HL` shape
(`SHLD` reads HL and writes only memory; HL survives) and the
`val=DE/BC` arm is one-size-fits-all — it always materialises HL
with `LXI` and walks it via `INX`, ignoring observable post-RA
liveness of `HL` and `A` that would enable cheaper shapes.

### Desired behavior

Drop `Defs = [HL]`, repoint the isel pattern to
`V6CLANG_STORE16_G`, and dispatch per `val` register class on
observable post-RA liveness of `HL` and `A`:

|# |val|Predicate         |Expansion                                   |Bts/CCs|
|--|--|-------------------|--------------------------------------------|-------|
|1 |HL|(always)           |`SHLD addr`                                 |3B/20cc|
|2a|DE|`HL` dead at pseudo|`XCHG; SHLD addr`                           |4B/24cc|
|2b|DE|otherwise          |`XCHG; SHLD addr; XCHG`                     |5B/28cc|
|3a|BC|`HL` dead at pseudo|`MOV H,B; MOV L,C; SHLD addr`               |5B/36cc|
|3b|BC|`HL` live, `A` dead|`MOV A,C; STA addr; MOV A,B; STA addr+1`    |8B/48cc|
|3c|BC|`HL` live, `A` live|`PUSH H; MOV H,B; MOV L,C; SHLD addr; POP H`|7B/64cc|

Cycle counts use the V6CLANG-specific timings from
[`docs/Vector_06c_instruction_timings.md`](../../docs/Vector_06c_instruction_timings.md):
`SHLD`=20cc, `LXI`=12cc, `MOV M,r`=8cc, `INX`=8cc, `MOV r,r`=8cc,
`STA`=16cc, `XCHG`=4cc, `PUSH`=16cc, `POP`=12cc.

Comparison vs the current expander:

|# |val|Current shape (cc/B)           | New shape (cc/B)        | Δ        |
|--|--|--------------------------------|-------------------------|----------|
|1 |HL|`SHLD` 20cc/3B                  | `SHLD` 20cc/3B          | 0 / 0    |
|2a|DE|`LXI;MOV;INX;MOV` 36cc/5B       | `XCHG;SHLD` 24cc/4B     | −12 / −1 |
|2b|DE|`LXI;MOV;INX;MOV` 36cc/5B       | `XCHG;SHLD;XCHG` 28cc/5B| −8 / 0   |
|3a|BC|`LXI;MOV;INX;MOV` 36cc/5B       | `MOV H,B;MOV L,C;SHLD` 36cc/5B | 0 / 0 |
|3b|BC|(today: clobbers HL — RA spills HL)|`MOV A,C;STA;MOV A,B;STA+1` 48cc/8B|preserves HL|
|3c|BC|(today: clobbers HL — RA spills HL)|`PUSH H;…;POP H` 64cc/7B|honest preservation|

### Root cause

Two structural issues:

1. **Over-declared `Defs`.** `Defs = [HL]` is a lie for the
   `val=HL` shape (`SHLD` preserves HL); pre-RA passes (RA,
   scheduler, IPRA) see a stricter clobber set than the actual
   lowering, leading to unnecessary HL spills around `val=HL`
   stores.
2. **Single-shape `val=DE/BC` expander.** The expander emits
   the same `LXI; MOV M; INX H; MOV M` regardless of which
   non-HL register holds the value or whether `HL`/`A` are
   dead at the pseudo's location. RA cannot selectively spill
   `HL` or `A` per-instance — that decision belongs in the
   expander (same structural reason as O71/O72/O73).

The isel detour through `SHLD` exacerbates both: it forces RA to
materialise the value in HL even when DE or BC would be cheaper.

---

## 2. Strategy

### Approach: drop `Defs`, repoint isel, per-shape expansion

Three coordinated changes:

1. **`V6ClangInstrInfo.td`** — drop `Defs = [HL]` from
   `V6CLANG_STORE16_G`; replace the `(SHLD ...)` selection pattern
   with `(V6CLANG_STORE16_G ...)` so RA can pick HL, DE, or BC.
2. **`V6ClangInstrInfo.cpp::expandPostRAPseudo`** — extend the
   `V6CLANG_STORE16_G` case with three-way dispatch on `(val class,
   HLDead, ADead)`. Reuse the `isRegDeadAtMI` helper from O42.
3. **Test coverage** — lit test pinning each row (covers all five
   shapes), integration feature test (`tests/features/56/`)
   verifying byte-level semantics for the two shapes the *baseline*
   compiler can actually emit (case 1: val=HL, case 3a: val=BC with
   HL dead). The HL-live shapes (case 2 and case 3b/3c) cannot be
   runtime-compared because the baseline `Defs=[HL]` causes the
   register allocator to fail ("ran out of registers") — that very
   failure is one of the bugs this redesign fixes, so post-fix
   compilation of those shapes is verified solely by the lit test.

### Why this works

- **Pressure-friendly.** With no `Defs`, RA sees the pseudo as
  preserving every register. No spills inserted around stores.
  The new expander honours that contract by saving/restoring
  HL via `PUSH H/POP H` only when no cheaper option exists.
- **Honest at expansion time.** Each shape is selected only
  when its clobber set is provably empty (register dead at MI)
  or recoverable (PUSH/POP, XCHG round-trip). The `val=HL`
  shape never touches anything other than memory; the `val=DE`
  shapes always restore HL when live; the `val=BC` shapes
  either don't touch HL (3b — A dead, LDA-pair via A) or don't
  touch A (3a/3c) or recover HL via PUSH/POP (3c).
- **Reuses existing machinery.** `isRegDeadAtMI` (O42) covers
  both predicates. Address-operand-plus-1 emission for `STA
  addr+1` mirrors O73's `LDA addr+1` pattern (inline lambda).

### Summary of changes

| Step | What                                                                 | Where                                          |
|------|----------------------------------------------------------------------|------------------------------------------------|
| TD   | Drop `Defs = [HL]`; repoint isel `SHLD` → `V6CLANG_STORE16_G`            | `llvm/lib/Target/V6Clang/V6ClangInstrInfo.td`          |
| C++  | Three-way `val=BC` dispatch + DE liveness dispatch                   | `V6ClangInstrInfo.cpp` `case V6CLANG::V6CLANG_STORE16_G:`  |
| Lit  | `store16g-shapes.ll` pinning each row                                | `llvm/test/CodeGen/V6Clang/`                       |
| Feat | `tests/features/56/` — c8080 + v6clang reference + result.txt        | `tests/features/56/`                           |
| Doc  | Mark O74 done in `design/future_plans/README.md`                     | `design/future_plans/`                         |

---

## 3. Implementation Steps

### Step 3.1 — TD changes: drop `Defs`, repoint isel pattern [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.td`,
near lines 897–913.

```tablegen
// Before
let mayStore = 1, Defs = [HL] in
def V6CLANG_STORE16_G : V6ClangPseudo<(outs), (ins GR16:$val, imm16:$addr),
    "# STORE16G $val, $addr", []>;
...
def : Pat<(store i16:$val, (V6Clangwrapper tglobaladdr:$addr)),
          (SHLD i16:$val, tglobaladdr:$addr)>;

// After
let mayStore = 1 in
def V6CLANG_STORE16_G : V6ClangPseudo<(outs), (ins GR16:$val, imm16:$addr),
    "# STORE16G $val, $addr", []>;
...
def : Pat<(store i16:$val, (V6Clangwrapper tglobaladdr:$addr)),
          (V6CLANG_STORE16_G i16:$val, tglobaladdr:$addr)>;
```

> **Design Notes**: Mirrors the existing `V6CLANG_LOAD16_G` declaration
> (no `Defs`, isel routes through the pseudo) — see lines 880–894.
> RA may now pick HL/DE/BC for the value register; the expander
> below handles all three.

> **Implementation Notes**: <to be filled>

### Step 3.2 — Expander: rewrite `V6CLANG_STORE16_G` arm [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`,
`case V6CLANG::V6CLANG_STORE16_G:` (currently line ~1968).

Replace the existing two-arm body with:

```cpp
case V6CLANG::V6CLANG_STORE16_G: {
  // Store 16-bit to global address. O74: per-shape, liveness-aware.
  //   val=HL: SHLD addr                                    (3B / 20cc)
  //   val=DE, HL dead:    XCHG; SHLD addr                  (4B / 24cc)
  //   val=DE, fallback:   XCHG; SHLD addr; XCHG            (5B / 28cc)
  //   val=BC, HL dead:    MOV H,B; MOV L,C; SHLD addr      (5B / 36cc)
  //   val=BC, A dead:     MOV A,C; STA; MOV A,B; STA+1     (8B / 48cc)
  //   val=BC, fallback:   PUSH H; MOV H,B; MOV L,C; SHLD;
  //                       POP H                            (7B / 64cc)
  Register ValReg = MI.getOperand(0).getReg();
  MachineOperand &AddrOp = MI.getOperand(1);

  auto emitSHLD = [&]() {
    auto MIB = BuildMI(MBB, MI, DL, get(V6CLANG::SHLD)).addReg(V6CLANG::HL);
    if (AddrOp.isGlobal())
      MIB.addGlobalAddress(AddrOp.getGlobal(), AddrOp.getOffset());
    else
      MIB.addImm(AddrOp.getImm());
  };

  if (ValReg == V6CLANG::HL) {
    emitSHLD();
  } else if (ValReg == V6CLANG::DE) {
    bool HLDead = isRegDeadAtMI(V6CLANG::HL, MI, MBB, &RI);
    BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
    emitSHLD();
    if (!HLDead)
      BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
  } else {
    // val=BC: three-way dispatch on (HLDead, ADead).
    bool HLDead = isRegDeadAtMI(V6CLANG::HL, MI, MBB, &RI);
    bool ADead  = isRegDeadAtMI(V6CLANG::A,  MI, MBB, &RI);

    if (HLDead) {
      // 5B / 36cc: MOV H,B; MOV L,C; SHLD addr.
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::H).addReg(V6CLANG::B);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::L).addReg(V6CLANG::C);
      emitSHLD();
    } else if (ADead) {
      // 8B / 48cc: MOV A,C; STA addr; MOV A,B; STA addr+1.
      // Preserves HL — strictly cheaper than PUSH/POP wrap (-16cc, +1B).
      auto emitSTA = [&](int64_t Bias) {
        auto MIB = BuildMI(MBB, MI, DL, get(V6CLANG::STA)).addReg(V6CLANG::A);
        if (AddrOp.isGlobal())
          MIB.addGlobalAddress(AddrOp.getGlobal(),
                               AddrOp.getOffset() + Bias);
        else
          MIB.addImm(AddrOp.getImm() + Bias);
      };
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::A).addReg(V6CLANG::C);
      emitSTA(0);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::A).addReg(V6CLANG::B);
      emitSTA(1);
    } else {
      // 7B / 64cc fallback: PUSH H; MOV H,B; MOV L,C; SHLD; POP H.
      BuildMI(MBB, MI, DL, get(V6CLANG::PUSH))
          .addReg(V6CLANG::HL, RegState::Kill)
          .addReg(V6CLANG::SP, RegState::ImplicitDefine);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::H).addReg(V6CLANG::B);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::L).addReg(V6CLANG::C);
      emitSHLD();
      BuildMI(MBB, MI, DL, get(V6CLANG::POP), V6CLANG::HL)
          .addReg(V6CLANG::SP, RegState::ImplicitDefine);
    }
  }

  MI.eraseFromParent();
  return true;
}
```

> **Design Notes**: The structure mirrors O73's `V6CLANG_LOAD16_G`
> case. The `STA addr+1` operand uses the same offset-bump
> idiom as O73's `LDA addr+1`. The `XCHG` for `val=DE` is
> emitted unconditionally (not guarded by `markXchgUseUndef`)
> because `DE` is necessarily live at the pseudo (it's the
> value source). We do not need an `isRegLiveBefore`-driven
> undef annotation as O73 needed for `dst=DE`.

> **Implementation Notes**: <to be filled>

### Step 3.3 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

Fix any compile errors, then proceed.

> **Implementation Notes**: <to be filled>

### Step 3.4 — Lit test: store16g-shapes.ll [x]

**File**: `llvm-project/llvm/test/CodeGen/V6Clang/store16g-shapes.ll`

Mirror `load16g-shapes.ll`. Construct each dispatch outcome
directly in IR; force the value-register class via the V6CLANG
free-list calling convention (HL, DE, BC for i16 args).

```llvm
; RUN: llc -march=v6clang < %s | FileCheck %s

@g = external dso_local global i16
declare i16 @use_hl_i16()
declare void @sink_i8(i8)

; val=HL — SHLD only.
; CHECK-LABEL: case1_val_hl:
; CHECK:       SHLD g
; CHECK-NOT:   PUSH
; CHECK-NOT:   XCHG
define void @case1_val_hl(i16 %v) {
  store i16 %v, ptr @g, align 1
  ret void
}

; val=DE, HL dead — XCHG; SHLD (no trailing XCHG).
; The first arg lands in HL but is never used after the store; the
; second arg lands in DE and is the value.
; CHECK-LABEL: case2a_val_de_hl_dead:
; CHECK:       XCHG
; CHECK-NEXT:  SHLD g
; CHECK-NOT:   PUSH
define void @case2a_val_de_hl_dead(i16 %unused_hl, i16 %v) {
  store i16 %v, ptr @g, align 1
  ret void
}

; val=DE, HL live — XCHG; SHLD; XCHG.
; HL is returned, so it must survive across the store.
; CHECK-LABEL: case2b_val_de_hl_live:
; CHECK:       XCHG
; CHECK-NEXT:  SHLD g
; CHECK-NEXT:  XCHG
; CHECK-NOT:   PUSH
define i16 @case2b_val_de_hl_live(i16 %hl_keep, i16 %v) {
  store i16 %v, ptr @g, align 1
  ret i16 %hl_keep
}

; val=BC, HL dead — MOV H,B; MOV L,C; SHLD.
; Three i16 args land in HL/DE/BC; the BC arg is the value; HL/DE
; are unused after.
; CHECK-LABEL: case3a_val_bc_hl_dead:
; CHECK:       MOV H, B
; CHECK-NEXT:  MOV L, C
; CHECK-NEXT:  SHLD g
; CHECK-NOT:   PUSH
; CHECK-NOT:   STA
define void @case3a_val_bc_hl_dead(i16 %unused_hl, i16 %unused_de, i16 %v) {
  store i16 %v, ptr @g, align 1
  ret void
}

; val=BC, HL live, A dead — MOV A,C; STA; MOV A,B; STA+1.
; HL is returned (live across store); A is never set.
; CHECK-LABEL: case3b_val_bc_a_dead:
; CHECK:       MOV A, C
; CHECK-NEXT:  STA g
; CHECK-NEXT:  MOV A, B
; CHECK-NEXT:  STA g+1
; CHECK-NOT:   PUSH    H
define i16 @case3b_val_bc_a_dead(i16 %hl_keep, i16 %unused_de, i16 %v) {
  store i16 %v, ptr @g, align 1
  ret i16 %hl_keep
}

; val=BC, HL live, A live — PUSH H; MOV H,B; MOV L,C; SHLD; POP H.
; HL is returned; an i8 arg flows through A and is consumed after.
; CHECK-LABEL: case3c_val_bc_a_live:
; CHECK:       PUSH    H
; CHECK:       MOV H, B
; CHECK:       MOV L, C
; CHECK:       SHLD g
; CHECK:       POP     H
; CHECK-NOT:   STA g
define i16 @case3c_val_bc_a_live(i16 %hl_keep, i16 %unused_de, i16 %v, i8 %a_keep) {
  store i16 %v, ptr @g, align 1
  call void @sink_i8(i8 %a_keep)
  ret i16 %hl_keep
}
```

> **Design Notes**: The V6CLANG calling convention is free-list
> based (HL, DE, BC for i16; A for first i8 — see
> `V6ClangISelLowering.cpp::V6ClangArgAllocator`). The argument
> ordering above pins each value-register class deterministically.

> **Implementation Notes**: <to be filled>

### Step 3.5 — Run lit tests [x]

```
cd llvm-project
llvm-build\bin\llvm-lit -v llvm/test/CodeGen/V6Clang
```

Diagnose and fix any failure. Pre-existing global-store lit
tests that pin the old `LXI; MOV M; INX H; MOV M` shape may
need updates.

> **Implementation Notes**: <to be filled>

### Step 3.6 — Run regression tests [x]

```
python tests\run_all.py
```

Diagnose and fix any regression. Re-run until clean.

> **Implementation Notes**: <to be filled>

### Step 3.7 — Verification assembly steps from `tests\features\README.md` [x]

Compile `tests\features\56\v6clang.c` to `v6clang_new01.asm`
and analyse:

- `case1_val_hl` — single `SHLD` (unchanged).
- `case2_val_de` — `XCHG; SHLD; XCHG` (was `LXI; MOV M; INX H;
  MOV M`). −8cc per store.
- `case3_val_bc_a_dead` — `MOV A,C; STA; MOV A,B; STA+1`
  preserving HL (was `Defs=[HL]`-driven RA spill of HL plus
  `LXI; MOV M; INX H; MOV M`). Net depends on baseline.

Iterate to `v6clang_new02.asm`, … if needed.

> **Implementation Notes**: <to be filled>

### Step 3.8 — Make sure `result.txt` is created (`tests\features\README.md`) [x]

Document c8080 vs v6clang cycles/bytes per function, plus the
shape-by-shape dispatch matrix.

> **Implementation Notes**: <to be filled>

### Step 3.9 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: <to be filled>

### Step 3.10 — Mark O74 complete in `design/future_plans/README.md` [x]

Add the **DONE** marker on the O74 row.

> **Implementation Notes**: <to be filled>

---

## 4. Expected Results

### Example 1 — `case2_val_de` from `tests/features/56/`

**Before** (current expander, val=DE, HL live):
```asm
case2_val_de:
        LXI     H, g            ; 12cc / 3B
        MOV     M, E            ;  8cc / 1B
        INX     H               ;  8cc / 1B
        MOV     M, D            ;  8cc / 1B
        RET                     ; 12cc / 1B
                                ; ----------
                                ; 36cc / 5B (excl. RET) for the store
```

**After** (val=DE, HL live → row 2b):
```asm
case2_val_de:
        XCHG                    ;  4cc / 1B
        SHLD    g               ; 20cc / 3B
        XCHG                    ;  4cc / 1B
        RET                     ; 12cc / 1B
                                ; ----------
                                ; 28cc / 5B for the store
```

Net: **−8 cc, +0 B** per store.

### Example 2 — `case2_val_de` (HL dead)

**After** (row 2a): `XCHG; SHLD g`. **−12 cc, −1 B** vs the
old shape.

### Example 3 — `case3_val_bc_a_dead`

Today the `Defs=[HL]` causes RA to insert HL preservation
(spill/reload pair via the static-stack slot or push/pop) and
then the expander still walks HL via `LXI; INX`. The new row
3b emits `MOV A,C; STA g; MOV A,B; STA g+1` (8B / 48cc),
preserving HL in place — no spill, no LXI, no `INX H`.

Compared to a typical RA spill+reload wrap (`SHLD slot; LXI;
MOV M; INX H; MOV M; LHLD slot` = 20+12+8+8+8+20 = 76cc /
13B + frame slot), the new shape saves ~28cc and 5B.

### Example 4 — `case1_val_hl` (already-optimal preserved)

`SHLD g`. Unchanged, but RA may now keep HL live across the
store (no longer spills HL to honour `Defs=[HL]`).

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `addr+1` operand construction is wrong for `tglobaladdr` (offset must apply to the symbol, not the relocation) | Lit test `case3b_val_bc_a_dead` asserts the literal `STA g+1` text; mirrors the verified O73 `LDA g+1` path. |
| Isel pattern repoint shifts RA decisions globally for 16-bit global stores | The new expander handles HL/DE/BC faithfully, so no shape regresses. Net is at worst neutral and at best a 0–12cc speedup per store from one fewer i16 copy materialising into HL. Validated by `python tests\run_all.py` regression suite. |
| Existing lit tests pin the old `LXI; MOV M; INX H; MOV M` shape for non-HL global stores | Update affected lit tests to the new shapes. For tests where the assertion was incidental to a different feature, prefer relaxing the CHECK to accept either shape. |
| `isRegDeadAtMI(A)` reports A dead when in fact a successor reads A through a callee-saved path | A is never callee-saved on V6CLANG (empty preserved mask, see `getCallPreservedMask`). Same machinery O73 already relies on. |
| `XCHG` for `val=DE` when DE was loaded just before the store could swap stale H/L into DE | DE holds the value (live by ISel), HL holds whatever RA chose. Round-trip XCHG preserves both; HL-dead variant only skips the trailing XCHG which leaves HL=value (dead-by-predicate). |
| Increased expander branch count makes the case harder to maintain | Three-way dispatch with one shared `emitSHLD` helper plus a small `emitSTA(Bias)` lambda local to the BC arm. ~50 LOC total — same shape and size as O73's `V6CLANG_LOAD16_G` arm. |

---

## 6. Relationship to Other Improvements

- **O73 (V6CLANG_LOAD16_G Redesign)** — companion plan for the
  global-address load. O74 ports the same cheap-first dispatch
  idea to the store side. The `(no Defs) + isel-via-pseudo +
  per-shape expansion` pattern is shared.
- **O71 / O72 (V6CLANG_LOAD16_P / V6CLANG_STORE16_P Redesign)** —
  through-pointer variants. Same structural problem solved
  there for the indirect-address case.
- **O42 (Liveness-Aware Pseudo Expansion)** — provides
  `isRegDeadAtMI`, the foundation for both the existing `HLDead`
  skip and the new `ADead` predicate.
- **O20 (Honest Store/Load Pseudo Defs)** — long-running effort
  to remove false HL clobbers from store/load pseudos. O74
  closes the loop on `V6CLANG_STORE16_G`.

---

## 7. Future Enhancements

- Sequential `V6CLANG_STORE16_G` peephole: two adjacent global
  stores at `addr` / `addr+2` sharing an HL-walk via `SHLD
  addr; LXI H, val2; SHLD addr+2`, or two STA-pair stores
  sharing an A-resident byte. Requires a peephole over expanded
  MIs.
- Combined LOAD/STORE peephole: `LHLD g; …; SHLD g` round-trips
  collapsed when the intermediate body doesn't touch HL.

## 8. References

- [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
- [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md)
- [Future Improvements](future_plans/README.md)
- [O73 V6CLANG_LOAD16_G Redesign Plan](plan_O73_V6CLANG_LOAD16_G_redesign.md)
- [O74 Design Doc](future_plans/O74_V6CLANG_STORE16_G_redesign.md)
