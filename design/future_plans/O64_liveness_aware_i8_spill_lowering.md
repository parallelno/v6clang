# O64 — Liveness-Aware i8 Spill/Reload Lowering (Static-Stack Shapes B & C)

**Source:** V6CLANG
**Savings:** 8–28 cc per i8 spill/reload site, depending on the live
          state of HL, A, and spare GPRs. Pure win over the current
          pessimistic `[PUSH HL] ... [POP HL]` and DE-detour shapes.
**Frequency:** Very high — every i8 RA spill on a static-stack function
          whose source/dest is not A.
**Complexity:** Low-Medium
**Risk:** Low. Every new shape is functionally equivalent to the
          existing one; selection is a pure cost-model decision driven
          by post-RA liveness queries already used by O42.
**Dependencies:** O10 (static stack) done; O42 (liveness-aware
          expansion) done — reuses `isRegDeadAfterMI` infrastructure.
          Independent of O61 (Approach A splits by mode, not by shape).
**Status:** [ ] not started.


## Problem

`V6ClangRegisterInfo::eliminateFrameIndex` (static-stack branch, lines
~143–250) lowers `V6CLANG_SPILL8` / `V6CLANG_RELOAD8` using only **one**
secondary strategy when the data register is not A: route through HL.
Routing through HL has to be protected whenever HL is live across the
site, producing a `PUSH HL` / `POP HL` wrap. That wrap is expensive.

Current Shape B (src/dst ∈ {B,C,D,E}):

```
SPILL8  r:   [PUSH HL]; LXI HL, addr; MOV M, r; [POP HL]
RELOAD8 r:   [PUSH HL]; LXI HL, addr; MOV r, M; [POP HL]
```

Current Shape C (src/dst ∈ {H,L}):

```
SPILL8  H/L: [PUSH DE]; MOV D,H; MOV E,L; LXI HL, addr; MOV M,D;
             MOV H,D; MOV L,E; [POP DE]
RELOAD8 H:   [PUSH DE]; MOV D,L;          LXI HL, addr; MOV H,M; MOV L,D; [POP DE]
RELOAD8 L:   [PUSH DE]; MOV D,H;          LXI HL, addr; MOV L,M; MOV H,D; [POP DE]
```

Both shapes ignore the fact that, on the i8080, there are *other* ways
to move a byte to/from an absolute address:

* **`STA addr` / `LDA addr`** — 16cc, 1-byte absolute store/load, but
  only through `A`. Cheap when A is free.
* **`MOV r, r'`** — 8cc, 1B. Moving a byte into or out of A takes one
  of these.

These alternatives let us **skip the HL pointer entirely** whenever A
is dead (or cheaply freed up), eliminating the PUSH/POP HL wrap.


## Proposed solution

Turn each of `V6CLANG_SPILL8` / `V6CLANG_RELOAD8` expansions into a small
**cost-model decision list** driven by `isRegDeadAfterMI` queries
against HL, A, and the set of GPRs (B, C, D, E). Pick the cheapest
shape at lowering time. No IR-level changes; no TableGen changes.

Shape A (src/dst == A) is already optimal (`STA` / `LDA`, 16cc / 3B) —
no change.

### Spill path, src ∈ {B, C, D, E}

| # | Precondition                                   | Sequence                                          | Approx cost |
|---|------------------------------------------------|---------------------------------------------------|-------------|
| 1 | HL dead                                        | `LXI HL, addr; MOV M, r`                          | 20 cc, 4 B  |
| 2 | HL live, A dead                                | `MOV A, r; STA addr`                              | 24 cc, 4 B  |
| 3 | HL live, A live, one spare GPR `Tmp` dead      | `MOV Tmp, A; MOV A, r; STA addr; MOV A, Tmp`     | 40 cc, 6 B  |
| 4 | HL live, A live, no spare GPR dead             | `PUSH HL; LXI HL, addr; MOV M, r; POP HL`         | 48 cc, 6 B  |

### Reload path, dst ∈ {B, C, D, E}

| # | Precondition                                   | Sequence                                          | Approx cost |
|---|------------------------------------------------|---------------------------------------------------|-------------|
| 1 | HL dead                                        | `LXI HL, addr; MOV r, M`                          | 20 cc, 4 B  |
| 2 | HL live, A dead                                | `LDA addr; MOV r, A`                              | 24 cc, 4 B  |
| 3 | HL live, A live, one spare GPR `Tmp` dead      | `MOV Tmp, A; LDA addr; MOV r, A; MOV A, Tmp`     | 40 cc, 6 B  |
| 4 | HL live, A live, no spare GPR dead             | `PUSH HL; LXI HL, addr; MOV r, M; POP HL`         | 48 cc, 6 B  |

### Spill path, src ∈ {H, L}

`MOV M, H` / `MOV M, L` via HL is illegal (HL *is* the pointer), so A
becomes the router.

| # | Precondition                                   | Sequence                                          | Approx cost |
|---|------------------------------------------------|---------------------------------------------------|-------------|
| 1 | A dead                                         | `MOV A, H/L; STA addr`                            | 24 cc, 4 B  |
| 2 | A live, one spare GPR `Tmp` dead               | `MOV Tmp, A; MOV A, H/L; STA addr; MOV A, Tmp`   | 40 cc, 6 B  |
| 3 | A live, no spare GPR dead                      | `PUSH PSW; MOV A, H/L; STA addr; POP PSW`         | 52 cc, 5 B  |

### Reload path, dst ∈ {H, L}

Analogous. Note that reloading into H clobbers HL (as pointer), so
the "reload through A" shape avoids having to save L; reloading into
L symmetrically avoids having to save H.

| # | Precondition                                   | Sequence                                          | Approx cost |
|---|------------------------------------------------|---------------------------------------------------|-------------|
| 1 | Other half of HL dead (reload H → L dead; reload L → H dead) | `LXI HL, addr; MOV H/L, M`          | 20 cc, 4 B  |
| 2 | A dead                                         | `LDA addr; MOV H/L, A`                            | 24 cc, 4 B  |
| 3 | A live, one spare GPR `Tmp` dead               | `MOV Tmp, A; LDA addr; MOV H/L, A; MOV A, Tmp`   | 40 cc, 6 B  |
| 4 | A live, no spare GPR dead                      | `PUSH PSW; LDA addr; MOV H/L, A; POP PSW`         | 52 cc, 5 B  |

> **Timing note.** Cycle numbers use the authoritative
> `docs/V6ClangInstructionTimings.md` (cross-checked against
> `docs/Vector_06c_instruction_timings.md`): `MOV r,r` = 8cc,
> `MOV r,M` / `MOV M,r` = 8cc, `LXI` = 12cc, `STA`/`LDA` = 16cc,
> `PUSH` = 16cc, `POP` = 12cc. The *ordering* of the rows (row N is
> strictly cheaper than row N+1 when its precondition holds) is what
> matters for correctness of the decision list.


## Why this works

1. **Liveness is cheap to query post-RA.** O42 already uses
   `isRegDeadAfterMI(Reg, MI, MBB, TRI)` at the spill/reload expansion
   site to decide the `PUSH HL` / `POP HL` gate. Same hook answers
   "is A dead?" and "is any of B,C,D,E dead?".
2. **Every shape is flag-clean** (static stack only, so no `DAD SP`).
   The proposed sequences use `LXI`, `MOV r,r`, `MOV r,M`, `MOV M,r`,
   `STA`, `LDA`, `PUSH`, `POP` — none sets PSW. Composes cleanly with
   O63 (drop `Defs=[FLAGS]`).
3. **The fallback (row 4 / row 3) is the current shape.** Correctness
   regression surface is zero — if preconditions aren't met we emit
   exactly what we emit today.


## Implementation sketch

1. **New shared module** `V6ClangSpillExpand.{h,cpp}` hosts the ladder
   and its helpers (`isRegDeadAfterMI` moved from its two duplicate
   static definitions, plus a new `findDeadSpareGPR8` walking
   `{B, C, D, E}` minus any overlap with an "excluded" register).
   Core entry points:

   ```cpp
   using AppendAddrFn = llvm::function_ref<void(MachineInstrBuilder &)>;

   void expandSpill8Static(MachineInstr &MI,
                           MachineBasicBlock::iterator InsertBefore,
                           Register SrcReg, bool SrcIsKill,
                           const TargetInstrInfo &TII,
                           const TargetRegisterInfo *TRI,
                           AppendAddrFn AppendAddr);

   void expandReload8Static(MachineInstr &MI,
                            MachineBasicBlock::iterator InsertBefore,
                            Register DstReg,
                            const TargetInstrInfo &TII,
                            const TargetRegisterInfo *TRI,
                            AppendAddrFn AppendAddr);
   ```

   `AppendAddrFn` lets the same ladder body serve two callers that
   differ only in the address operand kind: a `GlobalAddress + offset`
   (FI / static-stack form) or an `MCSymbol + MO_PATCH_IMM` (O61
   form). Shape A (`A` src/dst) is trivially handled inline by each
   caller — no need for the helper to know about it.

2. **`V6ClangRegisterInfo::eliminateFrameIndex`**, `V6CLANG_SPILL8` /
   `V6CLANG_RELOAD8` static-stack branch:
   * For `A`, stay inline (`STA` / `LDA`).
   * Otherwise, call the shared helper with an appender that emits
     `addGlobalAddress(GV, StaticOffset)`.
   * For H/L shapes, drop the DE-detour entirely; the ladder produces
     strictly better code in every case (row 2's Tmp pick will prefer
     D or E when both are dead).

3. **`V6ClangSpillPatchedReload`**, non-winner i8 reload loop:
   * For `A`, stay inline (`LDA Sym+1`, unchanged).
   * Otherwise, call the shared `expandReload8Static` with an
     appender that emits `addSym(Syms[0], V6ClangII::MO_PATCH_IMM)`.
   * Winner emission (`MVI r, 0` + pre-instr label) and spill
     rewrite (`STA Sym+1` per winner) are unchanged.

4. **Scheduler note.** All new sequences are fully contained between
   the pseudo's original MI position and its eraseFromParent, so
   scheduling boundaries are unchanged.

5. **Annotation** (optional): when `-mv6clang-annotate-pseudos` is on,
   emit a comment tag showing which row fired — useful for measuring
   row distribution on real code.

### Interaction with O61

O61 rewrites a spill *source* of `A` into `STA .LLo61_N+1` (shape A),
unaffected. The patched *reload* site emits `MVI r, 0` (8 cc, 2 B),
which is *cheaper* than any row here, so O61's patched shape always
wins where it applies. For the non-winner reloads O61 does not
patch, both `V6ClangRegisterInfo::eliminateFrameIndex` and
`V6ClangSpillPatchedReload` call the shared `expandReload8Static` helper,
so those reloads get the same ladder.

### Interaction with O42

O42's "HL dead → skip PUSH/POP" optimisation is subsumed by row 1 of
both ladders. After this change, O42's static-stack i8 code paths can
be deleted (dead code), but leave O42 intact for i16 and for
dynamic-stack paths.

### Interaction with O63

Orthogonal. O63 drops the `FLAGS` def on static-stack pseudos; O64
picks a cheaper expansion. Both touch `eliminateFrameIndex` but in
disjoint lines.


## Savings estimate

Per site, relative to current lowering:

| Current path                     | New best path                              | Δ per site      |
|----------------------------------|--------------------------------------------|-----------------|
| Shape B, HL live, A dead → 48 cc | Row 2 → 24 cc / 4 B                        | **−24 cc, −2 B** |
| Shape B, HL live, A live, spare → 48 cc | Row 3 → 40 cc / 6 B                 | **−8 cc, 0 B**   |
| Shape B, HL live, no spare → 48 cc | Row 4 = current                          | 0 cc, 0 B       |
| Shape B, HL dead → 20 cc (= current row 1) | Row 1 = current                 | 0 cc, 0 B       |
| Shape C (H/L), DE live → 80 cc   | Row 1 / Row 2 → 24–40 cc                   | **−40–−56 cc**   |

On workloads with call-heavy loops (where HL is live into the call
boundary but A is kill-returned), Shape B row 2 is the common case and
saves 24 cc on every reload. Measured expectation on `tests/features/37`
and similar corpora: roughly 2×–3× the Stage 4 per-function wins seen
from O61, because Shape B fires far more often than the pure-A-spill
path O61 targets.


## Testing

1. **Lit tests** under `llvm/test/CodeGen/V6Clang/spill-reload-i8-*.ll`:
   one function per decision row, with `CHECK` lines asserting the
   exact sequence.
2. **Regression** — all existing O42 / O43 / O61 lit tests must still
   pass unmodified (expected output may tighten in a few cases;
   update the CHECK lines to the shorter sequences).
3. **Feature tests** — re-generate every `tests/features/NN/v6clang.asm`
   touching i8 spill/reload and update `result.txt`. Expect strictly
   fewer bytes / cycles in every affected function.


## Risks

* **Spare-GPR selection quality.** Row 3 picks *any* dead GPR. A bad
  pick (e.g. one that's dead locally but frequently used downstream)
  can create minor live-range fragmentation artefacts. Post-RA,
  though, this is just a physical register — no re-allocation risk.
* **Increased i-cache / code size pessimism in row 3.** Row 3 is 6 B
  vs row 4's 6 B — identical bytes, −8 cc. No size regression.
* **Cost-model mis-ordering** if the Vector-06c timings differ
  materially from the numbers used above. Resolve by table-driving
  row selection from `V6ClangInstructionTimings.md`-sourced constants.


## References

* Current lowering —
  `llvm-project/llvm/lib/Target/V6Clang/V6ClangRegisterInfo.cpp` lines ~143–250
  and `V6ClangSpillPatchedReload.cpp` non-winner i8 reload loop
  (lines ~474–534).
* Liveness helper — `isRegDeadAfterMI` (currently duplicated in
  both files above; consolidated into the new `V6ClangSpillExpand.h`).
* Pseudo defs — `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.td`
  (`V6CLANG_SPILL8`, `V6CLANG_RELOAD8`). No changes needed unless O63 lands
  first.
* Timings — `docs/V6ClangInstructionTimings.md`.
* Related design:
  * `design/future_plans/O42_liveness_aware_expansion.md` — prior art
    for HL liveness querying at the expansion site.
  * `design/future_plans/O49_direct_memory_alu_isel.md` — related
    approach that folds the memory access into ALU ops instead of
    into spill/reload.
  * `design/future_plans/O61_spill_in_reload_immediate.md` — A-source
    self-modifying shape; O64 handles everything else.
  * `design/future_plans/O63_split_spill_pseudo_flags.md` — strictly
    orthogonal `Defs=[FLAGS]` cleanup.
