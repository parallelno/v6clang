# Plan: O61 — Spill Into the Reload's Immediate Operand (Stage 4)

> **Scope of this plan.** This plan implements **Stage 4** of the staged
> rollout described in
> [O61_spill_in_reload_immediate.md](future_plans/O61_spill_in_reload_immediate.md#recommended-scope-of-a-minimal-prototype):
>
> * Extend O61 from **16-bit slots only (Stages 1–3)** to **8-bit slots**
>   as well. Group `V6CLANG_SPILL8` / `V6CLANG_RELOAD8` pseudos by frame index
>   alongside the existing 16-bit grouping.
> * Patched reload targets extend from `{HL, DE, BC}` (i16) to also
>   include `{A, B, C, D, E, H, L}` (i8). The big-win case is `r8` with
>   `HL` live across the reload (Δ ≥ +44 cc per the design doc's
>   [Reloads table](future_plans/O61_spill_in_reload_immediate.md#reloads-reload-site-only)
>   and the V6CLANG backend's real classical baseline — see §1 for the
>   concrete V6CLANG numbers).
> * Spill source for i8 slots must be **`A`** (keeps the spill-side
>   emitter trivial: `STA <Sym+1>`). Non-A r8 spill sources are
>   deferred — they add value-routing complexity that doesn't buy
>   meaningful Δ, and `A` is the dominant i8 spill source in
>   practice. (Stage 5 lifts this along with the i16 HL-only spill
>   restriction.)
> * Reuse the existing chooser (`pickBestReload`) with an extended
>   `deltaForReload` table. Keep Stage 3's K caps: **K ≤ 2** for
>   single-source spills, **K ≤ 1** for multi-source spills, with the
>   2nd-patch chooser excluding `A`-target reloads (2nd-patch Δ = −8
>   cc for A per design doc) *and* `HL`/`H`/`L`-target reloads (per
>   the existing `AllowHL=false` rule plus the symmetric "never patch
>   a 2nd `A`-target" rule now extended to i8).

Stages 1–3 already shipped:
[plan_O61_spill_in_reload_immediate.md](plan_O61_spill_in_reload_immediate.md),
[plan_O61_spill_in_reload_immediate_stage2.md](plan_O61_spill_in_reload_immediate_stage2.md),
[plan_O61_spill_in_reload_immediate_stage3.md](plan_O61_spill_in_reload_immediate_stage3.md).

---

## 1. Problem

### Current behavior

The Stage 3 `V6ClangSpillPatchedReload` pass only collects
`V6CLANG_SPILL16` / `V6CLANG_RELOAD16` pseudos:

```cpp
    if (Opc == V6CLANG::V6CLANG_SPILL16)
      Slots[MI.getOperand(1).getIndex()].Spills.push_back(&MI);
    else if (Opc == V6CLANG::V6CLANG_RELOAD16)
      Slots[MI.getOperand(1).getIndex()].Reloads.push_back(&MI);
```

Every 8-bit spill/reload pair goes straight through the classical
static-stack expansion in
`V6ClangRegisterInfo::eliminateFrameIndex`
([V6ClangRegisterInfo.cpp lines 133–200](../llvm/lib/Target/V6CLANG/V6ClangRegisterInfo.cpp#L133))
as `STA`/`LDA` (A-target) or the HL-routed
`PUSH HL; LXI HL, slot; MOV M, r / MOV r, M; POP HL` sequence
(non-A target). The `__v6clang_ss.f` BSS slot is 1 byte per i8 spill
plus the reload-site instruction (3–6 B).

### Desired behavior

For every static-stack-eligible function, for every i8 spill slot
whose every source is `V6CLANG_SPILL8` with src = `A`:

1. Compute per-reload Δ using the design doc's
   [Reloads table](future_plans/O61_spill_in_reload_immediate.md#reloads-reload-site-only),
   specialised to V6CLANG's classical baselines (which route non-A r8
   reloads through HL rather than A):

   | Reload target | HL state at reload | Classical cost | Patched cost | Δ (saved cc) |
   |---------------|--------------------|----------------|---------------|--------------|
   | `A`           | n/a                | 16 (`LDA`)     | 8 (`MVI A,imm`) | **+8**      |
   | `r8` non-A    | HL dead            | 28 (`LXI HL,addr; MOV r,M`) | 8 (`MVI r,imm`) | **+20** |
   | `r8` non-A    | HL live            | 52 (`PUSH H; LXI HL,addr; MOV r,M; POP H`) | 8 | **+44** |

   > **Design Note**: The V6CLANG backend's classical RELOAD8 expansion
   > for non-A/H/L registers already routes through HL (preserving
   > A). The design doc's table (+16/+44) instead assumes an
   > A-routed classical baseline (`LDA; MOV r,A`). We use the V6CLANG
   > real baseline to make the Δ numbers match assembly reality.
   > The big-win case (+44) still appears when HL is live — just
   > keyed on HL liveness rather than A liveness.

2. Pick up to K winners (K ≤ 2 single-source, K ≤ 1 multi-source)
   via `BlockFrequency × Δ`, using the same `pickBestReload`
   helper already used for i16. The 2nd-patch chooser additionally
   skips `A`-target candidates (2nd-patch Δ = 8 − 16 = −8 cc) and
   `H`/`L`-target candidates (reload-side value lands in HL which
   the spill's `STA` path cannot feed cheaply in a second pass
   — symmetric to the i16 "skip HL on 2nd patch" rule).
3. Emit **one `.Lo61_N` label per winner** with `MVI <DstReg>, 0`
   carrying `MO_PATCH_IMM`.
4. Rewrite every original `V6CLANG_SPILL8` as a sequence of one
   `STA <Sym[i]+1>` per winner (kill flag only on the last).
5. Rewrite every non-winner `V6CLANG_RELOAD8` as the classical i8
   reload sequence for its destination register, reading from
   `Syms[0]+1` instead of the BSS slot — mirroring the existing
   `V6ClangRegisterInfo::eliminateFrameIndex` i8 expansion but with
   the slot address replaced by an `MCSymbol + MO_PATCH_IMM`
   operand.

### Root cause

The pass filter and the `deltaForReload` / `scoreReload` helpers are
written against `V6CLANG_SPILL16`/`V6CLANG_RELOAD16` + `{HL, DE, BC}`
destinations only. The plumbing — `MO_PATCH_IMM`, MCSymbol lowering,
constant-tracking opt-out, AsmPrinter label emission — is already
generic: `MVI` immediates route through the same
`V6ClangMCInstLower::MO_MCSymbol` case and the existing
`V6ClangLoadImmCombine.cpp` guards (`isImm()`-checked at the two MVIr
sites at lines 269 and 399) already treat non-immediate MVI operands
as opaque.

---

## 2. Strategy

### Approach: extend `V6ClangSpillPatchedReload` with a parallel 8-bit slot path

All Stage 1–3 infrastructure stays exactly as-is:

* `MO_PATCH_IMM` target flag (V6ClangInstrInfo.h).
* `V6ClangMCInstLower.cpp` lowers `MO_MCSymbol + MO_PATCH_IMM` as `Sym+1`.
* `V6ClangLoadImmCombine.cpp` already gates `MVIr` and `LXI` with
  `isImm()` (the else branch invalidates the dst), so patched MVIs
  are naturally treated as opaque constant definers.
* `V6ClangInstrInfo.cpp` INX-scan LXI guard (Stage 1 step 3.8) is
  LXI-specific; MVIr is not a pair-forming instruction, so no
  analogous scan needs guarding for i8.
* O43 `isSameAddress` already ignores MCSymbol operands.

Stage 4 adds two parallel data structures and extends three helpers:

1. **Collection loop.** Add the `V6CLANG_SPILL8` / `V6CLANG_RELOAD8` cases
   to the pseudo-grouping loop, storing into a second map
   `Slots8` keyed by FI. Keep `Slots16` untouched.
2. **Width-aware filter.** For i8 slots, require all spill sources
   to be `V6CLANG::A`. Reload destinations can be any of
   `{A, B, C, D, E, H, L}`.
3. **Δ table extension.** Add an `isI8` parameter (or overload) to
   `deltaForReload` returning the i8 table above for `{A, B..L}`
   keyed on HL-liveness. Keep the i16 path unchanged.
4. **Chooser 2nd-patch rule for i8.** Extend `pickBestReload` /
   `scoreReload` to accept a `Width ∈ {8, 16}` parameter that
   selects both the Δ table and the 2nd-patch skip set:
   * i16 1st pick: allow `{HL, DE, BC}`; i16 2nd pick: allow `{DE, BC}`.
   * i8  1st pick: allow `{A, B, C, D, E, H, L}`; i8 2nd pick: allow
     `{B, C, D, E}` (skip A, H, L — A for the −8 cc rule; H/L because
     they alias HL which is the unpatched-reload routing register
     and skipping prevents a same-pair 2nd-patch from creating an
     HL-live-across-itself hazard).
5. **Spill emitter (i8).** For each winner Sym, emit
   `STA <Sym+1, MO_PATCH_IMM>` (source register = A). Kill flag on
   the last emitted STA.
6. **Winner patch emitter (i8).** `MVI <DstReg>, 0` with pre-instr
   label and `MO_PATCH_IMM` on the imm operand.
7. **Unpatched reload emitter (i8).** Mirror the current
   `V6ClangRegisterInfo::eliminateFrameIndex` i8 paths but replace
   the `.addGlobalAddress(GV, StaticOffset)` operand with
   `.addSym(Syms[0], V6ClangII::MO_PATCH_IMM)`:
   * dst = A: `LDA <Syms[0], MO_PATCH_IMM>`.
   * dst = B/C/D/E: HL-liveness-aware
     `[PUSH H;] LXI HL, <Sym+1>; MOV r, M; [POP H;]`.
   * dst = H/L: DE-temp + other-half-dead aware, analogous to the
     existing expansion.

### Why this works

1. **Correctness of patched MVI.** `MVI` is a 2-byte instruction
   `00_DDD_110 d8`. The imm byte is at `site+1`. `STA` writes a
   byte atomically on 8080 (16 cc, no prefetch window). Patching
   the byte before the `MVI` is re-executed is safe — same
   invariants as the i16 case (§"Pitfalls and Non-Issues" in the
   design doc).
2. **Correctness of mixed i8 + i16 patches.** Different FIs are
   independent. The `Syms` allocated per i8 slot and per i16 slot
   are distinct; no aliasing between the two.
3. **Correctness of HL-live-unpatched-reload for i8.** The
   unpatched reload path may need `PUSH H; LXI HL, <Sym+1>; …; POP H`
   — this is identical to the existing static-stack i8 reload
   expansion for `B/C/D/E` with HL-live, just with a symbolic
   address. The O43 PUSH/POP-fold pass does not apply to these
   sequences (they contain no SHLD/LHLD pair).
4. **Chooser parity with design doc.** The Δ table is derived from
   the V6CLANG backend's real classical-reload expansions (the same
   sequences that `V6ClangRegisterInfo.cpp` emits today). `BlockFrequency
   × Δ` captures hot-reload preference; the K caps and 2nd-patch
   exclusions match the design doc's stated rules.
5. **No regressions to i16 path.** The i16 collection, filter,
   chooser, and rewrite paths stay byte-identical for any function
   whose 8-bit slots don't match the Stage 4 filter (or where no
   i8 slots exist). Verified by re-running the Stage 1–3 lit tests
   unchanged.

### Why not a separate pass

Three reasons to extend `V6ClangSpillPatchedReload` rather than add a
sibling pass:

* Slot grouping and chooser infrastructure are shared (~40 lines of
  code reused).
* The i8 and i16 paths never touch the same FI, so there is no
  ordering concern.
* One pass means one CLI flag (`-mv6clang-spill-patched-reload`) and
  one place to audit for correctness.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Collect i8 pseudos | Add `V6CLANG_SPILL8`/`V6CLANG_RELOAD8` cases to the grouping loop; store into a second `Slots8` map | `V6ClangSpillPatchedReload.cpp` |
| Extend Δ table | Add i8 rows (A: +8; r8 HL-dead: +20; r8 HL-live: +44) via an `isI8` branch in `deltaForReload` | same |
| Extend chooser | Add `Width` parameter (or separate i8 helper) to `scoreReload` / `pickBestReload`; 2nd-patch skip set becomes `{A, H, L}` for i8 | same |
| Add i8 slot loop | Mirror the existing i16 loop body against `Slots8`, using i8 filter (src = A), i8 emitters (STA, MVI, LDA/MOV-r-M) | same |
| Spill emitter (i8) | `STA <Sym[i]+1>` per winner, kill on last | same |
| Patch emitter (i8) | `MVI <DstReg>, 0` + `setPreInstrSymbol(Syms[i])` + `MO_PATCH_IMM` on imm | same |
| Unpatched reload emitter (i8) | LDA for A; PUSH/LXI/MOV/POP for B..L; DE-temp for H/L — all reading `<Syms[0], MO_PATCH_IMM>` | same |
| Lit test — i8 A spill / r8 reload | One A spill, one r8 reload (HL live / HL dead) → patched MVI | new `spill-patched-reload-i8.ll` |
| Lit test — i8 K=2 | Two r8 reloads both patched (MVI B + MVI C) | same |
| Lit test — i8 2nd-patch A skipped | A-target 2nd pick skipped; r8 non-A picked instead | same |
| Lit test — i8 + i16 mix | Same function patches both an HL slot and an A slot without interference | same |
| Lit test — Stage 1–3 regression | `spill-patched-reload-{hl,de-bc,k2}.ll` must still pass | existing |
| Feature test | `tests/features/37/` | new folder |

No new CLI flag — `-mv6clang-spill-patched-reload` continues to gate the
pass.

---

## 3. Implementation Steps

### Step 3.1 — Extend `deltaForReload` for i8 reloads [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangSpillPatchedReload.cpp`

Add an i8 branch. The simplest form is a second helper to keep the
i16 function body unchanged:

```cpp
// i8 Delta: classical i8 reload cost - patched MVI cost (8cc).
static int deltaForReload8(unsigned DstReg, bool HLLive) {
  if (DstReg == V6CLANG::A)
    return 8;                    // LDA (16) -> MVI A (8)
  if (DstReg == V6CLANG::B || DstReg == V6CLANG::C ||
      DstReg == V6CLANG::D || DstReg == V6CLANG::E ||
      DstReg == V6CLANG::H || DstReg == V6CLANG::L)
    return HLLive ? 44 : 20;    // classical HL-routed r8 reload
  return 0;
}
```

> **Design Note**: H/L reloads use the DE-temp path in
> `V6ClangRegisterInfo::eliminateFrameIndex`. That path's cost is close
> to the B/C/D/E HL-routed cost, so we use the same (+20/+44) Δ for
> H/L — Stage 4 treats them identically to B..E for the chooser.

> **Implementation Notes**:

### Step 3.2 — Extend chooser with `Width` parameter [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangSpillPatchedReload.cpp`

Extend `scoreReload` and `pickBestReload` to accept the slot width.
The 2nd-patch exclusion flag is reused (`AllowHL=false` for i16)
and a new `AllowA` flag is introduced for i8. Combined signature:

```cpp
static uint64_t scoreReload(const MachineInstr &R, unsigned Width,
                            bool AllowHL, bool AllowA,
                            const MachineBlockFrequencyInfo &MBFI,
                            const TargetRegisterInfo *TRI);

static int pickBestReload(ArrayRef<MachineInstr *> Reloads,
                          ArrayRef<int> Excluded, unsigned Width,
                          bool AllowHL, bool AllowA,
                          const MachineBlockFrequencyInfo &MBFI,
                          const TargetRegisterInfo *TRI);
```

* i16 1st pick: `Width=16, AllowHL=true,  AllowA=true` (A unused).
* i16 2nd pick: `Width=16, AllowHL=false, AllowA=true`.
* i8  1st pick: `Width=8,  AllowHL=true,  AllowA=true`.
* i8  2nd pick: `Width=8,  AllowHL=false, AllowA=false` (skip H/L too).

For the i8 case, `AllowHL=false` is interpreted as "also skip H and
L dst" since the single-byte sub-registers alias HL. A small helper
`isHLRelated(Reg)` returning true for `{HL, H, L}` covers both
widths.

> **Implementation Notes**:

### Step 3.3 — Collect i8 pseudos into `Slots8` [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangSpillPatchedReload.cpp`

Add to the existing MF scan:

```cpp
DenseMap<int, PerFI> Slots16, Slots8;

for (auto &MBB : MF) {
  for (auto &MI : MBB) {
    unsigned Opc = MI.getOpcode();
    if      (Opc == V6CLANG::V6CLANG_SPILL16)
      Slots16[MI.getOperand(1).getIndex()].Spills.push_back(&MI);
    else if (Opc == V6CLANG::V6CLANG_RELOAD16)
      Slots16[MI.getOperand(1).getIndex()].Reloads.push_back(&MI);
    else if (Opc == V6CLANG::V6CLANG_SPILL8)
      Slots8 [MI.getOperand(1).getIndex()].Spills.push_back(&MI);
    else if (Opc == V6CLANG::V6CLANG_RELOAD8)
      Slots8 [MI.getOperand(1).getIndex()].Reloads.push_back(&MI);
  }
}
```

> **Implementation Notes**:

### Step 3.4 — Add i8 slot rewrite loop [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangSpillPatchedReload.cpp`

After the existing i16 slot loop, add a parallel i8 loop:

```cpp
for (auto &KV : Slots8) {
  PerFI &E = KV.second;

  // Stage 4 filter (i8): >=1 A-source spill, reload dsts in any GR8.
  if (E.Spills.empty() || E.Reloads.empty())
    continue;
  if (!llvm::all_of(E.Spills, [](MachineInstr *S) {
        return S->getOperand(0).getReg() == V6CLANG::A;
      }))
    continue;
  if (!llvm::all_of(E.Reloads, [&](MachineInstr *R) {
        Register D = R->getOperand(0).getReg();
        return D == V6CLANG::A || D == V6CLANG::B || D == V6CLANG::C ||
               D == V6CLANG::D || D == V6CLANG::E || D == V6CLANG::H ||
               D == V6CLANG::L;
      }))
    continue;

  // Chooser.
  SmallVector<int, 2> Winners;
  int W1 = pickBestReload(E.Reloads, {}, /*Width=*/8,
                          /*AllowHL=*/true, /*AllowA=*/true,
                          MBFI, TRI);
  if (W1 < 0) continue;
  Winners.push_back(W1);
  if (E.Spills.size() == 1) {
    int Exc[] = {W1};
    int W2 = pickBestReload(E.Reloads, Exc, /*Width=*/8,
                            /*AllowHL=*/false, /*AllowA=*/false,
                            MBFI, TRI);
    if (W2 >= 0) Winners.push_back(W2);
  }

  // ... allocate Syms, emit STAs, emit MVIs, emit unpatched reloads ...
}
```

> **Implementation Notes**:

### Step 3.5 — Spill emitter (i8) [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangSpillPatchedReload.cpp`

Per original `V6CLANG_SPILL8` (src = A), emit one `STA` per Sym:

```cpp
for (MachineInstr *Spill : E.Spills) {
  MachineBasicBlock *MBB = Spill->getParent();
  DebugLoc DL = Spill->getDebugLoc();
  bool IsKill = Spill->getOperand(0).isKill();
  for (size_t si = 0; si < Syms.size(); ++si) {
    bool Kill = IsKill && (si + 1 == Syms.size());
    BuildMI(*MBB, Spill, DL, TII.get(V6CLANG::STA))
        .addReg(V6CLANG::A, getKillRegState(Kill))
        .addSym(Syms[si], V6ClangII::MO_PATCH_IMM);
  }
  Spill->eraseFromParent();
}
```

> **Implementation Notes**:

### Step 3.6 — Winner patch emitter (i8) [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangSpillPatchedReload.cpp`

```cpp
for (size_t wi = 0; wi < Winners.size(); ++wi) {
  MachineInstr *PR = E.Reloads[Winners[wi]];
  MachineBasicBlock *MBB = PR->getParent();
  DebugLoc DL = PR->getDebugLoc();
  Register Dst = PR->getOperand(0).getReg();
  MachineInstrBuilder NewMvi =
      BuildMI(*MBB, PR, DL, TII.get(V6CLANG::MVIr))
          .addReg(Dst, RegState::Define)
          .addImm(0);
  NewMvi->getOperand(1).setTargetFlags(V6ClangII::MO_PATCH_IMM);
  NewMvi->setPreInstrSymbol(MF, Syms[wi]);
  PR->eraseFromParent();
}
```

> **Implementation Notes**:

### Step 3.7 — Unpatched reload emitter (i8) [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangSpillPatchedReload.cpp`

Mirror `V6ClangRegisterInfo::eliminateFrameIndex`'s `V6CLANG_RELOAD8`
branches (A / H / L / other r8), replacing the
`.addGlobalAddress(GV, StaticOffset)` operand with
`.addSym(Syms[0], V6ClangII::MO_PATCH_IMM)` and using the existing
`isRegDeadAfterMI` helper for HL / DE / other-half liveness.

```cpp
auto isWinner = [&](size_t i) {
  return llvm::is_contained(Winners, (int)i);
};
for (size_t i = 0, n = E.Reloads.size(); i < n; ++i) {
  if (isWinner(i)) continue;
  MachineInstr *R = E.Reloads[i];
  MachineBasicBlock *MBB = R->getParent();
  DebugLoc DL = R->getDebugLoc();
  Register Dst = R->getOperand(0).getReg();

  if (Dst == V6CLANG::A) {
    BuildMI(*MBB, R, DL, TII.get(V6CLANG::LDA), V6CLANG::A)
        .addSym(Syms[0], V6ClangII::MO_PATCH_IMM);
  } else if (Dst == V6CLANG::H || Dst == V6CLANG::L) {
    // DE-temp path, mirrors V6ClangRegisterInfo expansion.
    // ... see existing code for the exact sequence ...
  } else {
    // B/C/D/E: PUSH H; LXI HL, Syms[0]+1; MOV r, M; POP H
    // (skip PUSH/POP when HL dead after R).
    // ... see existing code ...
  }
  R->eraseFromParent();
}
```

> **Design Note**: Keep the emitter structurally close to
> `V6ClangRegisterInfo::eliminateFrameIndex`'s i8 RELOAD branches so
> future refactors of the static-stack expansion automatically
> guide any equivalent O61 adjustments.

> **Implementation Notes**:

### Step 3.8 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**:

### Step 3.9 — Lit test: i8 patched reload [x]

**File**:
`llvm-project/llvm/test/CodeGen/V6CLANG/spill-patched-reload-i8.ll` (new)

Four cases:

1. **Single A spill, single B-target reload (HL live)** — expect
   `STA .Lo61_0+1`, `.Lo61_0:` label then `MVI B, 0`. No
   `__v6clang_ss.f+N` BSS slot.
2. **K=2 single-source (B + C reloads)** — expect two labels,
   two STAs at the spill site, two `MVI r, 0`s at the reload
   sites.
3. **2nd-patch A skipped** — spill A, reloads = `[B, A]`.
   Expect B patched (1st pick, Δ=+20 or +44), A left classical
   (`LDA .Lo61_0+1`) because 2nd-patch A is forbidden.
4. **Multi-source K=1** — two A spills (diverging paths), one
   r8 reload. Expect both STAs retargeted to `.Lo61_0+1`, one
   `MVI r, 0` at the reload.

Include a mixed i8/i16 function to verify no interference.

> **Implementation Notes**:

### Step 3.10 — Lit test: Stage 1–3 regression [x]

Re-run `spill-patched-reload-hl.ll`,
`spill-patched-reload-de-bc.ll`, and `spill-patched-reload-k2.ll`.
Stage 4 must leave these byte-identical — the i16 path is
untouched except for the shared helper signature changes.

> **Implementation Notes**:

### Step 3.11 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**:

### Step 3.12 — Verification assembly steps from `tests\features\README.md` [x]

Test folder `tests/features/37/` (created in Phase 1). Compile
`v6clang.c` with
`-mllvm -mv6clang-spill-patched-reload -mllvm -v6clang-disable-shld-lhld-fold`
into `v6clang_new01.asm`. Verify i8 slot patching fires where
Stage 3 left the classical `STA/LDA`/HL-routed path in place.
Iterate `_new02.asm`, `_new03.asm` … as needed.

> **Implementation Notes**:

### Step 3.13 — Make sure result.txt is created (`tests\features\README.md`) [x]

Per the test folder template: C source, c8080 reference body,
c8080 stats, v6clang Stage 3 baseline, v6clang Stage 4 asm,
v6clang stats, per-slot impact table for i8 scenarios, and the
chooser log (1st/2nd pick per slot).

> **Implementation Notes**:

### Step 3.14 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**:

---

## 4. Expected Results

### Example 1 — A spill, B-target reload (HL live)

Current (Stage 3, classical i8 expansion):

```
; spill A
  STA   __v6clang_ss.f+0        ; 16cc, 3B
  ...
; reload to B with HL live
  PUSH  H                   ; 12cc, 1B
  LXI   HL, __v6clang_ss.f+0    ; 12cc, 3B
  MOV   B, M                ; 8cc,  1B
  POP   H                   ; 12cc, 1B
```

Total spill+reload: **60 cc, 9 B** plus 1 B BSS.

Stage 4:

```
; spill A
  STA   .Lo61_0+1           ; 16cc, 3B
  ...
.Lo61_0:
  MVI   B, 0                ; 8cc,  2B   ; imm was patched
```

Total: **24 cc, 5 B**, 0 B BSS. **Δ = −36 cc, −4 B, −1 B BSS.**

### Example 2 — A spill, K=2 single-source (B + C reloads, HL dead)

Stage 3: picks the highest-Δ reload (say B), emits K=1. C reload
stays classical `LXI HL, .Lo61_0+1; MOV C, M` (28 cc).

Stage 4 K=2:

```
  STA   .Lo61_0+1           ; 16cc
  STA   .Lo61_1+1           ; 16cc
...
.Lo61_0:
  MVI   B, 0                ; 8cc
...
.Lo61_1:
  MVI   C, 0                ; 8cc
```

Cycle-wise the 2nd patch pays +16 cc (extra STA) in exchange for
−20 cc (LXI HL + MOV C, M → MVI C, imm). **Net = −4 cc, +1 B
bytes** for the K=2 vs K=1 choice — chooser admits it only when
the reload is in a hot block.

### Example 3 — 2nd-patch A skipped

A spill, reloads = `[B (hot), A (cold)]`. Stage 4 picks B (1st)
then tries for a 2nd; the chooser rejects A (2nd-patch Δ = −8).
A reload emits as classical `LDA .Lo61_0+1` reading from the
patched B-site's imm byte.

### Example 4 — multi-source K=1

Two A spills on diverging paths, one B-target reload. Stage 3
left this as classical (Stage 3 allows multi-source K=1 only for
i16). Stage 4 admits it as multi-source K=1 for i8:

```
  STA   .Lo61_0+1           ; spill #1
  ...
  STA   .Lo61_0+1           ; spill #2 (same label, same byte)
  ...
.Lo61_0:
  MVI   B, 0
```

**Δ per patched r8 reload = +20..+44 cc** (HL state-dependent).

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Patched `MVI r, imm` misinterpreted as a compile-time constant by downstream passes | `MO_PATCH_IMM` + non-imm `MachineOperand`; existing `isImm()` guards at the two MVIr sites in `V6ClangLoadImmCombine.cpp` (lines 269, 399) already route to `invalidate(DstReg)`. Verified during Stage 1 audit. |
| i8 slot shared between an i8 spill and a stray i16 reload (or vice versa) | RA-level invariant: `V6CLANG_SPILL8` and `V6CLANG_RELOAD8` only reference 1-byte FIs. `Slots8` and `Slots16` are keyed by FI and never overlap. |
| `STA Sym+1` when A is already clobbered by a concurrent expansion | O61 runs post-RA and post-SpillForwarding but before PEI — the `V6CLANG_SPILL8` pseudo declares `A` as its source, so RA guarantees A is defined immediately before. |
| `MVI r, 0` with `r = A` and a live flags dependency | `MVI` does not touch flags. No interaction with `V6ClangRedundantFlagElim`. Same reasoning as the LXI patched-reload case. |
| Unpatched HL-live reload clobbering A via `LDA` path | The unpatched i8 reload mirrors the existing static-stack HL-routed expansion for `B..E` — A is not clobbered on that path. A-target unpatched reloads do clobber A, but A is exactly the target being redefined, which is the intended semantics. |
| 2nd-patch rule "skip H/L" too conservative | The 2nd-patch A-skip is load-bearing (Δ = −8 cc); the H/L-skip is a safety measure because H/L sub-registers alias HL which is used in the unpatched reload's own routing. Safe conservative default; Stage 5+ can relax if measurements show wins. |
| Existing Stage 3 lit tests regress | Helper signature change (`Width` + `AllowA`) defaulted at i16 call sites to current behaviour; re-run `spill-patched-reload-{hl,de-bc,k2}.ll` in step 3.10 to confirm byte-identical output. |

---

## 6. Relationship to Other Improvements

* **O10 Static Stack Allocation** — required prerequisite; i8 slot
  addresses must be link-time constants.
* **O43 SHLD/LHLD to PUSH/POP** — does not apply to STA/LDA pairs,
  so no interaction with the i8 path.
* **O42 Liveness-Aware Expansion** — the i8 unpatched reload emitter
  already reads HL liveness via `isRegDeadAfterMI`, matching O42's
  conditional `PUSH H` / `POP H` elision in `V6ClangRegisterInfo.cpp`.
* **Stage 5 (future)** — extends spill-side handling from A to any
  GR8 (and from HL to DE/BC for i16). Cleanly layers on top of
  Stage 4 once the A-routing-at-spill invariant is relaxed.

---

## 7. Future Enhancements

* **Non-A i8 spill sources** (Stage 5 territory) — admit
  `V6CLANG_SPILL8` with non-A source by emitting `MOV A, r; STA Sym+1`
  (guarded by A-liveness; wrap with `PUSH PSW` / `POP PSW` when A
  is live after the spill).
* **H/L-target 2nd patch** — the current Stage 4 conservative rule
  skips H/L on 2nd patches. Measurements may show wins in some
  cases; revisit with a per-function cost comparison.
* **DE-temp routing for H/L unpatched reloads** — the exact
  sequence mirrors the static-stack expansion; a future refactor
  could share the helper between `V6ClangRegisterInfo` and
  `V6ClangSpillPatchedReload`.

---

## 8. References

* [O61 Design](future_plans/O61_spill_in_reload_immediate.md) — full
  design incl. Reloads table, cost model, staged rollout.
* [O61 Stage 1 Plan](plan_O61_spill_in_reload_immediate.md) —
  infrastructure (MO_PATCH_IMM, MCSymbol lowering).
* [O61 Stage 2 Plan](plan_O61_spill_in_reload_immediate_stage2.md) —
  cost model, DE/BC reload targets.
* [O61 Stage 3 Plan](plan_O61_spill_in_reload_immediate_stage3.md) —
  K ≤ 2 single-source, multi-source K ≤ 1.
* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md).
* [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md).
* [Future Improvements](future_plans/README.md).
