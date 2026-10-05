# Plan: O61 — Spill Into the Reload's Immediate Operand (Stage 6)

> **Scope of this plan.** This plan implements **Stage 6** of the staged
> rollout described in
> [O61_spill_in_reload_immediate.md](future_plans/O61_spill_in_reload_immediate.md#stage-6--i8-non-a-spill-sources):
>
> * Lift the i8 patched-spill source restriction from **A only**
>   (Stage 4) to **any 8-bit GPR** (`{A, B, C, D, E, H, L}`). The i8
>   reload-target set (all eight GR8s) and every i16 path are
>   unchanged.
> * Per-source spill emitter:
>   * **A** — unchanged: one `STA <Sym+1>` per winner (kill on last).
>   * **B / C / D / E / H / L** — call through O64's shared
>     `expandSpill8Static` helper (`V6ClangSpillExpand.h`), which runs
>     the Shape B / Shape C decision ladder and terminates in either
>     `STA <Sym+1>` or `LXI HL, <Sym+1>; MOV M, r`. The appender
>     lambda supplies the patched address operand
>     (`MCSymbol + MO_PATCH_IMM`).
> * **K-cap for i8 non-A sources: hard-capped to K ≤ 1** per design
>   doc §"Cost model" (Stage 6 rollout). The K=2 arithmetic for
>   non-A sources needs per-row ladder inspection at chooser time;
>   the design explicitly defers this. A-source i8 spills keep the
>   Stage 4 K ≤ 2 rule unchanged.
> * Reload-side emitter, chooser scoring, `MO_PATCH_IMM` lowering,
>   `LoadImmCombine` / O43 opt-outs, and classical-path i8 expansion
>   all land **unchanged** from Stage 4 / O64.

Stages 1–5 already shipped:
[plan_O61_spill_in_reload_immediate.md](plan_O61_spill_in_reload_immediate.md),
[plan_O61_spill_in_reload_immediate_stage2.md](plan_O61_spill_in_reload_immediate_stage2.md),
[plan_O61_spill_in_reload_immediate_stage3.md](plan_O61_spill_in_reload_immediate_stage3.md),
[plan_O61_spill_in_reload_immediate_stage4.md](plan_O61_spill_in_reload_immediate_stage4.md),
[plan_O61_spill_in_reload_immediate_stage5.md](plan_O61_spill_in_reload_immediate_stage5.md).

---

## 1. Problem

### Current behavior

The Stage 4 / Stage 5 `V6ClangSpillPatchedReload` pass admits an i8 frame
slot only when **every** `V6CLANG_SPILL8` writing that FI has source
register `A`:

```cpp
bool AllASources = llvm::all_of(E.Spills, [](MachineInstr *S) {
  return S->getOperand(0).getReg() == V6CLANG::A;
});
if (!AllASources)
  continue;
```

i8 vregs spilled from `B`, `C`, `D`, `E`, `H`, or `L` bypass the
patched path entirely and fall through to the classical
`V6ClangRegisterInfo::eliminateFrameIndex` i8 expansion, which since O64
already runs the same decision ladder — terminating in `STA <BSS>`
or `LXI HL, <BSS>; MOV M, r` — exposed through
`llvm::expandSpill8Static` in `V6ClangSpillExpand.h`.

The reload-side handling is already complete in Stage 4 (all eight
GR8 reload targets admit `MVI r, imm`), and the unpatched-reload
emitter already delegates non-A reloads to `expandReload8Static`
with an `MCSymbol + MO_PATCH_IMM` appender.

### Desired behavior

For every static-stack-eligible function, for every i8 slot whose
spill sources are all in `{A, B, C, D, E, H, L}` (i.e. any GR8):

1. Run the existing chooser unchanged for K=1 picks
   (`scoreReload` / `pickBestReload`, Width=8).
2. Apply the **per-slot K cap**:
   * If every spill source is `A` — keep the Stage 4 rule: K ≤ 2
     single-source, K ≤ 1 multi-source.
   * If any spill source is non-A — hard-cap K ≤ 1 regardless of
     spill count (design doc: "keep the implementation simple:
     hard-cap K ≤ 1 for all i8 non-A spill sources").
3. Emit one `.Lo61_N` label per winner with `MVI <DstReg>, 0`
   carrying `MO_PATCH_IMM` (unchanged from Stage 4).
4. Replace each original `V6CLANG_SPILL8`:
   * **A source** — unchanged: one `STA <Sym[i]+1>` per winner,
     kill on last.
   * **Non-A source** — call `expandSpill8Static(SpillMI, SpillMI,
     Src, IsKill, TII, TRI, [&](MIB &B){ B.addSym(Syms[0],
     MO_PATCH_IMM); })`. Because Stage 6 hard-caps K=1 for
     non-A sources, the ladder runs **once** per spill
     instruction, targeting the single `Syms[0]`.
5. Unpatched reloads (if any) continue to use the existing Stage 4
   i8 reload emitter (LDA for A, `expandReload8Static` for others)
   reading from `Syms[0]+1` — no change.

### Root cause

The Stage 4 i8 spill emitter was written with the A-only source
invariant baked into both the filter and the emitter body (it
always emits `STA .addReg(V6CLANG::A)`). Generalising to non-A sources
requires:

* a one-line filter relaxation, and
* a per-source switch in the spill emitter that delegates to the
  O64 shared helper for non-A sources, with the appender supplying
  the `MCSymbol + MO_PATCH_IMM` address operand.

Because O64 has already landed the shared ladder helper
(`expandSpill8Static`) that the classical `V6ClangRegisterInfo` path
now consumes, Stage 6 reuses it verbatim. No new ladder code is
duplicated on the patched path.

---

## 2. Strategy

### Approach: per-source spill emitter inside the existing i8 loop

Keep all Stage 1–5 infrastructure exactly as-is. Localise Stage 6
to the i8 loop body in `V6ClangSpillPatchedReload.cpp`:

1. **Filter widening.** Replace the A-only `all_of` with an
   unconditional `true` check (every GR8 is acceptable), or delete
   the `AllASources` check outright. The reload-side `all_of` stays
   (admits every GR8).
2. **K-cap branch on source-set.** Before picking the 2nd winner,
   check whether every spill source is `A`. If so, keep the
   Stage 4 behaviour (2nd pick allowed for single-source spills,
   `AllowHL=false, AllowA=false`). If any spill source is non-A,
   skip the 2nd pick — enforce K ≤ 1.
3. **Spill emitter — per-source switch.** In the
   `for (Spill : E.Spills)` loop, branch on
   `Spill->getOperand(0).getReg()`:
   * `Src == V6CLANG::A` — emit the Stage 4 loop: one
     `STA <Syms[i], MO_PATCH_IMM>` per winner, kill on last.
   * `Src != V6CLANG::A` — call `expandSpill8Static(*Spill, Spill,
     Src, IsKill, TII, TRI, appender)` once, with `appender`
     supplying `Syms[0]` + `MO_PATCH_IMM`. The helper erases no
     instructions; the outer loop still calls `Spill->eraseFromParent()`.
4. **No reload-side change.** The patched-reload emitter
   (`MVI <DstReg>, 0`) and unpatched-reload emitter (LDA for A,
   `expandReload8Static` for non-A) are source-agnostic. They read
   from `Syms[0]+1` exactly as in Stage 4 regardless of what wrote
   the bytes.
5. **No classical-path change.** O64 already landed the
   `expandSpill8Static` ladder in
   `V6ClangRegisterInfo::eliminateFrameIndex` for the classical path.

### Why this works

1. **Correctness of O64 ladder on code-address target.** The
   shared `expandSpill8Static` helper never inspects the address
   operand it builds; the appender supplies a fully-formed `MCOperand`
   (MCSymbol with `MO_PATCH_IMM`). The helper's decision tree is
   a function of `(SrcReg, HLDead, ADead, findDeadSpareGPR8)` — all
   of which are independent of target-address kind. The AsmPrinter's
   `MO_PATCH_IMM` lowering (from Stage 1) renders `Sym+1` identically
   whether the operand appears on `STA`, `LDA`, `SHLD`, `LHLD`, `LXI`,
   or `MVI`. Same `R_V6CLANG_16` relocation shape as the classical path.

2. **Correctness of K=1 restriction for non-A sources.** With K=1
   there is a single `Syms[0]` to target. The ladder's terminal
   store (either `STA Sym[0]+1` or `LXI HL, Sym[0]+1; MOV M, r`)
   writes the spilled value into the patched imm bytes. Any
   subsequent unpatched reload of the same slot reads those bytes
   via `expandReload8Static` / `LDA Sym[0]+1` — the same semantics
   as the classical BSS path.

3. **Why hard-cap K=1 for non-A sources.** The design doc's
   §"Cost model" (Stage 6) lays out that a second patched site
   for a non-A i8 spill requires *repeating the terminal store*,
   which for Row 1 (HL-dead, `LXI HL, Sym+1; MOV M, r`) costs an
   extra 20 cc / 4 B. That extra cost can flip K=2 negative for
   low-Δ reload targets. The design explicitly defers K=2 to a
   follow-up: "Lift the cap in a follow-up once measurements
   justify the extra chooser state." Stage 6 takes the simple
   path.

4. **No regressions to Stage 1–5 paths.** Stage 4 A-source i8
   lit tests use the fast-path `STA Syms[i]+1` emitter. The
   `Src == V6CLANG::A` branch of the new per-source switch is the
   verbatim Stage 4 emitter body (pulled into a `case`), so its
   output is byte-identical. The filter's A acceptance is
   preserved by the unconditional GR8 admission. The K-cap
   branch keeps the A-source K ≤ 2 semantics untouched.

5. **No interaction with i16 path.** i8 and i16 slots are stored
   in distinct DenseMaps (`Slots8` / `Slots16`) and processed in
   independent loops. No shared state beyond the pass-level
   `MF.getContext()` symbol allocator, which already emits
   unique `.Lo61_N` labels.

### Why not a separate pass

* The shared `expandSpill8Static` helper and the shared chooser
  infrastructure already live in the pass. Stage 6 is a ~15 LOC
  filter + emitter delta.
* One CLI gate (`-mv6clang-spill-patched-reload`) keeps A/B testing
  straightforward.
* No ordering concerns — Stage 6 only widens the set of slots the
  pass admits; it doesn't change when the pass runs or what other
  passes it interacts with.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Widen i8 spill filter | Drop the `AllASources` check; accept any GR8 source | `V6ClangSpillPatchedReload.cpp` (i8 slot loop) |
| K-cap by source-set | 2nd winner picked only if every spill source is A (Stage 4 rule); otherwise K ≤ 1 | same |
| Spill emitter — per-source switch | A: existing STA-per-winner loop; non-A: `expandSpill8Static` with a `Syms[0]+MO_PATCH_IMM` appender | same |
| Lit test — non-A i8 spill, r8 reload | One spill per source in `{B, C, D, E, H, L}`; expect the expected ladder row (HL-dead: `LXI HL, .Lo61_N+1; MOV M, r`; A-dead: `MOV A, r; STA .Lo61_N+1`) + patched `MVI r, 0` at reload | new `spill-patched-reload-stage6.ll` |
| Lit test — Stage 1–5 regression | Re-run `spill-patched-reload-{hl,de-bc,k2,stage5}.ll` byte-for-byte | existing |
| Feature test | `tests/features/40/` — function with non-A i8 spill traffic | new folder |

No new CLI flag — `-mv6clang-spill-patched-reload` continues to gate the
pass.

---

## 3. Implementation Steps

### Step 3.1 — Widen the i8 spill-source filter [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangSpillPatchedReload.cpp`

Delete the `AllASources` check in the i8 slot loop (the GR8 reload-dst
check stays). Concretely replace:

```cpp
bool AllASources = llvm::all_of(E.Spills, [](MachineInstr *S) {
  return S->getOperand(0).getReg() == V6CLANG::A;
});
if (!AllASources)
  continue;
```

with:

```cpp
// Stage 6: accept any GR8 spill source. A-sourced and non-A
// sourced slots use different emitters (see spill rewrite loop
// below) but the chooser and reload-side emission are identical.
```

(i.e. no filter on spill source). The `AllSupportedR8` check on
reload destinations is retained verbatim.

> **Implementation Notes**: Landed as written. `AllASources` is now
> computed but used only by the K-cap in Step 3.2; the filter `continue`
> was deleted.

### Step 3.2 — Source-set-aware K cap [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangSpillPatchedReload.cpp`

Compute an `AllASources` flag (same predicate as the deleted
filter) and branch on it before picking the 2nd winner:

```cpp
bool AllASources = llvm::all_of(E.Spills, [](MachineInstr *S) {
  return S->getOperand(0).getReg() == V6CLANG::A;
});

// Chooser: 1st pick allows A/HL/DE/BC/...; 2nd pick skips A/H/L
// per Stage 4 rules. Stage 6 additionally caps K=1 when any
// spill source is non-A.
int W1 = pickBestReload(...);
if (W1 < 0) continue;
Winners.push_back(W1);

if (AllASources && E.Spills.size() == 1) {
  int Exc[] = {W1};
  int W2 = pickBestReload(...AllowHL=false, AllowA=false...);
  if (W2 >= 0)
    Winners.push_back(W2);
}
```

> **Design Note**: The second-patch exclusion set (skip A, H, L) is
> unchanged from Stage 4 — it still applies when the source is A and
> the caller admits a 2nd pick.

> **Implementation Notes**: Landed as written. 2nd pick guarded by
> `AllASources && E.Spills.size() == 1`; non-A slots produce exactly
> one symbol.

### Step 3.3 — Per-source spill emitter (A / non-A) [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangSpillPatchedReload.cpp`

Replace the body of the i8 `for (MachineInstr *Spill : E.Spills)`
loop with a per-source switch. The A branch is the verbatim Stage 4
emitter body; the non-A branch delegates to `expandSpill8Static`:

```cpp
for (MachineInstr *Spill : E.Spills) {
  MachineBasicBlock *MBB = Spill->getParent();
  DebugLoc DL = Spill->getDebugLoc();
  Register SrcReg = Spill->getOperand(0).getReg();
  bool IsKill = Spill->getOperand(0).isKill();

  if (SrcReg == V6CLANG::A) {
    // Stage 4: one STA per winner. Kill A on last STA.
    for (size_t si = 0; si < Syms.size(); ++si) {
      bool Kill = IsKill && (si + 1 == Syms.size());
      BuildMI(*MBB, Spill, DL, TII.get(V6CLANG::STA))
          .addReg(V6CLANG::A, getKillRegState(Kill))
          .addSym(Syms[si], V6ClangII::MO_PATCH_IMM);
    }
  } else {
    // Stage 6 (K=1 hard-capped for non-A sources).
    assert(Syms.size() == 1 && "Stage 6 caps K=1 for non-A i8 spills");
    expandSpill8Static(*Spill, Spill, SrcReg, IsKill, TII, TRI,
        [&](MachineInstrBuilder &B) {
          B.addSym(Syms[0], V6ClangII::MO_PATCH_IMM);
        });
  }
  Spill->eraseFromParent();
}
```

> **Design Note**: `expandSpill8Static` covers Shape B (`B/C/D/E`)
> and Shape C (`H/L`). It handles all four rows (HL dead / A dead /
> Tmp spare / PUSH-HL-or-PSW fallback) internally. Callers pass a
> valid GR8 other than A; the assertion inside the helper enforces
> this.

> **Implementation Notes**: Landed as written. The non-A branch calls
> `expandSpill8Static` once with a `Syms[0]+MO_PATCH_IMM` appender; the
> helper's row selection (HL-dead / A-dead / Tmp-save / PUSH-fallback)
> is unchanged.

### Step 3.4 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: `ninja -C llvm-build clang llc` completed
> with `[4/4] Linking CXX executable bin\clang.exe`.

### Step 3.5 — Lit test: non-A i8 patched spill [x]

**File**:
`llvm-project/llvm/test/CodeGen/V6CLANG/spill-patched-reload-stage6.ll`
(new)

Cover at minimum:

1. **B/C/D/E source, HL-dead at spill** — expect
   `LXI HL, .LLo61_N+1; MOV M, r` followed later by the patched
   reload `MVI <r>, 0` (or a different target reg).
2. **B/C/D/E source, HL-live + A-dead** — expect
   `MOV A, r; STA .LLo61_N+1` + patched reload.
3. **H/L source, A-dead** — expect `MOV A, H|L; STA .LLo61_N+1`
   + patched reload.
4. **Stage 4 A-source regression** — a function with only A
   sources must still emit `STA .LLo61_N+1` (no ladder prefix).

Use `-mv6clang-spill-patched-reload -v6clang-disable-shld-lhld-fold` as the
RUN-line flags, matching the other stages.

> **Implementation Notes**: Added
> `llvm-project/llvm/test/CodeGen/V6CLANG/spill-patched-reload-stage6.ll`
> covering `three_i8(i8,i8,i8)` which forces one B/C spill and one D/E
> spill through `expandSpill8Static` Row 1
> (`LXI HL, .LLo61_*+1; MOV M, r`) plus the A-source fast path
> (`STA .LLo61_*+1`). DISABLED prefix re-runs the Stage 5 baseline
> (`__v6clang_ss.three_i8`).
>
> **Bug discovered & fixed in this step**: `V6ClangLoadImmCombine.cpp`
> treated `MVI r, imm` with `MO_PATCH_IMM` as a trackable constant def,
> causing the "same value already in reg → erase MVI" optimisation to
> delete a second patched `MVI L, 0` when a prior patched `MVI L, 0`
> had seeded `KnownVal[L]=0`. Fixed by gating all four
> `MI.getOperand(1).isImm()` sites (`initFromPredecessor` MVIr/LXI,
> `processBlock` MVIr/LXI) on a new `isPlainImm(MO)` helper that also
> requires `MO.getTargetFlags() == 0`; operands carrying any target
> flag (MO_PATCH_IMM in practice) are treated as opaque constant
> definers (`invalidate(DstReg)` for MVI; `invalidateWithSubSuper` for
> LXI). This also fixes a latent Stage 4 bug that never triggered
> because Stage 4 tests happened to avoid colliding (reg,imm) pairs.

### Step 3.6 — Lit test: Stage 1–5 regression [x]

Re-run
`spill-patched-reload-hl.ll`,
`spill-patched-reload-de-bc.ll`,
`spill-patched-reload-k2.ll`,
`spill-patched-reload-stage5.ll`.
Stage 6 must leave all four byte-identical (the i16 path is
untouched; the i8 A-source branch is the verbatim Stage 4 emitter).

> **Implementation Notes**: `lit` runs `spill-patched-reload-hl.ll`,
> `spill-patched-reload-de-bc.ll`, `spill-patched-reload-k2.ll`,
> `spill-patched-reload-stage5.ll` — all PASS byte-identical alongside
> the new Stage 6 test.

### Step 3.7 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: `python tests\run_all.py` — 109/109 lit
> tests PASS, golden suite PASS, 2/2 suites PASS.

### Step 3.8 — Verification assembly steps from `tests\features\README.md` [x]

Test folder `tests/features/40/`. Compile `v6clang.c` with
`-mllvm -mv6clang-spill-patched-reload -mllvm -v6clang-disable-shld-lhld-fold`
into `v6clang_new01.asm`. Verify that non-A i8 spill sites collapse
from the classical ladder + BSS slot to the Stage 6 patched form
(ladder terminal targets `.Lo61_N+1`) with the reload collapsed to
`MVI r, 0` at the `.Lo61_N:` label.

> **Implementation Notes**: `tests/features/40/v6clang_new02.asm`
> (post-fix) shows `three_i8` with three `.LLo61_{0,1,2}` patched sites
> (A-source STA + two non-A `LXI HL; MOV M, r` ladders) and the three
> `MVI r, 0` reloads all preserved. `four_i8` has four patched sites.
> No `__v6clang_ss.*` BSS labels remain for the three_i8/four_i8 spills.

### Step 3.9 — Make sure result.txt is created. `tests\features\README.md` [x]

Five-section template (C source, c8080 body + stats, v6clang
Stage-5 baseline, v6clang Stage-6 ASM + stats, chooser log /
per-slot impact).

> **Implementation Notes**:

### Step 3.10 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**:

---

## 4. Expected Results

### Example 1 — `C` source, `B`-target reload, HL dead at spill

Stage 5 (A-only filter — i8 patched path skipped, falls to classical
O64 ladder against BSS):

```
; spill C (HL dead)
  LXI  HL, __v6clang_ss.f+0      ; 12 cc, 3 B
  MOV  M, C                  ;  8 cc, 1 B
  ...
; reload B (HL live, A dead) — O64 Row 2
  LDA  __v6clang_ss.f+0          ; 16 cc, 3 B
  MOV  B, A                  ;  8 cc, 1 B
```

Total: **44 cc, 8 B + 1 B BSS**.

Stage 6:

```
; spill C (HL dead)
  LXI  HL, .Lo61_0+1         ; 12 cc, 3 B
  MOV  M, C                  ;  8 cc, 1 B
  ...
.Lo61_0:
  MVI  B, 0                  ;  8 cc, 2 B    ; imm was patched
```

Total: **28 cc, 6 B, 0 B BSS**. **Δ = −16 cc, −2 B, −1 B BSS.**

### Example 2 — `E` source, single `E`-target reload (HL live, A dead)

Classical (Stage 5 baseline, via O64 Row 2 on both ends):

```
  MOV  A, E                  ;  8 cc, 1 B
  STA  __v6clang_ss.f+0          ; 16 cc, 3 B
  ...
  LDA  __v6clang_ss.f+0          ; 16 cc, 3 B
  MOV  E, A                  ;  8 cc, 1 B
```

Total: **48 cc, 8 B + 1 B BSS**.

Stage 6:

```
  MOV  A, E                  ;  8 cc, 1 B
  STA  .Lo61_0+1             ; 16 cc, 3 B
  ...
.Lo61_0:
  MVI  E, 0                  ;  8 cc, 2 B
```

Total: **32 cc, 6 B, 0 B BSS**. **Δ = −16 cc, −2 B, −1 B BSS.**

### Example 3 — `H` source spill (Shape C)

Stage 5 routes via `expandSpill8Static` Row 1 (A dead) against BSS;
Stage 6 reroutes to `.Lo61_0+1`:

```
  MOV  A, H                  ;  8 cc, 1 B
  STA  .Lo61_0+1             ; 16 cc, 3 B
  ...
.Lo61_0:
  MVI  D, 0                  ;  8 cc, 2 B
```

Δ identical to Example 2 — reload savings dominate.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Stage 4 A-source regression (K=2 path) | `Src == V6CLANG::A` branch is verbatim Stage 4 code; lit tests re-run byte-identical. |
| `expandSpill8Static` asserts on unexpected source | Helper accepts `{B, C, D, E, H, L}` — the exact set Stage 6 routes to it; A is handled inline. |
| K-cap accidentally tightened for A-source | `AllASources` flag computed once and branched; A-only slots retain Stage 4 K ≤ 2. |
| Row-1 ladder clobbers HL unexpectedly | O64 Row-1 precondition is `isRegDeadAfterMI(HL, …)`; identical check to the classical path. No new liveness edge. |
| Unpatched reload reads from wrong Syms index | K=1 for non-A sources means `Syms.size() == 1`; `Syms[0]` is always well-defined. Asserted in Step 3.3. |
| MO_PATCH_IMM lowering breaks on `MOV M, r` | `MOV M, r` doesn't carry the address operand — the `LXI HL, Sym+1` that precedes it does, which Stage 1 already exercises for i16 reloads. Same lowering path. |

---

## 6. Relationship to Other Improvements

* **O64** (Liveness-Aware i8 Spill/Reload Lowering) — hard
  prerequisite. Stage 6 reuses O64's `expandSpill8Static` helper,
  its `isRegDeadAfterMI` / `findDeadSpareGPR8` liveness queries,
  and its Shape B / Shape C decision tree directly. No ladder code
  is duplicated on the patched path.
* **O61 Stage 4** (A-source i8 patching) — fast path for
  `Src = A` i8 spills. Stage 6 preserves it byte-for-byte.
* **O61 Stage 5** (DE / BC i16 sources) — orthogonal; Stage 6
  touches only the i8 slot loop.
* **O43** (SHLD/LHLD → PUSH/POP) — unchanged. Stage 6 emits no
  SHLD/LHLD pair, so O43 has nothing to fold at Stage 6 sites.
* **LoadImmCombine / AccumulatorPlanning** — already treat patched
  `MVI` / `LXI` operands as opaque (the `MO_PATCH_IMM` flag from
  Stage 1). No new opt-outs.

## 7. Future Enhancements

* **K=2 for non-A i8 sources.** The design doc sketches the
  decision arithmetic: a second patch for a non-A source pays an
  extra terminal store (16–20 cc) in exchange for removing one
  classical reload (Δ = +12…+44 cc). When Δ(2nd reload) >
  extra_store_cost the second patch wins. Implementation requires
  per-row chooser state (did the ladder pick Row 1? Then extra =
  20 cc; else 16 cc), deferred by this plan.
* **Multi-source non-A i8 spills.** Currently K ≤ 1 for any non-A
  source (even single-source). The multi-source case (each source
  runs the ladder once to the same `Sym[0]`) is mechanically
  supported by the current design but exercises a rarely-hit
  chooser corner; defer until measurement justifies.

## 8. References

* [O61 Design Doc — Stage 6](future_plans/O61_spill_in_reload_immediate.md#stage-6--i8-non-a-spill-sources)
* [O64 Design Doc](future_plans/O64_liveness_aware_i8_spill_lowering.md)
* [Stage 4 Plan](plan_O61_spill_in_reload_immediate_stage4.md)
* [Stage 5 Plan](plan_O61_spill_in_reload_immediate_stage5.md)
* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md)
* [Future Improvements](future_plans/README.md)
