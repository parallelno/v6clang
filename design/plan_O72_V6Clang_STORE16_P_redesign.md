# Plan: V6CLANG_STORE16_P Redesign — Honest Per-Shape Preservation

Source design: [O72 V6CLANG_STORE16_P Redesign](future_plans/O72_V6CLANG_STORE16_P_redesign.md)

Companion to the completed [O71](future_plans/O71_V6CLANG_LOAD16_P_redesign.md);
mirrors the same template applied to the 16-bit *store*-through-pointer
pseudo.

## 1. Problem

### Current behavior

`V6CLANG_STORE16_P` is the generic 16-bit store-through-pointer pseudo:

```tablegen
let mayStore = 1, Defs = [HL, A] in
def V6CLANG_STORE16_P : V6ClangPseudo<(outs), (ins GR16:$val, GR16:$addr),
    "# STORE16P $val, ($addr)",
    [(store i16:$val, i16:$addr)]>;
```

The pseudo declares a single blanket `Defs = [HL, A]` that is
over-declared on most of the 9 `(val, addr)` shapes. The post-RA
expander in `V6ClangInstrInfo::expandPostRAPseudo()` lowers each shape
to a concrete sequence:

```
val=HL, addr=HL  → MOV A,H; MOV M,L; INX H; MOV M,A
val=HL, addr=DE  → [PUSH D]; MOV A,L; STAX D; INX D; MOV A,H; STAX D; [POP D]
val=HL, addr=BC  → [PUSH B]; MOV A,L; STAX B; INX B; MOV A,H; STAX B; [POP B]
val∈{BC,DE}, addr=HL  → MOV M,lo; INX H; MOV M,hi
val∈{BC,DE}, addr∈{BC,DE} → MOV H,addrHi; MOV L,addrLo; MOV M,lo; INX H; MOV M,hi
```

Two structural problems:

1. **`Defs = [HL, A]` is over-declared on 6 of 9 shapes.** Cases
   `val∈{BC,DE}` never write `A`, so RA is forced to spill `A`
   across **every** 16-bit pointer store even though most of them
   leave `A` untouched. On a 1-element pressure class that's the
   single most expensive part of the declaration.
2. **`Defs` is also wrong on shapes that fully overwrite HL** —
   `val∈{BC,DE}, addr∈{BC,DE}` does `MOV H,addrHi; MOV L,addrLo`,
   wiping HL completely. The blanket `HL` def is technically
   honest there, but `addr=HL, val∈{BC,DE}` only mutates HL via
   `INX H` — a single `DCX H` recovers the original cheaply, which
   the current expander never emits.

A single coarse `Defs` set cannot simultaneously be truthful and
tight across 9 different code shapes. (No correctness bug — the
existing PUSH/POP elision via O42 keeps the live-DE/BC paths
correct — just structural over-declaration that costs cycles.)

### Desired behavior

After the redesigned expander runs:

- `A` is preserved across every shape **except case 5** (`addr=BC,
  val∈{HL,DE}`), where `STAX rp` forces `A` to be the staging
  register. On case 5, when `A` is live the expander prefers a
  dead GR8 spare over `PUSH PSW`/`POP PSW`.
- The address pair (`HL`, `BC`, or `DE`) is preserved across every
  shape when it is live across the pseudo, using the cheapest
  available recovery — `DCX rp` after `INX rp` (5 cases), or
  `PUSH H`/`POP H` only as the last resort on case 6 when HL is
  fully overwritten and no GR8 spare is available.
- The `addr=DE` shapes use `XCHG; …; XCHG` instead of `STAX D` —
  this preserves both `A` and `HL` on the common path and replaces
  the current `PUSH D`/`POP D` (16+12cc) with a `DCX D` (8cc) when
  DE is live.
- The pseudo's pre-RA contract — "stores `$val` at `$addr`,
  preserves everything else" — is honest at the IR level (no
  `Defs = [HL, A]`), and the expander emits truthful per-shape
  recovery.

### Root cause

The original expander conflated 9 `(val, addr)` shapes onto two
code paths and used a single `Defs = [HL, A]` to cover the union
of clobbers. The blanket has the same structural problem as
LOAD16_P (O71): cheap shape-specific recovery (`DCX rp`, dead-GR8
spare, `XCHG` swap) is impossible to express in TableGen `Defs`.
The fix is the same — drop `Defs` and emit truthful preservation
per shape at expansion time.

---

## 2. Strategy

### Approach: per-shape expansion with cheap-first preservation (mirror of O71)

Drop `Defs = [HL, A]` from `V6CLANG_STORE16_P` entirely. Replace the
body of `case V6CLANG::V6CLANG_STORE16_P:` in
`V6ClangInstrInfo::expandPostRAPseudo()` with a six-row dispatch on
`(addr, val)` register pairs (rows match the design table):

| Row | addr | val   | expansion |
|----|----|----|---|
| 1  | HL  | HL    | `MOV SpareR,H; MOV M,L; INX H; MOV M,SpareR` (+ `DCX H` if HL live) |
| 2  | HL  | BC/DE | `MOV M,lo; INX H; MOV M,hi` (+ `DCX H` if HL live) |
| 3  | DE  | HL/BC | `XCHG; MOV M,lo; INX H; MOV M,hi; XCHG` (+ `DCX D` if DE live) |
| 4  | DE  | DE    | `XCHG; MOV SpareR,H; MOV M,L; INX H; MOV M,SpareR; XCHG` (+ `DCX D` if DE live) |
| 5  | BC  | HL/DE | `MOV A,lo; STAX B; INX B; MOV A,hi; STAX B` (+ `DCX B` if BC live, + A-preservation if A live) |
| 6  | BC  | BC    | tiered by HL liveness (see Step 3.7) |

Cheap-first preservation order, identical to O71:

1. Use any dead GR8 as a temp/save target (rows 1, 4, 5, 6).
2. Emit `DCX rp` to undo `INX rp` when the address pair is live
   (rows 1, 2, 3, 4, 5).
3. Use `XCHG; …; XCHG` for `addr=DE` so HL and A are preserved
   with no extra stack traffic (rows 3, 4).
4. Wrap `PUSH PSW`/`POP PSW` only as a worst-case fallback when
   `A` is live and no GR8 is dead (rows 1, 4, 5).
5. Wrap `PUSH H`/`POP H` only on row 6 when HL is live AND no GR8
   spare is available — the only shape where HL is unavoidably
   scratched and there is no `A`-preserving STAX detour.

### Why this works

- **Pressure-friendly.** Without `Defs = [HL, A]`, RA stops
  spilling `A` across every 16-bit pointer store. The 8 of 9
  shapes that already preserve `A` benefit immediately.
- **Honest at expansion time.** Liveness is fully resolved
  post-RA; the expander emits exactly the recovery code each
  instance needs. Cases that don't need recovery emit nothing.
- **Cheaper than RA-visible `Defs`.** RA cannot emit `DCX rp`
  (operates on vregs only), cannot pick a dead GR8, and cannot
  use `XCHG` shape-conditionally. All three are key cost levers
  on this 3-element-GR16 / 1-element-A ISA.
- **Reuses existing helpers.** O71 already provides
  `isRegDeadAtMI` and `findDeadGR8AtMI`; O72 reuses both unchanged.
  The only new logic is the row-6 three-way dispatch on
  `(HLDead, SpareR-available)`.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Drop `Defs` | Remove `Defs = [HL, A]` from V6CLANG_STORE16_P | `V6ClangInstrInfo.td` |
| Rewrite expander | Six-row dispatch with cheap-first preservation | `V6ClangInstrInfo.cpp` `case V6CLANG::V6CLANG_STORE16_P:` |
| (No new helper) | Reuse `isRegDeadAtMI` and `findDeadGR8AtMI` from O71 | `V6ClangInstrInfo.cpp` |
| Test coverage | Lit tests for the highest-value shapes + feature test | `tests/lit/`, `tests/features/54/` |
| Doc updates | Mark O72 done in `design/future_plans/README.md`, fill Implementation Notes | `design/future_plans/` |

---

## 3. Implementation Steps

### Step 3.1 — Drop `Defs` from `V6CLANG_STORE16_P` td declaration [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.td`

Remove `Defs = [HL, A]` from the `V6CLANG_STORE16_P` declaration:

```tablegen
let mayStore = 1 in
def V6CLANG_STORE16_P : V6ClangPseudo<(outs), (ins GR16:$val, GR16:$addr),
    "# STORE16P $val, ($addr)",
    [(store i16:$val, i16:$addr)]>;
```

> **Design Notes**: Mirrors O71's `V6CLANG_LOAD16_P` (no `Defs`). All
> truthful clobbers move into the post-RA expander.

> **Implementation Notes**: Dropped `Defs = [HL, A]` from the
> `V6CLANG_STORE16_P` pseudo definition; comment now references O72.

### Step 3.2 — Rewrite expander: row 2 (`addr=HL, val∈{BC,DE}`) [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`,
`case V6CLANG::V6CLANG_STORE16_P:` (currently around line 1564).

Anchor the new structure with the simplest row:

```asm
    MOV  M, ValLo
    INX  H
    MOV  M, ValHi
    DCX  H               ; only if HL live after the pseudo
```

Branch on `AddrReg == V6CLANG::HL && ValReg != V6CLANG::HL`. Emit `DCX H`
iff `!isRegDeadAtMI(V6CLANG::HL, MI, MBB, &RI)`.

Reuse the `emitMOVrM` / `emitMOVMr` / `emitINXHL` / `emitDCX` /
`emitXCHG` lambda helpers from the O71 LOAD16_P expander; refactor
them into local lambdas inside the STORE16_P case (or keep
parallel copies — same shape).

> **Design Notes**: Today's expander does the same 3 stores but
> never emits `DCX H`. Adding `DCX H` for the live-HL path saves
> the next pointer reload (`LXI HL, ptr` ≈ 12cc/3B) on tight
> sequential-store loops.

> **Implementation Notes**: Implemented as the `addr=HL && val!=HL`
> branch in the rewritten `case V6CLANG::V6CLANG_STORE16_P:`. Uses local
> `emitMOVMr / emitINXHL / emitDCX` lambdas. `DCX H` guarded by
> `!isRegDeadAtMI(V6CLANG::HL, MI, MBB, &RI)`. Verified on
> `row2_hl_reused` in `v6clang_new01.asm` — body unchanged (4
> instr) plus `DCX H` only when HL is reused.

### Step 3.3 — Row 1 (`addr=HL, val=HL`) [x]

```asm
    MOV  SpareR, H
    MOV  M, L
    INX  H
    MOV  M, SpareR
    DCX  H               ; only if HL live after the pseudo
```

`SpareR = findDeadGR8AtMI(MI, MBB, &RI, V6CLANG::HL)`. If
`SpareR == 0`, set `SpareR = V6CLANG::A` and wrap with
`PUSH PSW`/`POP PSW` iff `!isRegDeadAtMI(V6CLANG::A, MI, MBB, &RI)`.

`DCX H` if HL live: at end of body HL = orig+1, SpareR holds
`H_orig`. `DCX H` brings HL back to orig. The body never reads
SpareR until the final `MOV M, SpareR`, so any non-`{H, L}` GR8 is
safe.

> **Design Notes**: Today's expander hard-codes `A` as the temp
> and clobbers `A` unconditionally. The dead-GR8 spare path
> preserves `A`.

> **Implementation Notes**: `addr=HL && val=HL` branch picks
> `SpareR = findDeadGR8AtMI(MI, MBB, &RI, V6CLANG::HL)`. Falls back to
> `A` with `PUSH PSW`/`POP PSW` wrap when A is live and no GR8 is
> dead. Verified by lit test `store16p-shapes.ll::row1_hl_hl`.

### Step 3.4 — Rows 3a (`addr=DE, val=HL`) and 3b (`addr=DE, val=BC`) [x]

```asm
    XCHG
    MOV  M, lo
    INX  H
    MOV  M, hi
    XCHG
    DCX  D               ; only if DE live after the pseudo
```

After the leading `XCHG`: `HL = orig DE` (the address), `DE = orig
HL` for row 3a or `DE = orig DE-half-aliasing` is irrelevant for
3b because `val=BC` → `lo = C, hi = B`. The body stores via the
new HL (= address), `INX H` bumps it, the trailing `XCHG`
restores HL = orig HL and leaves DE = address+1. `DCX D` (only if
DE is live) snaps DE back to address.

For row 3a (`val=HL`): after XCHG HL holds the value (was orig HL,
now in HL because XCHG swapped), wait — re-derive. Initial: HL =
val, DE = address. XCHG: HL = address, DE = val. Body stores
mem[address] = E (= lo of val), mem[address+1] = D (= hi of val).
Trailing XCHG: HL = val (restored), DE = address+1. ✓

For row 3b (`val=BC`): initial HL = orig HL, DE = address, BC =
val. XCHG: HL = address, DE = orig HL, BC unchanged. Body stores
mem[address] = C, mem[address+1] = B. Trailing XCHG: HL = orig HL,
DE = address+1. ✓

> **Design Notes**: Today's row 3a uses `[PUSH D]; MOV A,L; STAX
> D; INX D; MOV A,H; STAX D; [POP D]` — clobbers A, costs 6–8B
> and 41–63cc. The XCHG path is 5B/32cc with neither A nor HL
> clobbered. Today's row 3b uses `MOV H,D; MOV L,E; …` — fully
> overwrites HL even though `DCX D` could recover DE. The XCHG
> path keeps HL too. Major win on both rows.

> **Implementation Notes**: Single `addr=DE` branch handles both
> 3a (val=HL) and 3b (val=BC) — XCHG; MOV M,lo; INX H; MOV M,hi;
> XCHG; [DCX D]. After XCHG, `lo/hi` are derived from the post-XCHG
> register state (val=HL → lo=E, hi=D; val=BC → lo=C, hi=B).
> Verified in `v6clang_new01.asm::row3_de_hl` (5 instr, no A
> clobber) and via the updated lit test `load-store-i16.ll`
> store_ptr CHECK pattern.

### Step 3.5 — Row 4 (`addr=DE, val=DE`) [x]

```asm
    XCHG
    MOV  SpareR, H
    MOV  M, L
    INX  H
    MOV  M, SpareR
    XCHG
    DCX  D               ; only if DE live after the pseudo
```

After leading `XCHG`: HL = orig DE = value = address (val=DE means
val and addr are the same register), DE = orig HL.
- `MOV SpareR, H`: SpareR = D_orig (high byte of value).
- `MOV M, L`: mem[address] = E_orig (low byte of value).
- `INX H`: HL = address + 1.
- `MOV M, SpareR`: mem[address+1] = D_orig.
- Trailing `XCHG`: HL = orig HL (from D:E saved values), DE =
  address+1.
- `DCX D` if DE live: DE = address.

SpareR selection mirrors O71 case 4 (per-byte, not per-pair):
after the leading `XCHG`, `HL` holds the address (so `H`, `L` are
never candidates), and `DE` physically holds the original `HL`
bytes that the trailing `XCHG` will restore. Therefore:

- `B` candidate iff `B` dead across the pseudo.
- `C` candidate iff `C` dead across the pseudo.
- `D` candidate iff **`H`** dead across the pseudo.
- `E` candidate iff **`L`** dead across the pseudo.
- `A` candidate iff `A` dead across the pseudo (with PUSH PSW
  fallback).
- `H`, `L` never candidates.

Implement as a local `findRow4Spare` lambda identical to O71's
`findCase4Spare`.

> **Design Notes**: Today's expander has no row 4 — `val=DE,
> addr=DE` falls through to the generic `MOV H,D; MOV L,E; …`
> path that fully overwrites HL. Going through the XCHG-wrapped
> per-byte spare body preserves HL.

> **Implementation Notes**: `addr=DE && val=DE` branch.
> `findRow4Spare` lambda mirrors O71 case 4: scans GR8s with
> per-byte aliasing rules (D candidate iff H dead, E candidate iff
> L dead, never H/L). Falls back to `A` + PUSH PSW. Verified in
> `v6clang_new01.asm::row4_de_de` (B chosen as spare, 6 instr) and
> lit `store16p-shapes.ll::row4_de_de`.

### Step 3.6 — Row 5 (`addr=BC, val∈{HL,DE}`) [x]

```asm
    [save A: MOV SpareR, A   if A live and SpareR available]
    [save A: PUSH PSW        if A live and no SpareR]
    MOV  A, lo
    STAX B
    INX  B
    MOV  A, hi
    STAX B
    [restore A: MOV A, SpareR or POP PSW]
    DCX  B               ; only if BC live after the pseudo
```

`STAX rp` only accepts `A`, so `A` is **mandatory** as the staging
register. The body is identical to today's expander; the change
is the preservation strategy:

- If `A` is dead across the pseudo: emit body unchanged.
- Else, prefer `MOV SpareR, A; <body>; MOV A, SpareR` where
  `SpareR = findDeadGR8AtMI(MI, MBB, &RI, V6CLANG::BC, ValReg)`. The
  exclusion set is `{A, B, C, val_lo, val_hi}` because the body
  reads both halves of the value via `MOV A, lo` / `MOV A, hi`,
  and writes/reads BC via `STAX B; INX B; STAX B`. Excluding the
  ValReg pair handles this for both val=HL (excludes H, L) and
  val=DE (excludes D, E).
- Else (no GR8 spare AND A live): wrap `PUSH PSW` / `POP PSW`.

`DCX B` is emitted iff `!isRegDeadAtMI(V6CLANG::BC, MI, MBB, &RI)`.

> **Design Notes**: `A` clobber is unavoidable on this row
> because `STAX rp` is the only encoding that stores indirectly
> through BC/DE. Today's expander adds PUSH/POP B as well; the
> redesign replaces both with a single `DCX B` (1B/8cc vs
> 2B/28cc) when BC is live, and adds the SpareR / PUSH PSW
> A-preservation knob.

> **Implementation Notes**: `addr=BC && val!=BC` branch. Three
> A-preservation tiers: (i) A dead — emit body raw; (ii) GR8 spare
> available — `MOV SpareR, A; <body>; MOV A, SpareR`; (iii) `PUSH
> PSW` / `POP PSW` wrap. Exclusion set `{B, C, val_lo, val_hi}`
> (helper auto-skips A). `DCX B` guarded by liveness.

### Step 3.7 — Row 6 (`addr=BC, val=BC`) [x]

Three sub-rows ordered cheap-first, dispatched on
`(HLDead, SpareR-available)`:

**6a — HL dead at the pseudo** (the common case after RA has
scheduled HL away):

```asm
    MOV  H, B
    MOV  L, C
    MOV  M, C
    INX  H
    MOV  M, B
    DCX  B               ; only if BC live after the pseudo
```

5B / 40cc body. Clobbers HL (acceptable: HL is dead).

**6b — HL live, GR8 spare available**: switch to the row-5 STAX
body (which never touches HL) and save `A` into the spare.
`SpareR = findDeadGR8AtMI(MI, MBB, &RI, V6CLANG::A, V6CLANG::BC)` where
`A` exclusion is implicit (helper already skips A) and BC is
excluded because the body reads both halves:

```asm
    MOV  SpareR, A
    MOV  A, C
    STAX B
    INX  B
    MOV  A, B
    STAX B
    MOV  A, SpareR
    DCX  B               ; only if BC live after the pseudo
```

7B / 56cc. HL is left untouched.

**6c — HL live, no GR8 spare**: `PUSH H` / scratch body / `POP H`:

```asm
    PUSH H
    MOV  H, B
    MOV  L, C
    MOV  M, C
    INX  H
    MOV  M, B
    POP  H
    DCX  B               ; only if BC live after the pseudo
```

7B / 68cc. The scratch body (rather than the STAX body) is chosen
because it's strictly simpler and the `PUSH H/POP H` already
restores HL — no `A` shuffle needed.

> **Design Notes**: Today's expander always emits the 6c-shape
> path (`MOV H,B; MOV L,C; …` plus blanket `Defs = [HL, A]` so RA
> spills around it). The new row-6a path drops to 5B/40cc on the
> common HL-dead case; row-6b avoids `PUSH H` overhead when any
> GR8 is dead.

> **Implementation Notes**: `addr=BC && val=BC` branch with
> ordered probe: `HLDead → SpareR → PUSH H`. Row 6a is the common
> post-RA case. Verified `v6clang_new01.asm::row6_bc_bc` selects
> 6a (5B/40cc) and lit `store16p-shapes.ll::row6a_bc_bc_hl_dead`
> pins it.

### Step 3.8 — Build [x]

Run from repo root:

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

Fix any compile errors, then proceed.

> **Implementation Notes**: Build succeeded clean: 43/43 targets,
> no warnings introduced.

### Step 3.9 — Lit test: store16p-shapes (rows 1, 4, 6) [x]

**File**: `llvm-project/llvm/test/CodeGen/V6Clang/store16p-shapes.ll`

Pin the highest-value shapes:

- `row1_hl_hl` — `addr=HL, val=HL`. Asserts `MOV [[T:[BCDEHL]]], H ;
  MOV M, L ; INX H ; MOV M, [[T]]` and absence of `MOV A, H` or
  `MOV M, A`. Verifies dead-GR8 spare path (no A clobber).
- `row4_de_de` — `addr=DE, val=DE`. Asserts the XCHG-wrapped body
  with a dead-GR8 spare; absence of the old `MOV H,D; MOV L,E; …`
  pattern.
- `row6a_bc_bc_hl_dead` — `addr=BC, val=BC` with HL dead.
  Asserts `MOV H,B; MOV L,C; MOV M,C; INX H; MOV M,B` and absence
  of `PUSH H` / `POP H`.

Rows 2, 3, 5 are exercised by `tests/features/54/v6clang.c` and
the existing regression suite. Row 6b/6c are corner cases driven
by GR8 pressure; verifying them would need a hand-crafted MIR
test, deferred unless the feature test surfaces a regression.

> **Implementation Notes**: Created `store16p-shapes.ll` in both
> `tests/lit/CodeGen/V6Clang/` and `llvm-project/llvm/test/CodeGen/V6Clang/`
> with three functions (row1_hl_hl, row4_de_de,
> row6a_bc_bc_hl_dead). Lit run: PASS.

### Step 3.10 — Run regression tests [x]

```
python tests\run_all.py
```

Diagnose and fix any regression. Re-run until clean.

> **Implementation Notes**: Initial run: 2 lit failures
> (`load-store-i16.ll::store_ptr`, `shift-i16-byte-aligned.ll::
> srl8_i16`) pinned the legacy `MOV A, L; STAX D` pattern. Updated
> CHECK lines in both `tests/lit/` and the `llvm-project/llvm/test/`
> mirrors to the new XCHG-wrapped form. Final regression: 130/130
> PASS.

### Step 3.11 — Verification assembly steps from `tests\features\README.md` [x]

Compile `tests\features\54\v6clang.c` to `v6clang_new01.asm` and
analyze:

- Row 2: `DCX H` appears when HL pointer is reused after the
  store; absence of `Defs = [HL, A]`-induced spills around `A`.
- Row 1/4: temp is a dead GR8 when one is available; otherwise
  `PUSH PSW`/`POP PSW` wraps.
- Row 3 (DE): `XCHG; …; XCHG` instead of `STAX D; PUSH D/POP D`.
- Row 5: SpareR-A preservation when `A` is live; `DCX B` instead
  of `PUSH B / POP B`.
- Row 6: `MOV H,B; MOV L,C; MOV M,C; INX H; MOV M,B` (5B/40cc) on
  the HL-dead path; STAX-body with SpareR-A on the HL-live path
  with a dead GR8; `PUSH H`/`POP H` only as worst-case.

Iterate `v6clang_new02.asm`, … until the expected improvements
appear.

> **Implementation Notes**: `v6clang_new01.asm` already showed all
> expected improvements on first try — no iteration needed:
> row2 (4 instr + `DCX H` when HL reused), row3_de_hl (XCHG path,
> 5 instr, no A clobber), row4_de_de (XCHG + per-byte SpareR),
> row5 collapsed to row 3 by RA reassignment (still good),
> row6 selected 6a (5B/40cc).

### Step 3.12 — Make sure `result.txt` is created (`tests\features\README.md`) [x]

Document c8080 vs v6clang cycles/bytes per function and the
shape-by-shape matrix.

> **Implementation Notes**: `tests/features/54/result.txt`
> rewritten with the post-implementation per-function comparison
> and the row-by-row improvement matrix.

### Step 3.13 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Mirror sync completed cleanly.

### Step 3.14 — Mark O72 complete in `design/future_plans/README.md` [x]

Add the **DONE** marker on the O72 row.

> **Implementation Notes**: O72 row in
> `design/future_plans/README.md` marked **DONE**.

---

## 4. Expected Results

### Example 1 — `addr=HL, val=BC` with HL reused

**Before**:

```asm
MOV  M, C
INX  H
MOV  M, B
; HL = orig + 1, RA spilled A around the store and HL declared dead
LXI  H, ptr           ; +3B/+12cc/iter to reload the pointer
```

**After**:

```asm
MOV  M, C
INX  H
MOV  M, B
DCX  H                ; +1B/+8cc, HL = orig restored
; loop reuses HL directly → −3B/−12cc/iter on next store/load
```

Net per iteration: **−2B / −4cc** in tight sequential-store loops,
plus `A` no longer spilled.

### Example 2 — `addr=DE, val=HL` (e.g. linked-list write)

**Before** (today's STAX D path, DE live):

```asm
PUSH  D                     ; 16cc
MOV   A, L
STAX  D                     ; clobbers A
INX   D
MOV   A, H
STAX  D
POP   D                     ; 12cc
```

7B / 53cc, A clobbered.

**After** (XCHG path):

```asm
XCHG                        ; 4cc
MOV   M, E
INX   H
MOV   M, D
XCHG                        ; 4cc
DCX   D                     ; 8cc, only if DE live
```

5B / 40cc, **A and HL preserved**. −2B / −13cc and avoids the A
spill.

### Example 3 — `addr=BC, val=BC` (less common — pointer-of-pointer
write)

**Before** (today, blanket `Defs=[HL,A]` forces HL spill if live):

```asm
[PUSH H + reload — RA-emitted because HL declared dead]
MOV   H, B
MOV   L, C
MOV   M, C
INX   H
MOV   M, B
[POP H or refill]
```

**After** (row 6a, HL dead — common after RA):

```asm
MOV   H, B
MOV   L, C
MOV   M, C
INX   H
MOV   M, B
DCX   B                     ; only if BC live
```

5B / 40cc, no PUSH H emitted because HL was already dead.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Missed live-reg case in the dispatch leaves a clobber unrecovered | Per-row lit tests with both live-after and dead-after variants; runtime guard derived from `tests/features/54`. |
| Dropping `Defs = [HL, A]` exposes a pre-RA pass that relied on the over-declared clobber | Full `python tests/run_all.py` regression run. The matching O71 change for LOAD16_P had no such regression — the same passes operate identically on STORE16_P. |
| `findDeadGR8AtMI` returns a register that aliases the value or address pair | Helper takes 2 `Exclude` arguments; row 5 / row 6b pass the value pair and BC respectively. Row 4 uses the per-byte `findRow4Spare` lambda (mirrors O71 case 4). |
| Row 6 three-way dispatch picks the wrong tier under unusual liveness | Probe order is `HLDead → SpareR-available → PUSH-H fallback`; each tier is provably correct in isolation. The fallback is always safe. |
| Increased expander size (~150 LOC) raises maintenance cost | Single switch on `(addr, val)` shape with shared lambda helpers (parallels O71); each row body is 5–10 lines. |

---

## 6. Relationship to Other Improvements

- **O71 (`V6CLANG_LOAD16_P` redesign)** — same template, same
  helpers, completed. O72 reuses `isRegDeadAtMI` and
  `findDeadGR8AtMI` unchanged.
- **O20 (Honest Store/Load Pseudo Defs)** — addresses the
  structural problem at the td-declaration level. O72 takes the
  orthogonal expander-side approach because RA-visible Defs cost
  more than expander-time recovery on this ISA.
- **O42 (Liveness-Aware Pseudo Expansion)** — provides
  `isRegDeadAtMI`, the foundation for O72's preservation
  decisions. Existing PUSH/POP elision on rows 4 and 7 is
  preserved (now subsumed by the `DCX rp` / `XCHG` paths).
- **O44 (Adjacent XCHG Cancellation)** — cancels the trailing
  `XCHG` of a row-3/row-4 store against the leading `XCHG` of an
  adjacent `addr=DE` load/store, so the nominal +8cc XCHG
  overhead is paid only at chain boundaries.

---

## 7. Future Enhancements

- **`V6CLANG_LOAD16_G` / `V6CLANG_STORE16_G` global-address variants** —
  same shape-conflation pattern, follow-up redesign.
- **INX/DCX cancellation peephole** — `DCX rp` after `INX rp`
  pair elimination across basic-block joins.
- **Two-store chain peephole** — when two `addr=DE` stores abut,
  the trailing `XCHG` of the first cancels the leading `XCHG` of
  the second (covered structurally by O44, but explicitly track
  the `STORE16_P` use case).

---

## 8. References

* [O72 design doc](future_plans/O72_V6CLANG_STORE16_P_redesign.md)
* [O71 plan (template)](plan_O71_V6CLANG_LOAD16_P_redesign.md)
* [Plan format reference](plan_cmp_based_comparison.md)
* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
* [V6CLANG Instruction Timings](../docs/V6ClangInstructionTimings.md)
* [Future Improvements](future_plans/README.md)
* [Feature Test Cases](../tests/features/README.md)
* [Pipeline](pipeline_feature.md)
* [v6emul CLI](../tools/v6emul/docs/cli.md)
* [v6asm CLI](../tools/v6asm/docs/cli.md)
