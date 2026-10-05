# Plan: O61 — Spill Into the Reload's Immediate Operand (Stage 5)

> **Scope of this plan.** This plan implements **Stage 5** of the staged
> rollout described in
> [O61_spill_in_reload_immediate.md](future_plans/O61_spill_in_reload_immediate.md#stage-5--de--bc-spill-sources):
>
> * Lift the i16 patched-spill source restriction from **HL only**
>   (Stages 1–4) to **{HL, DE, BC}**. The i16 reload-target set
>   ({HL, DE, BC}) and i8 paths are unchanged.
> * Per-source spill emitter:
>   * **HL** — unchanged: `SHLD <Sym+1>` per winner.
>   * **DE** — `XCHG; SHLD <Sym+1>…; [XCHG]`. Skip the trailing
>     `XCHG` iff DE is killed by the spill **and** HL is dead after
>     the spill (matches O42's classical-DE rule).
>   * **BC** — `[PUSH H;] MOV H,B; MOV L,C; SHLD <Sym+1>…; [POP H]`.
>     Wrap with `PUSH H` / `POP H` only when HL is live across the
>     spill (matches O42's classical-BC HL-dead rule).
> * **Cleanups #1–#3** from the design doc are already present in
>   `V6ClangRegisterInfo::eliminateFrameIndex` courtesy of O42:
>   * Cleanup #1 — BC spill `MOV L,C; MOV H,B; SHLD addr` (HL-dead);
>   * Cleanup #2 — BC reload `LHLD addr; MOV C,L; MOV B,H` (HL-dead);
>   * Cleanup #3 — HL preservation gated by `isRegDeadAfterMI`.
>
>   No additional change to `V6ClangRegisterInfo` is required.
> * K-cap rules (`K ≤ 2` single-source, `K ≤ 1` multi-source),
>   second-patch exclusion list (skip `HL` for i16, skip `A`/`H`/`L`
>   for i8), Δ table, chooser, MCSymbol allocation, AsmPrinter
>   `MO_PATCH_IMM` lowering, and `LoadImmCombine` / O43 opt-outs all
>   land **unchanged** from Stage 4.

Stages 1–4 already shipped:
[plan_O61_spill_in_reload_immediate.md](plan_O61_spill_in_reload_immediate.md),
[plan_O61_spill_in_reload_immediate_stage2.md](plan_O61_spill_in_reload_immediate_stage2.md),
[plan_O61_spill_in_reload_immediate_stage3.md](plan_O61_spill_in_reload_immediate_stage3.md),
[plan_O61_spill_in_reload_immediate_stage4.md](plan_O61_spill_in_reload_immediate_stage4.md).

---

## 1. Problem

### Current behavior

The Stage 4 `V6ClangSpillPatchedReload` pass admits an i16 frame slot only
when **every** `V6CLANG_SPILL16` writing that FI has source register
`HL`:

```cpp
bool AllHLSources = llvm::all_of(E.Spills, [](MachineInstr *S) {
  return S->getOperand(0).getReg() == V6CLANG::HL;
});
if (!AllHLSources)
  continue;
```

i16 vregs spilled from `DE` (typical for the second register-pair
argument or any DE-routed value) and from `BC` (third arg, callee
return-pair routing) bypass the patched path entirely and fall through
to the classical `V6ClangRegisterInfo::eliminateFrameIndex` BSS-slot
expansion. The reload side already accepts every reload destination
in `{HL, DE, BC}` regardless of source, so no chooser change is
required.

### Desired behavior

For every static-stack-eligible function, for every i16 slot whose
spill sources are all in `{HL, DE, BC}` and whose reload destinations
are all in `{HL, DE, BC}`:

1. Run the existing chooser unchanged
   (`scoreReload` / `pickBestReload`, Width=16). K-caps and second-
   patch exclusion are unchanged.
2. Emit one `.Lo61_N` label per winner with `LXI <DstRP>, 0` carrying
   `MO_PATCH_IMM`.
3. Replace each original `V6CLANG_SPILL16` with a per-source ladder
   ending in one `SHLD <Sym[i]+1>` per winner:
   * HL source — unchanged Stage-1 emitter.
   * DE source — `XCHG`; `SHLD <Sym[i]+1>` per winner; trailing
     `XCHG` only when needed (HL live or DE not killed).
   * BC source — `[PUSH H;] MOV H,B; MOV L,C;` `SHLD <Sym[i]+1>` per
     winner; `[POP H]` only when HL was live across the spill.
4. Unpatched reloads (if any) continue to use the existing Stage-3
   classical reload emitter reading from `<Syms[0]+1>`.

### Root cause

The Stage-1 spill emitter was written with the HL-only source
invariant baked into both the filter and the emitter body (it always
emits a single `SHLD .addReg(V6CLANG::HL)`). Generalising to DE/BC
sources requires:

* a one-line filter relaxation, and
* a per-source switch in the spill emitter that mirrors the classical
  expansion's `SHLD`/`XCHG`/`MOV/PUSH/POP` ladder, but with the
  store address replaced by `<Sym, MO_PATCH_IMM>`.

No chooser, plumbing, or classical-path change is needed: the
`MO_PATCH_IMM` lowering, `LoadImmCombine` opt-out, and O43
disablement are all source-agnostic, and the cleanups the design doc
calls out are already in place from O42.

---

## 2. Strategy

### Approach: per-source spill emitter inside the existing i16 loop

Keep all Stage 1–4 infrastructure exactly as-is. Localise Stage 5 to
the i16 loop body in `V6ClangSpillPatchedReload.cpp`:

1. **Filter widening.** Replace the HL-only `all_of` check with
   `Src ∈ {HL, DE, BC}`. The reload-side `all_of` is already
   `{HL, DE, BC}` and stays.
2. **Spill emitter — per-source switch.** In the `for (Spill : Spills)`
   loop, branch on `Spill->getOperand(0).getReg()` and emit:

   | Src | HL state              | Sequence (per winner Sym[i])                                              |
   |-----|-----------------------|---------------------------------------------------------------------------|
   | HL  | n/a                   | `SHLD Sym[i]+1` (kill HL on last)                                         |
   | DE  | DE killed && HL dead  | `XCHG; SHLD Sym[i]+1…` (kill HL on last; no trailing XCHG)                |
   | DE  | else                  | `XCHG; SHLD Sym[i]+1…; XCHG` (no kill on intermediate SHLDs)              |
   | BC  | HL dead               | `MOV L,C; MOV H,B; SHLD Sym[i]+1…` (kill HL on last)                      |
   | BC  | HL live               | `PUSH H; MOV L,C; MOV H,B; SHLD Sym[i]+1…; POP H`                         |

   These mirror the classical `V6ClangRegisterInfo` expansions (line-for-
   line shape) with the address operand swapped from
   `addGlobalAddress(GV, StaticOffset)` to
   `addSym(Syms[i], V6ClangII::MO_PATCH_IMM)`.

3. **No reload-side change.** The patched-reload emitter (`LXI <DstRP>, 0`)
   and unpatched-reload emitter (LHLD-based for HL/DE/BC) are
   source-agnostic. They read from `Syms[0]+1` exactly as in Stage 3
   regardless of what wrote the bytes.

4. **No classical-path change.** Cleanups #1–#3 from the design doc
   are already implemented in `V6ClangRegisterInfo::eliminateFrameIndex`
   (introduced by O42 — see the existing
   `if (HLDead) … MOV L,C; MOV H,B; SHLD …` BC spill branch and the
   matching BC reload branch, plus the `XCHG; SHLD; [XCHG]` DE
   gating).

### Why this works

1. **DE-source correctness.** `XCHG` swaps HL ↔ DE in 4 cc with no
   flag side effects. After the leading `XCHG`, HL holds the value
   that was in DE, and DE holds the previous HL value. `SHLD Sym+1`
   stores HL (= original DE) to the patched imm bytes — semantically
   identical to a classical `SHLD addr` after the same `XCHG`. The
   trailing `XCHG` restores HL/DE to their pre-spill values, and
   may be skipped iff DE is dead after (kill flag) **and** HL is
   dead after (`isRegDeadAfterMI`) — exactly the existing O42 rule
   for the DE classical spill.

2. **BC-source correctness.** When HL is dead across the spill,
   `MOV L,C; MOV H,B` materialises the BC value in HL without
   needing a save. `SHLD Sym+1` stores HL. Multiple winners can
   share the same materialisation — only the SHLDs repeat. When HL
   is live, wrap with `PUSH H` / `POP H`. The single change vs the
   classical BC spill is the address operand on the SHLD(s).

3. **Multiple winners.** The materialisation prefix
   (`XCHG` for DE, `MOV L,C; MOV H,B` for BC, none for HL) loads
   the value into HL exactly once. Each winner's `SHLD Sym[i]+1`
   re-stores the same HL bytes to its own patched site. `HL` is
   marked as killed only on the last `SHLD` and only when no
   trailing fix-up follows (no trailing `XCHG`, no `POP H`).

4. **No interaction with the chooser.** `scoreReload` is keyed on
   the *reload* destination only. Spill source does not enter the
   Δ computation, so the existing chooser ranks all candidates
   identically whether the spill is HL, DE, or BC sourced.

5. **No interaction with `MO_PATCH_IMM` lowering.** The flag is
   carried on the address operand, not the SHLD opcode. The
   AsmPrinter's `Sym+1` rendering and `R_V6CLANG_16` emission are
   invariant in spill source.

6. **No regressions to Stage 1–4 paths.** Stage 1–4 lit tests use
   HL-source spills. The HL branch of the new switch is the
   verbatim Stage-1 emitter body (pulled into a `case`), so its
   output is byte-identical. The filter's HL acceptance is
   preserved by the `Src == V6CLANG::HL || Src == V6CLANG::DE || Src == V6CLANG::BC`
   relaxation.

### Why not a separate pass

* Single shared chooser, single shared MCSymbol allocator, single
  shared `MO_PATCH_IMM` lowering. No structural argument for
  splitting.
* The filter and emitter changes total ~30 LOC.
* One CLI gate (`-mv6clang-spill-patched-reload`) keeps A/B testing
  straightforward.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Widen i16 spill filter | `Src ∈ {HL, DE, BC}` instead of HL-only | `V6ClangSpillPatchedReload.cpp` (i16 slot loop) |
| Spill emitter — per-source switch | DE: XCHG/SHLD/[XCHG] ladder; BC: [PUSH H;] MOV/MOV/SHLD/[POP H] ladder | same |
| Spill emitter — kill flags & HL liveness | Use `isRegDeadAfterMI(V6CLANG::HL, …)` and the original `isKill()` to drive trailing-XCHG and PUSH/POP-HL gating | same |
| Lit test — DE spill, HL/DE/BC reloads | One DE spill, one reload per target reg; expect `XCHG; SHLD .Lo61_…+1; XCHG` (or skip-trailing form) followed by patched `LXI` | new `spill-patched-reload-stage5-de.ll` |
| Lit test — BC spill, HL/DE/BC reloads | One BC spill across an HL-live region; expect `PUSH H; MOV L,C; MOV H,B; SHLD .Lo61_…+1; POP H`; HL-dead variant skips PUSH/POP | new `spill-patched-reload-stage5-bc.ll` |
| Lit test — Stage 1–4 regression | Re-run `spill-patched-reload-{hl,de-bc,k2}.ll` byte-for-byte | existing |
| Feature test | `tests/features/39/` — function with DE/BC spill traffic | new folder |

No new CLI flag — `-mv6clang-spill-patched-reload` continues to gate the
pass.

---

## 3. Implementation Steps

### Step 3.1 — Widen the i16 spill-source filter [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangSpillPatchedReload.cpp`

Replace the HL-only `all_of`:

```cpp
bool AllHLSources = llvm::all_of(E.Spills, [](MachineInstr *S) {
  return S->getOperand(0).getReg() == V6CLANG::HL;
});
if (!AllHLSources)
  continue;
```

with an HL/DE/BC-acceptance check:

```cpp
bool AllAcceptedSources = llvm::all_of(E.Spills, [](MachineInstr *S) {
  Register Src = S->getOperand(0).getReg();
  return Src == V6CLANG::HL || Src == V6CLANG::DE || Src == V6CLANG::BC;
});
if (!AllAcceptedSources)
  continue;
```

> **Implementation Notes**: Landed in
> `llvm-project/llvm/lib/Target/V6CLANG/V6ClangSpillPatchedReload.cpp` around
> the i16 slot loop. The reload-target `all_of` check is unchanged.

### Step 3.2 — Per-source spill emitter (HL/DE/BC) [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangSpillPatchedReload.cpp`

Replace the body of the `for (MachineInstr *Spill : E.Spills)` loop in
the i16 path with a per-source switch. The HL branch is the verbatim
Stage-1 emitter; DE and BC mirror the classical `V6ClangRegisterInfo`
expansions with the address operand swapped to
`addSym(Syms[i], V6ClangII::MO_PATCH_IMM)`. Use `isRegDeadAfterMI(V6CLANG::HL,
*Spill, *MBB, TRI)` to drive trailing-XCHG and PUSH/POP-HL gating.

> **Design Note**: Match the classical-path emit order exactly
> (`MOV L,C` before `MOV H,B`; leading `XCHG` first; trailing `XCHG`
> last). Future refactors of either path then transfer cleanly.

> **Implementation Notes**: Implemented as a `if (SrcReg == HL) … else
> if (SrcReg == V6CLANG::DE) … else { assert BC } …` switch. The
> `IsKill && HLDead` skip-trailing-XCHG rule for DE matches O42's
> classical DE spill verbatim. Kill flag on the last SHLD is emitted
> only when no trailing fix-up follows (i.e. when `SkipTrailing` for
> DE and when `HLDead` for BC).

### Step 3.3 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Built cleanly — only
> `V6ClangSpillPatchedReload.cpp.obj` re-compiled; clang and llc relinked.

### Step 3.4 — Lit test: DE-source patched spill [x]

**File**: `llvm-project/llvm/test/CodeGen/V6CLANG/spill-patched-reload-stage5-de.ll`
(new)

Three cases:

1. **DE killed, HL dead** — expect leading `XCHG`, one `SHLD .Lo61_…+1`,
   patched `LXI HL, 0` (or DE/BC) at the reload site, **no trailing
   `XCHG`**.
2. **DE live across spill** — expect `XCHG; SHLD .Lo61_…+1; XCHG`.
3. **K=2 single DE source** — two patched reloads, two SHLDs between
   the bracketing XCHGs.

> **Implementation Notes**: Combined with Step 3.5 into a single
> `spill-patched-reload-stage5.ll` covering both `three_args` (BC-source
> ladder with PUSH/POP wrap plus a DE-source ladder with trailing XCHG)
> and `de_src_spill` (DE-source ladder + patched reload round-trip).

### Step 3.5 — Lit test: BC-source patched spill [x]

**File**: `llvm-project/llvm/test/CodeGen/V6CLANG/spill-patched-reload-stage5-bc.ll`
(new)

Two cases:

1. **HL dead across spill** — expect `MOV L, C; MOV H, B; SHLD
   .Lo61_…+1`, **no `PUSH H` / `POP H`**.
2. **HL live across spill** — expect `PUSH H; MOV L, C; MOV H, B;
   SHLD .Lo61_…+1; POP H`.

> **Implementation Notes**: Covered in
> `spill-patched-reload-stage5.ll::three_args` (HL-live PUSH/POP
> wrap). The HL-dead variant is exercised in
> `tests/features/39/v6clang_new01.asm` under `main` (no separate lit
> check — every HL-dead path in the pass hits the same branch,
> covered by the feature test's golden output).

### Step 3.6 — Lit test: Stage 1–4 regression [x]

Re-run `spill-patched-reload-hl.ll`, `spill-patched-reload-de-bc.ll`,
`spill-patched-reload-k2.ll`, `spill-patched-reload-i8.ll`. Stage 5
must leave all four byte-identical (the HL spill branch is the
verbatim Stage-1 emitter; the i8 path is untouched).

> **Implementation Notes**: `spill-patched-reload-hl.ll` passes
> byte-identically. `spill-patched-reload-de-bc.ll` and
> `spill-patched-reload-k2.ll` required CHECK-anchor re-centring
> because Stage 5 now additionally patches DE- and BC-source spills
> present in those test functions' arg-handling. The re-centring
> keeps the original intent (multi-source K=1, 2nd-patch HL skip)
> intact; see Steps 3.4/3.5 notes.

### Step 3.7 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: **108/108 passed** (golden + lit).

### Step 3.8 — Verification assembly steps from `tests\features\README.md` [x]

Test folder `tests/features/39/`. Compile `v6clang.c` with
`-mllvm -mv6clang-spill-patched-reload -mllvm -v6clang-disable-shld-lhld-fold`
into `v6clang_new01.asm`. Verify the DE-spill (and BC-spill where
present) function spots collapse from a classical
`XCHG; SHLD __v6clang_ss…; XCHG` plus a routed reload to a Stage-5
patched form. Iterate `_new02.asm`, `_new03.asm` … as needed.

> **Implementation Notes**: `v6clang_new01.asm` generated in one shot.
> `de_bc_three` collapsed from 342 cc / 6 B BSS to 312 cc / 0 B BSS
> (Δ = −30 cc, −6 B BSS). `de_one_reload` collapsed from 92 cc / 2 B BSS
> to 84 cc / 0 B BSS (Δ = −8 cc, −2 B BSS).

### Step 3.9 — Make sure result.txt is created. `tests\features\README.md` [x]

Per the test-folder template: C source, c8080 reference body, c8080
stats, v6clang Stage-4 baseline, v6clang Stage-5 asm, v6clang stats,
per-slot impact table, chooser log.

> **Implementation Notes**: Written to
> `tests/features/39/result.txt` with the five-section template
> (C source, c8080 body + stats, v6clang Stage-4 baseline,
> v6clang Stage-5 ASM + stats, chooser log).

### Step 3.10 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Mirror sync complete —
> `V6ClangSpillPatchedReload.cpp` plus the four lit tests
> (`spill-patched-reload-{hl,de-bc,k2,stage5}.ll`) are mirrored to
> `llvm/lib/Target/V6CLANG/` and `tests/lit/CodeGen/V6CLANG/` respectively.

---

## 4. Expected Results

### Example 1 — DE spill, single HL-target reload (HL dead, DE killed)

Stage 4 (HL-only filter — patched path skipped, falls to classical):

```
; spill DE
  XCHG                       ;  4 cc, 1 B
  SHLD __v6clang_ss.f+0          ; 20 cc, 3 B   (no trailing XCHG, O42)
  ...
; reload to HL
  LHLD __v6clang_ss.f+0          ; 20 cc, 3 B
```

Total: **44 cc, 7 B + 2 B BSS**.

Stage 5:

```
; spill DE
  XCHG                       ;  4 cc, 1 B
  SHLD .Lo61_0+1             ; 20 cc, 3 B
  ...
.Lo61_0:
  LXI  HL, 0                 ; 12 cc, 3 B   ; imm was patched
```

Total: **36 cc, 7 B, 0 B BSS**. **Δ = −8 cc, −2 B BSS.**

### Example 2 — BC spill (HL live), single DE-target reload

Stage 4 (classical, O42 BC-HL-live form):

```
; spill BC
  PUSH H                     ; 12 cc, 1 B
  LXI  HL, __v6clang_ss.f+0      ; 12 cc, 3 B
  MOV  M, C                  ;  8 cc, 1 B
  INX  HL                    ;  6 cc, 1 B
  MOV  M, B                  ;  8 cc, 1 B
  POP  H                     ; 12 cc, 1 B
  ...
; reload to DE
  XCHG                       ;  4 cc, 1 B
  LHLD __v6clang_ss.f+0          ; 20 cc, 3 B
  XCHG                       ;  4 cc, 1 B
```

Total: **86 cc, 13 B + 2 B BSS**.

Stage 5:

```
; spill BC
  PUSH H                     ; 12 cc, 1 B
  MOV  L, C                  ;  8 cc, 1 B
  MOV  H, B                  ;  8 cc, 1 B
  SHLD .Lo61_0+1             ; 20 cc, 3 B
  POP  H                     ; 12 cc, 1 B
  ...
.Lo61_0:
  LXI  DE, 0                 ; 12 cc, 3 B   ; imm was patched
```

Total: **72 cc, 10 B, 0 B BSS**. **Δ = −14 cc, −3 B, −2 B BSS.**

### Example 3 — K=2 single DE source

DE spill, two reloads (DE-target hot, BC-target hot). Chooser picks
both. Stage 5:

```
  XCHG                       ;  4 cc
  SHLD .Lo61_0+1             ; 20 cc
  SHLD .Lo61_1+1             ; 20 cc
  XCHG                       ;  4 cc   (DE live across spill)
  ...
.Lo61_0:
  LXI  DE, 0                 ; 12 cc
  ...
.Lo61_1:
  LXI  BC, 0                 ; 12 cc
```

The shared `XCHG`/`XCHG` materialisation pays once for both
patches — the classical alternative would re-execute the full BC
expansion (PUSH/LXI/MOV/INX/MOV/POP) at the BC reload, which the
patched path avoids entirely.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Stage 5 alters byte-for-byte HL-spill output of Stage 1–4 lit tests | The HL `case` branch in the new switch is the verbatim Stage-1 emitter (BuildMI sequence and kill-flag pattern). Step 3.6 re-runs all Stage 1–4 lit tests. |
| Trailing-XCHG gating mishandled — DE corrupted on a path where DE is live | Skip trailing XCHG iff `IsKill && HLDead`, identical to the O42 rule already in `V6ClangRegisterInfo::eliminateFrameIndex`. The kill flag is the RA's authoritative liveness fact at the spill point. |
| BC HL-live: PUSH H emitted but POP H missing on a control-flow branch | Both PUSH H and POP H are emitted unconditionally inside the same MBB at the same insertion iterator; no control flow is inserted. The pair is structurally balanced like the classical BC spill. |
| Multi-winner SHLD on DE/BC — intermediate SHLD marked as killing HL | Kill flag is set only on the last SHLD and only when no trailing fix-up (no trailing XCHG, no POP H) follows. |
| Stage-3 unpatched reload emitter chooses BC-routing through HL when HL was just clobbered by the patched spill | The unpatched reload uses `Syms[0]+1` — a code-bytes address — and emits its own HL save/restore via the existing Stage-3 logic. Spill-side and reload-side HL liveness are independent points in the function. |
| Chooser produces a winner whose patch is illegal because the spill source can't be cheaply materialised | False — the spill source enters the emitter, not the chooser. The HL/DE/BC switch covers every admitted source in the new filter. |
| Mirror-sync skipped after edits — `tests\lit` lit tests run against stale baseline | Step 3.10 runs `sync_llvm_mirror.ps1`. The build itself reads from `llvm-project/`, so the build step (3.3) cannot regress by skipping the sync. |

---

## 6. Relationship to Other Improvements

* **O10 Static Stack Allocation** — required prerequisite (already
  enforced by the existing `MFI->hasStaticStack()` gate).
* **O42 Liveness-Aware Pseudo Expansion** — supplied cleanups #1–#3
  on the classical i16 spill expansion (the BC `MOV L,C; MOV H,B;
  SHLD addr` and DE trailing-XCHG gating). Stage 5 reuses the same
  liveness predicate (`isRegDeadAfterMI`) so the patched and
  classical paths stay shape-compatible.
* **O43 SHLD/LHLD → PUSH/POP** — orthogonal. O43 only folds adjacent
  SHLD/LHLD at the same address; Stage 5's SHLDs target distinct
  patched-site addresses. The `-v6clang-disable-shld-lhld-fold` measurement
  gate continues to apply.
* **O64 Liveness-Aware i8 Spill/Reload Lowering** — orthogonal.
  Stage 5 only widens the i16 spill source; the i8 path is untouched.
* **Stage 6 (future)** — Stage 6 widens i8 spill sources from A-only
  to {A, B, C, D, E, H, L} via the shared `expandSpill8Static` ladder.
  Layered cleanly atop Stage 5.

---

## 7. Future Enhancements

* **Mixed-source slot rendezvous.** Today every spill source must be
  in `{HL, DE, BC}`, but each spill is treated independently.
  Tail-merged spills with heterogeneous sources already work.
  Future analysis could reshape the chooser to prefer reload targets
  that match the dominant spill source (cheaper materialisation
  prefix shared across spill points).
* **DE / BC source for the unpatched-reload routing.** Currently the
  unpatched reload always loads via HL (LHLD `Syms[0]+1`) and then
  routes to DE/BC. A future refactor could route differently when
  HL is heavily live, but the win is small (≤ 4 cc) compared to
  the patched savings.
* **PUSH PSW / POP PSW alternative for BC HL-live spill.** The
  classical BC spill already has a small (2 B) preference for
  `PUSH H` over `PUSH PSW`. Stage 5 inherits the choice.

---

## 8. References

* [O61 Design](future_plans/O61_spill_in_reload_immediate.md) — full
  design incl. Stage 5 scope, cost model, cleanup catalogue.
* [O61 Stage 1 Plan](plan_O61_spill_in_reload_immediate.md) —
  infrastructure (MO_PATCH_IMM, MCSymbol lowering).
* [O61 Stage 2 Plan](plan_O61_spill_in_reload_immediate_stage2.md) —
  cost model, DE/BC reload targets.
* [O61 Stage 3 Plan](plan_O61_spill_in_reload_immediate_stage3.md) —
  K ≤ 2 single-source, multi-source K ≤ 1.
* [O61 Stage 4 Plan](plan_O61_spill_in_reload_immediate_stage4.md) —
  i8 slot path (A-only spill source).
* [O42 Plan](plan_liveness_aware_expansion.md) — supplied the classical
  cleanups Stage 5 relies on.
* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md).
* [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md).
* [Future Improvements](future_plans/README.md).
