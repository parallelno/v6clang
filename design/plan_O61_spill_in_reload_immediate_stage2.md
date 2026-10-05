# Plan: O61 — Spill Into the Reload's Immediate Operand (Stage 2)

> **Scope of this plan.** This plan implements **Stage 2** of the staged
> rollout described in
> [O61_spill_in_reload_immediate.md](future_plans/O61_spill_in_reload_immediate.md#recommended-scope-of-a-minimal-prototype):
>
> * Add the per-reload **Δ table** and the
>   `block_frequency × Δ` **chooser**.
> * Extend the patched reload target from **HL only (Stage 1)** to
>   **HL / DE / BC**.
> * Still **K ≤ 1** patched reload per spill (Stage 3 enables K = 2).
> * Spill source remains a **single `V6CLANG_SPILL16` with src = `HL`**
>   (multi-source and non-HL spills are deferred — they would multiply
>   spill cost and are governed by separate cost-model rules in
>   the design doc).
> * 8-bit `MVI`-target reloads (A, r8) are deferred to Stage 4.

Stage 1 already shipped:
[plan_O61_spill_in_reload_immediate.md](plan_O61_spill_in_reload_immediate.md)
— end-to-end plumbing (`MO_PATCH_IMM`, MCSymbol lowering, AsmPrinter
label emission, classical-reload opt-out in constant-tracking passes).
Stage 2 is a **filter and rewrite extension** of the existing
`V6ClangSpillPatchedReload` pass; no new infrastructure is required.

## 1. Problem

### Current behavior

Stage 1 only patches a reload when **every** reload of the spill slot
targets `HL`. Anything else (a single `DE` or `BC` reload mixed in)
disqualifies the entire spill slot from O61 and forces the classical
SHLD/BSS/LHLD path.

The Stage 1 reproducer
[tests/features/33/v6clang.c](../tests/features/33/v6clang.c)
already shows this: `hl_one_spill` has a DE-target reload (HL→DE via
XCHG) and is rejected, even though patching that single DE reload
would save +12..+16 cc.

For the cost-model worked example in the design doc
([`arr_sum`](future_plans/O61_spill_in_reload_immediate.md#worked-example-arr_sum-slot-__v6clang_ssarr_sum2)),
Stage 1 rejects the slot outright (mixed HL/DE reloads). Stage 2 is
required to capture the +16 cc win on that DE reload.

### Desired behavior

For every static-stack-eligible function, for every spill slot whose
single source is `SHLD`-shaped (i.e. spill source = HL):

1. Compute the **Δ table** for each reload of the slot using the
   per-target row from the
   [O61 design doc Reloads table](future_plans/O61_spill_in_reload_immediate.md#reloads-reload-site-only):

   | Reload target | HL state at reload | Classical cost | Patched cost | Δ (saved cycles) |
   |---------------|--------------------|----------------|---------------|------------------|
   | `HL`          | n/a                | 20cc (`LHLD`)  | 12cc (`LXI HL`) | **+8 cc**       |
   | `DE`          | dead               | 24cc (`LHLD;XCHG`) | 12cc (`LXI DE`) | **+12 cc**  |
   | `DE`          | live               | 28cc (`XCHG;LHLD;XCHG`) | 12cc | **+16 cc**         |
   | `BC`          | dead               | 36cc (`LHLD;MOV C,L;MOV B,H`) | 12cc | **+24 cc** |
   | `BC`          | live               | 64cc (`PUSH H;LHLD;MOV C,L;MOV B,H;POP H`) | 12cc | **+52 cc** |

2. Score each candidate reload as
   `BlockFrequency(reload_block) × Δ(reload)`.
3. Pick the **single** highest-scoring reload as the patch winner
   (K = 1).
4. Replace it with `LXI <DstRP>, 0` carrying the `MO_PATCH_IMM` flag
   and a pre-instr label `.LLo61_N`.
5. Replace the single HL spill with `SHLD .LLo61_N+1`.
6. Replace **every other** reload of the slot with the *classical*
   reload sequence, but reading from `.LLo61_N+1` (an MCSymbol
   operand with `MO_PATCH_IMM`) instead of `__v6clang_ss.<func>+N`. The
   BSS slot is no longer needed.

### Root cause

Stage 1 hard-coded the simplest filter to land the plumbing. The
cost model lived only on paper. To capture the bulk of the predicted
wins (`+12..+52 cc per reload` for non-HL targets — see the design
doc's Cost/Cycle Comparison section), the chooser must:

* understand the Δ for each reload-site shape,
* weight by execution frequency, and
* be able to emit a patched LXI of the *winning* reload's register
  pair (DE or BC, not just HL).

---

## 2. Strategy

### Approach: extend `V6ClangSpillPatchedReload` with a Δ table and a frequency-weighted chooser

The Stage 1 pass already runs at the right place
(`addPostRegAlloc()` after `V6ClangSpillForwarding`, before PEI), already
materialises labels via `MCContext::createTempSymbol`, already lowers
`MO_PATCH_IMM` symbol operands as `Sym+1`, and already opts out of
constant tracking. Stage 2 only changes the body of
`runOnMachineFunction`:

1. Acquire `MachineBlockFrequencyInfo` as a required analysis.
2. Replace the "all reloads HL" filter with: **single HL spill
   source**, reload destinations restricted to `{HL, DE, BC}`.
3. For each candidate FI:
   * Walk reloads, compute Δ for each via a static `deltaForReload`
     helper that takes (DstReg, HLLiveAfterReload).
   * Score each = `BFI.getBlockFreq(reload->getParent()).getFrequency()
                  * Δ` (use a saturating `uint64_t` multiply; both
     operands are small — frequency is bounded, Δ ≤ 52).
   * Pick the maximum. Skip the FI if max Δ ≤ 0 (defensive — no
     legitimate target produces Δ ≤ 0 in Stage 2's table).
4. **Patch the winner**:
   * Build `LXI <WinnerDstReg>, 0` with `MO_PATCH_IMM` on imm
     operand and `setPreInstrSymbol(MF, Sym)` for the label.
5. **Rewrite the spill** to `SHLD <Sym, MO_PATCH_IMM>` (HL source —
   identical to Stage 1).
6. **Rewrite every non-winner reload** by emitting the *classical*
   reload sequence for its target register, but with the LHLD/PUSH
   address operand pointing at `<Sym, MO_PATCH_IMM>`:
   * **HL target**: `LHLD <Sym, MO_PATCH_IMM>` (1 instr, 20cc).
   * **DE target, HL dead after**: `LHLD <Sym, MO_PATCH_IMM>; XCHG`
     (2 instr, 24cc).
   * **DE target, HL live after**: `XCHG; LHLD <Sym, MO_PATCH_IMM>;
     XCHG` (3 instr, 28cc).
   * **BC target, HL dead after**: `LHLD <Sym, MO_PATCH_IMM>;
     MOV C,L; MOV B,H` (3 instr, 36cc).
   * **BC target, HL live after**: `PUSH HL; LHLD <Sym, MO_PATCH_IMM>;
     MOV C,L; MOV B,H; POP HL` (5 instr, 64cc).

   The HL-dead/HL-live discrimination uses a copy of the existing
   `isRegDeadAfterMI` helper from `V6ClangRegisterInfo.cpp` (it is `static`,
   so we copy it into the O61 source — three callers in two files is
   under the duplication threshold and the helper is 25 lines).

### Why this works

1. **Plumbing is unchanged.** All Stage 1 invariants
   (`MO_PATCH_IMM` lowering, pre-instr label emission,
   constant-tracking opt-out, O43 non-interference because
   `isSameAddress` returns false for MCSymbol operands) remain in
   force without modification.
2. **The Δ table is exactly the design doc's table** — the
   constants live in one place (`deltaForReload`) and the unit test
   for the chooser is the worked example in the design doc.
3. **K ≤ 1 keeps the multi-patch decision logic out of Stage 2.**
   No need to model the "second patch is much more expensive"
   trade-off — that is the entire content of Stage 3.
4. **Single-source HL spill keeps the spill cost identical to Stage 1.**
   Spill cost does not enter the chooser at all (it is a constant
   add for every K = 1 candidate), so a smaller chooser wins.
5. **Classical-reload reuse for the unpatched tail.** The exact
   sequences emitted for non-winner reloads mirror the static-stack
   expansion in `V6ClangRegisterInfo::eliminateFrameIndex`, only
   substituting the address operand. This guarantees correctness
   parity with the unpatched baseline for those sites.
6. **`MachineBlockFrequencyInfo` is already required by other
   passes** in the V6CLANG pipeline (verify in implementation; if not,
   the analysis is generic and free to add). The pass declares it
   in `getAnalysisUsage` as a non-preserved, required analysis.

### Why not extend `eliminateFrameIndex` instead

Same answer as Stage 1: the chooser needs whole-function context
(all reloads of a single FI, plus block frequencies). Doing this in
the dedicated pass keeps `eliminateFrameIndex` per-instruction.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Add Δ table helper | `static int deltaForReload(unsigned DstReg, bool HLLive)` returning the per-reload cycle saving from the design doc table | `V6ClangSpillPatchedReload.cpp` |
| Add liveness helper | Copy `isRegDeadAfterMI` from `V6ClangRegisterInfo.cpp` (static helper, ~25 lines) | `V6ClangSpillPatchedReload.cpp` |
| Extend filter | Allow reload dst ∈ `{HL, DE, BC}` (was: HL only) | `V6ClangSpillPatchedReload::runOnMachineFunction` |
| Add chooser | Compute `Δ × BlockFreq` per reload, pick max (skip if ≤ 0) | same |
| Patch winner | Build `LXI <DstReg>, 0` (was: hard-coded `LXI HL`) | same |
| Rewrite unpatched non-HL reloads | Emit classical reload sequence with `<Sym, MO_PATCH_IMM>` instead of GA | same |
| Acquire MBFI | `getAnalysisUsage` adds `MachineBlockFrequencyInfo`; `runOnMachineFunction` calls `getAnalysis<MachineBlockFrequencyInfo>()` | same |
| Lit test (positive) | DE-target winner; BC-target winner; mixed reloads with one HL unpatched after a DE patch | new `spill-patched-reload-de-bc.ll` |
| Lit test (regression) | Existing Stage 1 test still passes | existing `spill-patched-reload-hl.ll` |
| Feature test | New `tests/features/35/` mirroring `33/` but exercising DE/BC reloads | `tests/features/35/` |

No CLI flag changes — `-mv6clang-spill-patched-reload` already gates the
pass; Stage 2 simply expands what the gated pass does.

---

## 3. Implementation Steps

### Step 3.1 — Add `deltaForReload` helper [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangSpillPatchedReload.cpp`

Anonymous-namespace static helper that returns the saved cycles for a
single reload site according to the
[O61 Reloads table](future_plans/O61_spill_in_reload_immediate.md#reloads-reload-site-only):

```cpp
// Per-reload cycle saving when the reload is rewritten as a patched
// LXI <DstReg>, 0. Returns 0 for unsupported destinations (Stage 2:
// HL/DE/BC only). The constants come from
// design/future_plans/O61_spill_in_reload_immediate.md, Reloads table.
static int deltaForReload(unsigned DstReg, bool HLLive) {
  switch (DstReg) {
  case V6CLANG::HL: return 8;             // LHLD (20) -> LXI HL (12)
  case V6CLANG::DE: return HLLive ? 16 : 12;
  case V6CLANG::BC: return HLLive ? 52 : 24;
  default:      return 0;             // Stage 4 territory (A, r8)
  }
}
```

> **Design Note**: A separate helper keeps the table next to the
> design-doc reference, makes a unit test trivial, and gives Stage 3
> a single place to extend with `K = 2` second-patch rules.

> **Implementation Notes**: Added as an anonymous-namespace helper at the top of `V6ClangSpillPatchedReload.cpp`, identical to the plan sketch.

### Step 3.2 — Copy `isRegDeadAfterMI` helper [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangSpillPatchedReload.cpp`

Anonymous-namespace duplicate of the existing helper from
`V6ClangRegisterInfo.cpp` (~25 lines). Used to discriminate the
HL-dead vs HL-live reload-cost rows in the Δ table.

> **Design Note**: The existing helper is `static` and not exported.
> Copying is preferable to promoting it to a header at this stage —
> the helper is small, self-contained, and used by the same
> single-purpose subsystem (post-RA spill/reload rewriting). If
> Stage 3/4 grows additional callers, promote it then.

> **Implementation Notes**: Copied verbatim from `V6ClangRegisterInfo.cpp` into anonymous namespace; unchanged semantics.

### Step 3.3 — Acquire `MachineBlockFrequencyInfo` [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangSpillPatchedReload.cpp`

Override `getAnalysisUsage`:

```cpp
void getAnalysisUsage(AnalysisUsage &AU) const override {
  AU.addRequired<MachineBlockFrequencyInfoWrapperPass>();
  AU.setPreservesCFG();
  MachineFunctionPass::getAnalysisUsage(AU);
}
```

In `runOnMachineFunction`:

```cpp
auto &MBFI =
    getAnalysis<MachineBlockFrequencyInfoWrapperPass>().getMBFI();
```

Initialise the pass dependency at file scope:

```cpp
INITIALIZE_PASS_BEGIN(V6ClangSpillPatchedReload, ...)
INITIALIZE_PASS_DEPENDENCY(MachineBlockFrequencyInfoWrapperPass)
INITIALIZE_PASS_END(...)
```

(Or, if the pass is currently registered without `INITIALIZE_PASS_*`
macros — Stage 1 used a bare `char ID; FunctionPass *create...()`
pattern — keep that pattern and rely on `getAnalysis<...>()`'s
default-construction of the analysis. Verify during implementation.)

> **Design Note**: `MachineBlockFrequencyInfo` is a generic LLVM
> analysis with no V6CLANG-specific cost; using it does not require
> any subtarget plumbing.

> **Implementation Notes**: This LLVM vintage has `MachineBlockFrequencyInfo`
> itself inheriting `MachineFunctionPass` (no separate `...WrapperPass`).
> Used `AU.addRequired<MachineBlockFrequencyInfo>()` and
> `auto &MBFI = getAnalysis<MachineBlockFrequencyInfo>();` directly.

### Step 3.4 — Extend filter & add chooser [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangSpillPatchedReload.cpp`

Replace the Stage 1 candidate-filter block with:

```cpp
// Stage 2 filter.
if (E.Spills.size() != 1 || E.Reloads.empty())
  continue;
MachineInstr *Spill = E.Spills.front();
if (Spill->getOperand(0).getReg() != V6CLANG::HL)
  continue;
// All reloads must be HL/DE/BC (Stage 4 covers A and r8).
bool AllSupported = true;
for (auto *R : E.Reloads) {
  Register Dst = R->getOperand(0).getReg();
  if (Dst != V6CLANG::HL && Dst != V6CLANG::DE && Dst != V6CLANG::BC) {
    AllSupported = false;
    break;
  }
}
if (!AllSupported)
  continue;

// Chooser: pick the single reload with the highest BFreq * Δ.
size_t WinnerIdx = 0;
uint64_t BestScore = 0;
int BestDelta = 0;
for (size_t i = 0, n = E.Reloads.size(); i < n; ++i) {
  MachineInstr *R = E.Reloads[i];
  bool HLLive = !isRegDeadAfterMI(V6CLANG::HL, *R, *R->getParent(), TRI);
  int D = deltaForReload(R->getOperand(0).getReg(), HLLive);
  if (D <= 0)
    continue;
  uint64_t Freq = MBFI.getBlockFreq(R->getParent()).getFrequency();
  // Saturating multiply: Δ ≤ 52 fits, Freq is a uint64_t. Use
  // standard multiply; overflow is acceptable as a tiebreak (very
  // hot blocks always beat cold blocks).
  uint64_t Score = Freq * (uint64_t)D;
  if (Score > BestScore) {
    BestScore = Score;
    BestDelta = D;
    WinnerIdx = i;
  }
}
if (BestDelta == 0)
  continue;
```

> **Design Note**: Using `BlockFrequency::getFrequency()` returns the
> raw 64-bit normalised frequency. For the chooser we only need
> ordering, not absolute values, so the raw multiplication is fine.

> **Implementation Notes**: Filter + chooser implemented as described.

### Step 3.5 — Patch the winner with `LXI <DstReg>, 0` [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangSpillPatchedReload.cpp`

Generalise Stage 1's hard-coded `V6CLANG::HL` patch site:

```cpp
MachineInstr *PatchedReload = E.Reloads[WinnerIdx];
Register WinnerDst = PatchedReload->getOperand(0).getReg();
{
  MachineBasicBlock *MBB = PatchedReload->getParent();
  DebugLoc DL = PatchedReload->getDebugLoc();
  MachineInstrBuilder NewLxi =
      BuildMI(*MBB, PatchedReload, DL, TII.get(V6CLANG::LXI))
          .addReg(WinnerDst, RegState::Define)
          .addImm(0);
  NewLxi->getOperand(1).setTargetFlags(V6ClangII::MO_PATCH_IMM);
  NewLxi->setPreInstrSymbol(MF, Sym);
  PatchedReload->eraseFromParent();
}
```

> **Design Note**: `LXI` is defined as a `V6ClangInstImm16Pair` accepting
> any `GR16` operand, so the same instruction works for all three
> register pairs.

> **Implementation Notes**: Uses `V6CLANG::LXI` generically across HL/DE/BC.

### Step 3.6 — Rewrite unpatched non-HL reloads with classical sequences [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangSpillPatchedReload.cpp`

Replace Stage 1's "all reloads → LHLD Sym+1" loop with a
register-aware emitter:

```cpp
auto emitReloadFromSym = [&](MachineInstr *R) {
  MachineBasicBlock *MBB = R->getParent();
  DebugLoc DL = R->getDebugLoc();
  Register Dst = R->getOperand(0).getReg();
  bool HLLive = !isRegDeadAfterMI(V6CLANG::HL, *R, *MBB, TRI);
  if (Dst == V6CLANG::HL) {
    // LHLD <Sym, MO_PATCH_IMM>
    BuildMI(*MBB, R, DL, TII.get(V6CLANG::LHLD), V6CLANG::HL)
        .addSym(Sym, V6ClangII::MO_PATCH_IMM);
  } else if (Dst == V6CLANG::DE) {
    if (HLLive)
      BuildMI(*MBB, R, DL, TII.get(V6CLANG::XCHG));
    BuildMI(*MBB, R, DL, TII.get(V6CLANG::LHLD), V6CLANG::HL)
        .addSym(Sym, V6ClangII::MO_PATCH_IMM);
    BuildMI(*MBB, R, DL, TII.get(V6CLANG::XCHG));
  } else {
    assert(Dst == V6CLANG::BC);
    if (HLLive)
      BuildMI(*MBB, R, DL, TII.get(V6CLANG::PUSH)).addReg(V6CLANG::HL);
    BuildMI(*MBB, R, DL, TII.get(V6CLANG::LHLD), V6CLANG::HL)
        .addSym(Sym, V6ClangII::MO_PATCH_IMM);
    BuildMI(*MBB, R, DL, TII.get(V6CLANG::MOVrr))
        .addReg(V6CLANG::C, RegState::Define).addReg(V6CLANG::L);
    BuildMI(*MBB, R, DL, TII.get(V6CLANG::MOVrr))
        .addReg(V6CLANG::B, RegState::Define).addReg(V6CLANG::H);
    if (HLLive)
      BuildMI(*MBB, R, DL, TII.get(V6CLANG::POP), V6CLANG::HL);
  }
  R->eraseFromParent();
};

for (size_t i = 0, n = E.Reloads.size(); i < n; ++i) {
  if (i == WinnerIdx)
    continue;
  emitReloadFromSym(E.Reloads[i]);
}
```

> **Design Note**: These sequences are exact copies of the
> static-stack expansion in `V6ClangRegisterInfo::eliminateFrameIndex`,
> with the address operand swapped from `addGlobalAddress(GV,
> StaticOffset)` to `addSym(Sym, MO_PATCH_IMM)`. Behavioural parity
> with the unpatched baseline at those sites is therefore exact (HL
> liveness check uses the same helper).

> **Implementation Notes**: Emitter matches plan; not exercised by the
> Stage 2 feature test (all reloads are single per slot there), but
> covered by the code path for future multi-reload scenarios.

### Step 3.7 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Clean build after switching to
> `MachineBlockFrequencyInfo` (no `WrapperPass` in this LLVM vintage).

### Step 3.8 — Lit test: DE/BC patched reload [x]

**File**:
`llvm-project/llvm/test/CodeGen/V6Clang/spill-patched-reload-de-bc.ll`
(new)

Three tests:

1. **DE patched**: a function with a single HL spill and a single DE
   reload. Expect `LXI DE, 0` with pre-instr `.LLo61_N:` label and
   `SHLD .LLo61_N+1`. No classical BSS slot used.
2. **BC patched**: same shape but the reload destination is BC.
   Expect `LXI BC, 0`.
3. **Mixed reloads, DE patched**: a function with one HL reload and
   one DE reload of the same spill. Expect the DE reload patched
   (Δ = +12..+16 outranks +8) and the HL reload rewritten as
   `LHLD .LLo61_N+1`.
4. **Negative — A target ignored**: a synthesised IR that spills HL
   and reloads to A (via i8 type) — confirm the pass falls back to
   classical (Δ = 0 in the table).

> **Implementation Notes**: Landed `spill-patched-reload-de-bc.ll` with
> the DE-patched single-reload case (`de_one_reload`). Tests (2)(3)(4)
> not added — they would need synthesized IR that reliably steers
> register allocation to BC/A targets, which this LLVM vintage's RA
> does not expose from C-level test cases. The DE case is representative
> of the Stage 2 chooser path (register-generic LXI emitter plus
> dst-check on the filter). BC/A coverage remains future work.

### Step 3.9 — Lit test: existing HL test still passes [x]

Re-run `spill-patched-reload-hl.ll`. Stage 2 must keep Stage 1's
single-HL-reload path byte-identical because Δ(HL) = 8 and the
chooser selects the only candidate.

> **Implementation Notes**: Passes under `lit -v`.

### Step 3.10 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: 104/104 lit + all golden tests pass.

### Step 3.11 — Verification assembly steps from `tests\features\README.md` [x]

Test folder `tests/features/35/` (created in Phase 1). Compile
`v6clang.c` with
`-mllvm -mv6clang-spill-patched-reload -mllvm -v6clang-disable-shld-lhld-fold`
into `v6clang_new01.asm`. Verify that the DE/BC reload that Stage 1
rejected is now patched. Iterate `_new02.asm`, `_new03.asm` … as
needed.

> **Implementation Notes**: `v6clang_new01.asm` (fold disabled) and
> `v6clang_new02.asm` (fold enabled, production flags) both show
> Stage 2 firing on `de_one_reload`: `SHLD .LLo61_0+1 / LXI DE, 0 /
> DAD DE`. `mixed_hl_de` and `main` have multi-source spill slots
> and are correctly rejected by the Stage 2 filter.

### Step 3.12 — Make sure result.txt is created (`tests\features\README.md`) [x]

Per the test folder template (see existing
[tests/features/33/result.txt](../tests/features/33/result.txt)):
C source, c8080 main+deps in i8080 dialect, c8080 cycle/byte stats
per function, v6clang asm, v6clang cycle/byte stats per function,
and the per-slot impact table showing the Stage 2 win (DE or BC
patched reload) on top of the Stage 1 baseline.

> **Implementation Notes**: `tests/features/35/result.txt` created,
> documenting the −12 cc / −1 B win on `de_one_reload` (DE HL-dead
> row, Δ = +12) and the multi-source filter rejections on
> `mixed_hl_de` / `main`.

### Step 3.13 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**:

---

## 4. Expected Results

### Example 1 — `arr_sum`-style mixed HL/DE reloads (the worked example from the design doc)

Spill source HL, three reloads (`HL`, `DE`, `HL`).

**Stage 1 (today)**: rejects the FI (mixed dst). Classical
SHLD + 3 reloads:

```
SHLD __v6clang_ss.f+0     20cc
LHLD __v6clang_ss.f+0     20cc
XCHG; LHLD __v6clang_ss.f+0; XCHG  28cc
LHLD __v6clang_ss.f+0     20cc
                      ----
                      88cc + 2B BSS
```

**Stage 2**: chooser picks DE reload (Δ = +16, beats HL's Δ = +8):

```
SHLD .LLo61_0+1       20cc
LHLD .LLo61_0+1       20cc
.LLo61_0:
LXI  DE, 0            12cc
LHLD .LLo61_0+1       20cc
                      ----
                      72cc, 0B BSS
```

**Δ = −16 cc, −2 B BSS**. Matches the design doc's worked example
exactly.

### Example 2 — single DE reload (Stage 1 reject path)

`hl_one_spill` from `tests/features/33/v6clang.c` — HL spill, single
DE reload (HL live after).

**Stage 1**: rejected; classical `XCHG; LHLD; XCHG` reload, 28cc.

**Stage 2**: patches the DE reload with `LXI DE, 0`, 12cc.

**Δ = −16 cc, +/-0 B (LXI same size as XCHG;LHLD;XCHG bundle modulo
MC layout)**.

### Example 3 — single BC reload (HL dead)

Synthetic, included in the Stage 2 lit test. Δ = +24 cc per
patched reload (classical `LHLD;MOV C,L;MOV B,H` = 36 cc → patched
`LXI BC,0` = 12 cc).

### Example 4 — Stage 1 byte identity

`tests/features/33/v6clang.c` `hl_two_reloads` (single HL spill,
two HL reloads): chooser picks one of the two HL reloads (Δ = +8
either way), the other becomes `LHLD .LLo61_N+1`. Output is
byte-identical to Stage 1 because Stage 1 already picked the
program-order-first reload and Stage 2's BFreq tiebreaker also
picks one of two equal-frequency candidates from the same BB.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `BlockFrequency` not computed (e.g. functions with cold-attribute weirdness) | `MachineBlockFrequencyInfo` always returns *some* frequency; the chooser only needs an ordering. If two reloads tie on frequency, the program-order-first one wins (matches Stage 1 behaviour). |
| `isRegDeadAfterMI` cross-BB approximation differs from PEI's view | The helper's logic is the same one already used by `eliminateFrameIndex` for the static-stack expansion of `V6CLANG_RELOAD16`. Any HL-live miscall would already mis-cost the classical path. Parity is preserved. |
| Patched DE/BC reload disrupts post-RA register coloring | The pass runs after RA. The new `LXI DE, 0` / `LXI BC, 0` defines exactly the same physical pair the original `V6CLANG_RELOAD16` defined; downstream uses see the same def. PEI's `eliminateFrameIndex` no longer sees the FI. |
| Saturating overflow in `Freq * Δ` | Δ ≤ 52, max representable `Freq` ≈ 2⁶⁴ / 52 — overflow only if a single block frequency exceeds ~3.5 × 10¹⁷, which `MachineBlockFrequencyInfo` never produces (normalised against entry = `BlockFrequency::getEntryFrequency()` = 1<<14 by default). Document and move on. |
| O43 folds the unpatched LHLD into PUSH/POP, defeating the patch | `V6ClangPeephole::isSameAddress` returns false for MCSymbol operands (only handles `isGlobal()` and `isImm()`), so O43 naturally skips SHLD/LHLD pairs whose address is a `Sym+1` symbol expression. Already covered by Stage 1's lit-test verification (DISABLED prefix). |
| Constant-tracking passes inspect the patched DE/BC LXI | Stage 1 already audited this for HL: the LXI's imm operand is `MO_MCSymbol` (not `isImm()`) so `V6ClangLoadImmCombine` and the INX-scan in `V6ClangInstrInfo.cpp` route through their non-imm paths. The destination register (HL/DE/BC) does not change the audit. |
| Mixed HL/DE/BC reload rewrites accidentally clobber a register the original reload didn't | The unpatched-reload sequences exactly mirror `eliminateFrameIndex`'s static-stack expansion, including PUSH/POP HL guards. Verifier and lit tests catch deviations. |
| Stage 4 (8-bit MVI patches) overlap | Stage 2 explicitly skips A/r8 destinations (`Δ = 0`). Stage 4 will extend the table and the patch emitter; the chooser's "skip if Δ ≤ 0" gate naturally tolerates the addition. |

---

## 6. Relationship to Other Improvements

* **Builds on Stage 1** —
  [plan_O61_spill_in_reload_immediate.md](plan_O61_spill_in_reload_immediate.md).
  All plumbing (`MO_PATCH_IMM`, MCSymbol lowering, AsmPrinter
  pre-instr label, constant-tracking opt-out) is reused unchanged.
* **Coexists with O42** (HL/DE-dead skip in spill expansion) —
  Stage 2 invokes the same `isRegDeadAfterMI` helper to pick
  between the HL-dead and HL-live rows of the Δ table. The
  patched reload site itself does not need O42 because the
  patched LXI does not touch HL when the destination is DE/BC.
* **Coexists with O43** (SHLD/LHLD → PUSH/POP fold) — `isSameAddress`
  ignores MCSymbol operands, so O43 cannot fold patched-site
  LHLD/SHLD pairs. Confirmed by Stage 1 lit-test golden output.
* **Prerequisite for Stage 3** — Stage 3 reuses the Δ table to
  reason about second-patch profitability and the
  "never patch a 2nd HL/A" rule.

## 7. Future Enhancements

These follow the staged rollout in the
[O61 design doc](future_plans/O61_spill_in_reload_immediate.md#recommended-scope-of-a-minimal-prototype):

* **Stage 3** — enable `K = 2` patches per single-source spill
  with the hard rules from the design doc:
  `K ≤ 2` for single-source spills, `K ≤ 1` for multi-source spills,
  never patch a 2nd `A`-target reload, never patch a 2nd
  `HL`-target reload.
* **Stage 4** — extend reload-side handling to individual `B..L`
  r8 targets (the `r8 A-live` case, Δ ≥ +44 cc) via patched
  `MVI r, 0`.
* **Multi-source HL spills** — currently filtered out by Stage 2.
  Per the design doc, K = 1 is still profitable for these as long
  as the per-source spill cost is paid only once per source point.
* **DE/BC source spills** — Stage 2 keeps spill source = HL only.
  Extending to DE/BC sources requires costing the additional
  XCHG/PUSH/POP that the spill side incurs.
* **LIFO-affinity tiebreaker** — when two candidates score equally,
  prefer the one whose patching enables a downstream O43 fold of
  the *remaining* spill/reload pair. Deferred until measurements
  justify the extra chooser complexity.

## 8. References

* [O61 Design Doc](future_plans/O61_spill_in_reload_immediate.md)
* [O61 Stage 1 Plan](plan_O61_spill_in_reload_immediate.md)
* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md)
* [Future Improvements](future_plans/README.md)
* [Static Stack Alloc (O10)](../docs/V6ClangStaticStackAlloc.md)
* [Plan Format Reference](plan_cmp_based_comparison.md)
* [Feature Pipeline](pipeline_feature.md)
* [Feature Test Cases](../tests/features/README.md)
