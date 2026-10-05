# Plan: O61 — Spill Into the Reload's Immediate Operand (Stage 3)

> **Scope of this plan.** This plan implements **Stage 3** of the staged
> rollout described in
> [O61_spill_in_reload_immediate.md](future_plans/O61_spill_in_reload_immediate.md#recommended-scope-of-a-minimal-prototype):
>
> * Raise the patched-reload cap from **K ≤ 1 (Stage 2)** to **K ≤ 2**
>   for **single-source** spills.
> * Keep **K ≤ 1** for **multi-source** spills (≥ 2 `V6CLANG_SPILL16` at
>   distinct program points writing the same FI).
> * When selecting the 2nd patch, the chooser must **skip `HL`-target
>   reload candidates** (the 2nd-patch Δ is −12 cc — a net loss), and
>   implicitly skip `A`-target candidates (Δ = 0 in the Stage 2 table,
>   Stage 4 territory).
> * Spill source remains `HL` (i.e. `V6CLANG_SPILL16` with src = HL). Any
>   non-HL spill keeps the classical slot path (deferred).
> * Patched reload targets stay in `{HL, DE, BC}`. A/r8 patched reloads
>   are Stage 4.

Stage 1 shipped end-to-end plumbing:
[plan_O61_spill_in_reload_immediate.md](plan_O61_spill_in_reload_immediate.md).
Stage 2 shipped the Δ table, the `BFreq × Δ` chooser, and the
DE/BC patched-reload emitter behind single-source, K ≤ 1:
[plan_O61_spill_in_reload_immediate_stage2.md](plan_O61_spill_in_reload_immediate_stage2.md).
Stage 3 is a **filter relaxation plus a second-patch chooser**
extension to the existing `V6ClangSpillPatchedReload` pass; no new
infrastructure is required.

## 1. Problem

### Current behavior

Stage 2's filter only accepts spill slots with **exactly one**
`V6CLANG_SPILL16` source (`E.Spills.size() != 1` is rejected), and the
chooser never considers patching more than one reload per slot
(`K ≤ 1` is hard-wired via a single-winner scan).

Two categories of spill slots in real code are therefore left on the
classical BSS path even though the cost model predicts a win:

1. **Multi-source HL spills.** Slots with ≥ 2 `V6CLANG_SPILL16` writing
   the same FI (typical for vregs defined on diverging paths that
   join) are skipped outright. The Stage 2 feature test
   [tests/features/35/v6clang.c](../tests/features/35/v6clang.c)
   shows exactly this: `mixed_hl_de` and `main` both have two
   SHLDs into the same slot and Stage 2 correctly rejects them
   ("Stage 2 skipped: multi-source" in
   [tests/features/35/result.txt](../tests/features/35/result.txt)).
   A K = 1 patch of the hot reload would still win — spill cost
   just doubles (two SHLDs to `Sym+1` instead of one), and that
   cost is already present in the classical baseline (two SHLDs
   to the BSS slot).
2. **Single-source spills with ≥ 2 non-HL reloads.** Stage 2 picks
   only the highest-scoring reload and leaves the rest as
   classical loads from `Sym+1`. If a second reload targets `DE`
   or `BC`, adding a second patch pays one extra spill but wins
   on the reload side (Δ_2 = +4..+12 cc for DE, +4 cc for BC per
   the design doc's
   [second-patch table](future_plans/O61_spill_in_reload_immediate.md#patching-decisions-are-not-independent)).

### Desired behavior

For every static-stack-eligible function, for every spill slot whose
sources are all `V6CLANG_SPILL16` with src = `HL`:

1. Compute Δ × BFreq for each reload (same table as Stage 2).
2. Pick the **single** highest-scoring reload as the first winner
   (same as Stage 2).
3. **If single-source (`E.Spills.size() == 1`)**, try to pick a
   second winner among the remaining reloads, subject to:
   * dst ∈ `{DE, BC}` (HL forbidden: 2nd-patch Δ = −12 cc,
     A forbidden: deferred to Stage 4 and Δ = 0 here),
   * Δ > 0 (via `deltaForReload`),
   * highest `BFreq × Δ` among eligible candidates.
   If none eligible, fall back to K = 1.
4. **If multi-source (`E.Spills.size() > 1`)**, cap at K = 1 and
   emit all sources as `SHLD Sym+1`.
5. For each winner (1 or 2), materialise a distinct `.Lo61_N` label
   and rewrite the winning reload as `LXI <DstRP>, 0` with
   `MO_PATCH_IMM` on the imm operand.
6. Rewrite **every** original spill of the slot as a *sequence* of
   SHLDs — one `SHLD SymI+1` per winner. Single-source K = 1 emits
   one SHLD (identical to Stage 2); single-source K = 2 emits two
   SHLDs in program order at the single spill site; multi-source
   K = 1 emits one SHLD at each of the N source points.
7. Every non-winner reload becomes the classical reload sequence
   for its dst (same emitter as Stage 2), reading from `Sym1+1`
   (the first patched site's imm bytes serve as the data slot).

### Root cause

Stage 2 hard-coded two invariants to keep the prototype small:
`E.Spills.size() != 1` rejects multi-source slots, and
`HaveWinner ? score > BestScore` picks only one winner. Neither
invariant is demanded by the design; both were deferred to Stage 3
per the
[staged rollout](future_plans/O61_spill_in_reload_immediate.md#recommended-scope-of-a-minimal-prototype).
The design doc already spells out the second-patch cost and the
multi-source cap — Stage 3 wires them into the chooser and the
rewrite emitter.

---

## 2. Strategy

### Approach: extend `V6ClangSpillPatchedReload` with a 2nd-patch chooser and a multi-source-aware spill emitter

All Stage 1/2 infrastructure stays:

* `MO_PATCH_IMM` target flag (V6ClangInstrInfo.h, lowered in
  `V6ClangMCInstLower.cpp` as `Sym + 1`).
* Pre-instr label on the patched `LXI` (AsmPrinter emits it).
* Constant-tracking opt-out (LoadImmCombine, AccumulatorPlanning)
  already routes through the non-imm path when the imm is an
  `MCSymbol`.
* O43 `isSameAddress` already ignores MCSymbol operands, so the
  SHLD/LHLD → PUSH/POP fold leaves patched sites alone.

Stage 3 changes inside
`V6ClangSpillPatchedReload::runOnMachineFunction`:

1. **Filter relaxation.** Accept `E.Spills.size() >= 1` provided
   every spill source is HL. Reject otherwise.
2. **Chooser refactor.** Replace the single-winner loop with a
   helper `pickBestReload(Reloads, Excluded, RestrictTo)` that
   scans reloads (skipping those in `Excluded`) and returns the
   highest-scoring index whose dst is in `RestrictTo` and whose
   Δ > 0. Call it once with `RestrictTo = {HL,DE,BC}` to pick the
   first winner. If single-source and the first pick succeeded,
   call it again with `RestrictTo = {DE,BC}` (HL explicitly
   excluded — the 2nd-patch Δ = −12 cc rule) and
   `Excluded = {firstWinner}`.
3. **Syms array.** Replace the single `MCSymbol *Sym` with
   `SmallVector<MCSymbol *, 2> Syms` holding one symbol per winner.
4. **Spill rewrite.** For each original spill in `E.Spills`, emit
   `SHLD <Syms[i]+1>` for every `i ∈ [0, Syms.size())`, preserving
   the kill flag only on the last emitted SHLD (the value is
   dead after all stores). Then erase the original pseudo. This
   uniformly handles all three cases: single-source K=1 (1
   SHLD), single-source K=2 (2 SHLDs from the single spill
   point), multi-source K=1 (N SHLDs total, one per source).
5. **Patch winners.** Loop over `Winners` and emit
   `LXI <DstReg[i]>, 0` with `setPreInstrSymbol(MF, Syms[i])` and
   `MO_PATCH_IMM` on the imm operand. Erase the original reload
   pseudo.
6. **Unpatched reloads.** Same emitter as Stage 2, pointing at
   `Syms[0]` (arbitrary choice — any patched site's imm bytes
   are equally valid slot storage; picking the first keeps the
   assembly deterministic and matches the K = 1 behaviour).

### Why this works

1. **Plumbing is unchanged.** The same `MO_PATCH_IMM` lowering,
   the same `setPreInstrSymbol` wiring, the same constant-tracking
   opt-out — all reused.
2. **Correctness of K = 2 patched sites.** Every SHLD writes the
   imm bytes of both LXIs, so whichever LXI executes materialises
   the most recent spilled value. Because the static-stack guard
   (`hasStaticStack`) already forbids recursion and interrupt
   reachability, no concurrent execution path can observe a
   partial write.
3. **Correctness of multi-source K = 1.** Each source's SHLD
   writes the same `Sym+1` bytes. The RA-level invariant that
   each reload has a dominating spill on every reaching path
   still holds — the patched LXI just reads whichever spill
   most recently executed, same as a classical BSS slot.
4. **Cost model parity with the design doc.** The 2nd-patch
   chooser enforces exactly the two hard rules from the design
   doc's
   [Patching decisions are not independent](future_plans/O61_spill_in_reload_immediate.md#patching-decisions-are-not-independent)
   section: *never patch a 2nd `HL`-target reload* (skipped by
   `RestrictTo`), *never patch a 2nd `A`-target reload* (implicit
   via Stage 2's Δ = 0 for A), and `K ≤ 2` / `K ≤ 1`
   (multi-source) caps via the if-branch on `E.Spills.size()`.
5. **`MCSymbol` per winner is free.** `createTempSymbol` already
   allocates unique `.Lo61_N` labels; Stage 3 just calls it
   twice when K = 2.
6. **Kill-flag preservation.** For K = 2, the single HL source is
   live across both SHLDs; only the last SHLD can kill HL. This
   mirrors the existing post-RA expansion pattern where a
   sequence of uses of the same physical reg moves the kill flag
   to the last use.

### Why not split the chooser into its own file

Three reasons to keep the chooser inline in
`V6ClangSpillPatchedReload.cpp`:

* The chooser is ~30 lines, trivially self-contained, and only
  called from one site.
* Unit testing the chooser in isolation is not ergonomic in
  LLVM's gtest harness (it would need a mock `MachineInstr`
  and `MBFI`). Lit-test coverage through the driver is enough.
* The 2nd-patch exclusion list (`HL` today, maybe `A` in Stage 4
  plus any future constraints) lives next to `deltaForReload` —
  keeping both helpers together makes the cost-model surface
  obvious.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Relax spill-count filter | `E.Spills.size() >= 1 && all_of(Spills, isHLSrc)` (was: `size() == 1`) | `V6ClangSpillPatchedReload::runOnMachineFunction` |
| Extract chooser helper | `pickBestReload(Reloads, Excluded, AllowHL)` — returns index or `-1` | same file |
| Pick 2nd winner when eligible | Call helper with `AllowHL=false, Excluded={winner1}` iff single-source and K=1 succeeded | same |
| `Syms` vector | `SmallVector<MCSymbol *, 2>`, one per winner | same |
| Spill emitter | For each spill, emit N SHLDs (one per Sym); kill flag only on last | same |
| Winner patch emitter | Loop over `Winners`, build `LXI <DstReg[i]>, 0` with `Syms[i]` label | same |
| Unpatched reload emitter | Unchanged; reads from `Syms[0]` | same |
| Lit test — K=2 single-source DE+DE | Two DE reloads, both patched | new `spill-patched-reload-k2.ll` |
| Lit test — K=2 single-source DE+BC | Mixed DE+BC reloads, both patched | same |
| Lit test — K=2 blocked by HL 2nd | HL + DE reloads; only DE patched (HL skipped as 2nd) | same |
| Lit test — multi-source K=1 | 2 HL spills, 1 DE reload | same |
| Feature test | `tests/features/36/` — multi-source + K=2 scenarios | `tests/features/36/` |
| Lit test — Stage 2 regression | Existing `spill-patched-reload-de-bc.ll` must still pass (K=1 single-source single-reload case degenerates to Stage 2 output) | existing |

No new CLI flag — `-mv6clang-spill-patched-reload` continues to gate
the pass; Stage 3 just expands what the gated pass does.

---

## 3. Implementation Steps

### Step 3.1 — Extract `pickBestReload` helper [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangSpillPatchedReload.cpp`

Anonymous-namespace helper that encapsulates the chooser scan used
for both the 1st and 2nd winner picks. Signature:

```cpp
// Return the index of the best-scoring reload in `Reloads`, or -1
// if none is eligible. A candidate is eligible iff:
//   * its index is not in `Excluded`,
//   * its dst is HL and AllowHL is true, or its dst is DE/BC,
//   * deltaForReload(dst, HLLive) > 0.
// Score = MBFI.getBlockFreq(MBB).getFrequency() * Delta.
static int pickBestReload(ArrayRef<MachineInstr *> Reloads,
                          ArrayRef<int> Excluded, bool AllowHL,
                          const MachineBlockFrequencyInfo &MBFI,
                          const TargetRegisterInfo *TRI);
```

Replace the existing inline chooser loop with two calls:

```cpp
int W1 = pickBestReload(E.Reloads, /*Excluded=*/{}, /*AllowHL=*/true,
                        MBFI, TRI);
if (W1 < 0) continue;

SmallVector<int, 2> Winners = {W1};
if (E.Spills.size() == 1) {
  int W2 = pickBestReload(E.Reloads, /*Excluded=*/{W1},
                          /*AllowHL=*/false, MBFI, TRI);
  if (W2 >= 0)
    Winners.push_back(W2);
}
```

> **Design Note**: `AllowHL=false` bakes the 2nd-patch skip rule
> into the chooser surface. If Stage 4 later needs to skip A for
> 2nd patches as well, add an `AllowA` parameter in the same shape.

> **Implementation Notes**:

### Step 3.2 — Allocate one Sym per winner [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangSpillPatchedReload.cpp`

Replace the single-symbol allocation with:

```cpp
SmallVector<MCSymbol *, 2> Syms;
for (size_t i = 0; i < Winners.size(); ++i)
  Syms.push_back(MF.getContext().createTempSymbol(
      "Lo61_", /*AlwaysAddSuffix=*/true));
```

> **Implementation Notes**:

### Step 3.3 — Rewrite spills to write every Sym [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangSpillPatchedReload.cpp`

Replace the single `SHLD Sym+1` rewrite with a loop that handles
K = 1 and K = 2 uniformly and preserves the kill flag only on the
last emitted SHLD:

```cpp
for (MachineInstr *Spill : E.Spills) {
  MachineBasicBlock *MBB = Spill->getParent();
  DebugLoc DL = Spill->getDebugLoc();
  bool IsKill = Spill->getOperand(0).isKill();
  for (size_t si = 0; si < Syms.size(); ++si) {
    bool Kill = IsKill && (si + 1 == Syms.size());
    BuildMI(*MBB, Spill, DL, TII.get(V6CLANG::SHLD))
        .addReg(V6CLANG::HL, getKillRegState(Kill))
        .addSym(Syms[si], V6ClangII::MO_PATCH_IMM);
  }
  Spill->eraseFromParent();
}
```

> **Design Note**: For K = 2, the two SHLDs are emitted in
> ascending `Syms` order at each source point. Program order is
> irrelevant — the two patched sites hold the same bytes after
> both SHLDs commit.

> **Implementation Notes**:

### Step 3.4 — Patch each winner [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangSpillPatchedReload.cpp`

Replace the single winner rewrite with a loop:

```cpp
for (size_t wi = 0; wi < Winners.size(); ++wi) {
  MachineInstr *PR = E.Reloads[Winners[wi]];
  MachineBasicBlock *MBB = PR->getParent();
  DebugLoc DL = PR->getDebugLoc();
  Register Dst = PR->getOperand(0).getReg();
  MachineInstrBuilder NewLxi =
      BuildMI(*MBB, PR, DL, TII.get(V6CLANG::LXI))
          .addReg(Dst, RegState::Define)
          .addImm(0);
  NewLxi->getOperand(1).setTargetFlags(V6ClangII::MO_PATCH_IMM);
  NewLxi->setPreInstrSymbol(MF, Syms[wi]);
  PR->eraseFromParent();
}
```

> **Implementation Notes**:

### Step 3.5 — Unpatched reload emitter reads from Syms[0] [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangSpillPatchedReload.cpp`

Replace the Stage 2 single-Sym capture with a reference to
`Syms[0]` in the unpatched-reload emitter. Also change the
"skip if i == WinnerIdx" check to "skip if i is in Winners":

```cpp
auto isWinner = [&](size_t i) {
  return llvm::is_contained(Winners, (int)i);
};
for (size_t i = 0, n = E.Reloads.size(); i < n; ++i) {
  if (isWinner(i)) continue;
  // ... existing classical-reload emitter, using Syms[0] ...
}
```

> **Design Note**: Using `Syms[0]` for every unpatched reload is
> a deliberate simplification — the cost-model difference between
> reading from `Syms[0]+1` vs `Syms[1]+1` is zero (both are `LHLD
> addr`, 20cc). Splitting routing by proximity would only matter
> for very rare layout-sensitive cases and is out of scope.

> **Implementation Notes**:

### Step 3.6 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**:

### Step 3.7 — Lit test: K=2 and multi-source [x]

**File**:
`llvm-project/llvm/test/CodeGen/V6Clang/spill-patched-reload-k2.ll`
(new)

Three cases:

1. **Single-source K=2 (DE + DE)**: one HL spill, two DE reloads —
   expect two `.Lo61_N` labels each preceded by `SHLD .Lo61_N+1`
   and followed by `LXI DE, 0`.
2. **HL 2nd patch blocked**: one HL spill, one DE reload, one HL
   reload. Expect the DE reload patched (1st pick — higher Δ than
   HL), and the HL reload left as classical `LHLD .Lo61_0+1`
   (2nd pick skipped because HL dst is forbidden).
3. **Multi-source K=1**: two HL spills (diverging-path defs), one
   DE reload. Expect both spills rewritten to `SHLD .Lo61_0+1`
   and the DE reload rewritten to `LXI DE, 0`.

> **Design Note**: Stage 2's DE+BC lit test already covers the
> K=1 single-source fallback, so Stage 3 only needs to add the
> new-coverage cases above.

> **Implementation Notes**:

### Step 3.8 — Lit test: Stage 1/2 regression [x]

Re-run `spill-patched-reload-hl.ll` and
`spill-patched-reload-de-bc.ll`. Stage 3 must keep both passing
byte-identically (both test the K=1 code path which degenerates
from Stage 3's K=2 chooser whenever the 2nd pick yields no
eligible candidate).

> **Implementation Notes**:

### Step 3.9 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**:

### Step 3.10 — Verification assembly steps from `tests\features\README.md` [x]

Test folder `tests/features/36/` (created in Phase 1). Compile
`v6clang.c` with
`-mllvm -mv6clang-spill-patched-reload -mllvm -v6clang-disable-shld-lhld-fold`
into `v6clang_new01.asm`. Verify that multi-source and K=2
patching fires where Stage 2 left the classical path in place.
Iterate `_new02.asm`, `_new03.asm` … as needed.

> **Implementation Notes**:

### Step 3.11 — Make sure result.txt is created (`tests\features\README.md`) [x]

Per the test folder template: C source, c8080 reference body,
c8080 stats, v6clang Stage 2 baseline, v6clang Stage 3 asm,
v6clang stats, per-slot impact table for the K=2 / multi-source
scenarios, and the chooser log (which reload picked as 1st vs 2nd
and why).

> **Implementation Notes**:

### Step 3.12 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**:

---

## 4. Expected Results

### Example 1 — `arr_sum`-style single-source K=2 (DE + BC)

Spill source HL, three reloads: one HL, one DE, one BC. All in
the same block (or same inner loop).

**Stage 2**: picks the BC reload (Δ = +24 vs DE +12 vs HL +8).
Emits K=1. Remaining HL and DE reloads become classical loads
from `.Lo61_0+1` via LHLD / LHLD;XCHG respectively.

**Stage 3**: after the BC 1st pick, the chooser scans with
`AllowHL=false` and finds DE (Δ = +12). Emits K=2:

```
; spill:
  SHLD .Lo61_0+1     ; 20cc
  SHLD .Lo61_1+1     ; 20cc
...
; 1st patched reload (BC):
.Lo61_0:
  LXI  BC, 0         ; 12cc (patched -- was LHLD; MOV C,L; MOV B,H = 36cc)
...
; 2nd patched reload (DE):
.Lo61_1:
  LXI  DE, 0         ; 12cc (patched -- was LHLD; XCHG = 24cc)
...
; unpatched HL reload:
  LHLD .Lo61_0+1     ; 20cc  (unchanged from Stage 2)
```

**Net vs Stage 2 on that slot**: classical DE reload cost 24 cc →
patched 12 cc = **−12 cc**, plus one extra SHLD (+20 cc) = **net
−4 cc, +0 B** (gains scale with loop trip count; outside a loop
Stage 3 is break-even on this shape by design — the chooser only
fires when Δ > 0). Inside a loop with trip count ≥ 2 the savings
compound.

### Example 2 — multi-source K=1

`mixed_hl_de` from
[tests/features/35/v6clang.c](../tests/features/35/v6clang.c):
two HL spills of the same vreg on diverging paths, one DE reload.

**Stage 2**: rejected (multi-source filter). Classical BSS slot,
two SHLDs + one `XCHG;LHLD;XCHG` reload = 20+20+28 = **68 cc**,
2 B BSS.

**Stage 3**: multi-source K=1 allowed. Two SHLDs to `.Lo61_0+1`
(20+20 = 40 cc), one patched `LXI DE, 0` (12 cc) = **52 cc**,
0 B BSS. **Δ = −16 cc, −2 B BSS**.

### Example 3 — HL 2nd pick blocked

Single HL spill, three reloads: DE, HL, HL.

**Stage 2**: picks DE (Δ = +12), leaves both HL reloads classical.

**Stage 3**: first pick = DE. Second pick with `AllowHL=false`
scans the two HL reloads — both skipped. Falls back to K=1 —
output is byte-identical to Stage 2 on this shape. This is the
no-regression case: the `AllowHL=false` guard prevents Stage 3
from making a net-negative second patch.

### Example 4 — Stage 2 byte identity

Any test case from Stage 2 that picks K=1 and finds no eligible
2nd candidate (DE/BC). Stage 3 must emit byte-identical assembly.
Covered by re-running `spill-patched-reload-de-bc.ll` and the
Stage 1 `spill-patched-reload-hl.ll` test.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Duplicate kill-flag placement confuses `livePhysRegs` / verifier | Emit the kill flag only on the last SHLD (standard convention for a sequence of uses of the same physreg); `-verify-machineinstrs` in the lit tests catches deviations. |
| Two `setPreInstrSymbol` calls collide if the underlying map rejects duplicates | Each winner is a distinct `MachineInstr`; each gets its own unique `.Lo61_N` symbol. No collision possible. |
| Multi-source spill writes interleave with a reload between them | The patched LXI always reads the most recent bytes; interleaving is not a correctness issue — RA guarantees each reload is dominated by a spill on every reaching path, and all spills write identical bytes. Semantics match a classical BSS slot. |
| K=2 picks a 2nd reload in a cold block, losing on aggregate | The chooser multiplies by `BlockFrequency`, so a cold candidate scores near zero and only wins when no hot candidate exists. Δ > 0 guard also prevents the degenerate case where the 2nd pick is net negative on its own. |
| `Syms[0]` vs `Syms[1]` layout skew breaks linker relocations | MCSymbol operands lower via `MO_PATCH_IMM → Sym+1` in `V6ClangMCInstLower.cpp`; both symbols use the same lowering path. No relocation-layout sensitivity. |
| Second-patch rule gets stale as Stage 4 lands | `AllowHL=false` is the current one-flag encoding; Stage 4 can add `AllowA=false` without reworking the chooser surface. The Δ table remains the single source of truth. |
| Chooser tie between two reloads in the same block | Program-order-first wins (the scan preserves insertion order into `E.Reloads`), matching Stage 2's tiebreaker. Deterministic. |
| `MachineBlockFrequencyInfo` missing on functions with `cold` attribute oddities | Already handled in Stage 2 — `MBFI` always returns *some* frequency; ordering is what matters. |
| O43 folds the spill SHLDs back into PUSH/POP, defeating the patch | `V6ClangPeephole::isSameAddress` returns false for MCSymbol operands, so adjacent `SHLD .Lo61_0+1`/`SHLD .Lo61_1+1` pairs are not foldable. Confirmed already by Stage 1's DISABLED prefix test. |

---

## 6. Relationship to Other Improvements

* **Builds on Stage 2** —
  [plan_O61_spill_in_reload_immediate_stage2.md](plan_O61_spill_in_reload_immediate_stage2.md).
  Δ table, `BFreq × Δ` chooser, DE/BC patched-reload emitter,
  and unpatched-reload classical sequences are all reused
  unchanged.
* **Coexists with O42** (HL/DE-dead skip in spill expansion) —
  Stage 3 invokes the same `isRegDeadAfterMI` helper to pick
  between HL-dead and HL-live rows of the Δ table when scoring
  each reload.
* **Coexists with O43** (SHLD/LHLD → PUSH/POP fold) —
  `isSameAddress` ignores MCSymbol operands, so O43 cannot fold
  SHLDs whose address is a `Sym+1` symbol expression. Confirmed
  by Stage 1's lit-test golden output.
* **Prerequisite for Stage 4** — Stage 4 extends the Δ table to
  `A` and `r8` reload dsts (`MVI`-shaped patches). The chooser's
  `RestrictTo` / `AllowHL` knobs generalise to `AllowA` for the
  2nd-patch skip rule; `deltaForReload` gains new rows.

---

## 7. Future Enhancements

* **Multi-source K = 2.** Allowed by the design doc's cost model
  only if spill cost × source-count × (K − 1) is recouped by
  reload-side savings — rare enough to defer. Stage 5 candidate.
* **Non-HL spill sources.** Patched DE/BC spills would require an
  `MOV r,H`/`MOV r,L` byte-at-a-time path to split an 8-bit value
  into two `MVI`-slot imms. The cost model rules it out for most
  shapes; infrastructure-ready only if a measured benchmark shows
  demand.
* **LIFO-affinity tiebreaker.** The design doc mentions preferring
  patched sites that leave the remaining spill/reload pair in
  PUSH/POP-foldable shape. Add once measurements justify chooser
  complexity.
* **Spill-cost-aware chooser.** Currently the chooser ignores
  spill cost (constant per decision for K=1; linear in K for K≥2).
  For K=2 a more honest formulation would subtract one extra
  spill's frequency-weighted cost from the 2nd candidate's score,
  not just gate on Δ > 0. Measured effect is small for current
  workloads; revisit with real data.

---

## 8. References

* [O61 design doc](future_plans/O61_spill_in_reload_immediate.md) — the canonical cost model and staging plan.
* [Stage 2 plan](plan_O61_spill_in_reload_immediate_stage2.md) — the immediate predecessor, Δ table and chooser infrastructure.
* [Stage 1 plan](plan_O61_spill_in_reload_immediate.md) — end-to-end plumbing (`MO_PATCH_IMM`, MCSymbol lowering, AsmPrinter, constant-tracking opt-out).
* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md) — build commands and mirror sync procedure.
* [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md) — canonical instruction cycle costs used in the Δ table.
* [Feature Test Cases](../tests/features/README.md) — test folder structure and verification steps.
* [Future Optimizations](future_plans/README.md) — feature backlog.
