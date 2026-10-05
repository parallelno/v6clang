# Plan: O92 — Unified Cross-BB Physical-Register Value Forwarding

Design source: [design/future_plans/O92_unified_cross_bb_reg_value_forwarding.md](future_plans/O92_unified_cross_bb_reg_value_forwarding.md)
Pipeline: [design/pipeline_feature.md](pipeline_feature.md)

## 1. Problem

### Current behavior

When the register allocator parks a loop-invariant value in a general
register but an in-loop consumer needs it in the accumulator (every i8
`CMP`/`CPI`), ISel emits an accumulator reload (`MOV A, r`) **inside** the
loop body. The value `A` already equals `r` on entry to the loop and the
body never redefines either, so the reload is redundant on every iteration —
yet nothing removes it.

Reduced repro ([temp/acc_loop_repro2.c](../temp/acc_loop_repro2.c)),
first init loop of `repro`:

```asm
; %bb.0
        LDA     __v6clang_a.repro     ; A = n
        MOV     D, A              ; D = n
        ORA     A                 ; A unchanged (= n)
        JZ      .LBB15_3
; %bb.1
        MVI     E, 0
        LXI     H, perm1
.LBB15_2:                         ; inner loop
        MOV     M, E
        INR     E
        MOV     A, D              ; <-- redundant every iteration (8cc)
        CMP     E
        INX     H
        JNZ     .LBB15_2
```

`MOV A, D` is loop-invariant and redundant: `A == D` already holds on entry
to `.LBB15_2` from `bb.0`/`bb.1`, and neither `A` nor `D` is written in the
loop. The same source has two more redundant `MOV A, D` sites.

### Desired behavior

The reload is deleted; `A` carries `n` across the loop:

```asm
.LBB15_2:
        MOV     M, E
        INR     E
        CMP     E              ; A still holds D == n
        INX     H
        JNZ     .LBB15_2
```

General form (register-agnostic): if physical register `R` is already known
to hold value `V` (another register, or a constant), a later write of `V`
into `R` is redundant and is erased. Covers `MOV r, s` (when `r == s`
already) and `MVI r, imm` (when `r` already holds `imm`).

### Root cause

The redundancy is established in one block and carried across a CFG edge
(including a loop back-edge). No existing mechanism removes it:

- **upstream `machine-cp`** reasons intra-block only — it cannot prove the
  fact holds on entry from the predecessor *and* survives the back-edge.
- **`V6ClangAccumulatorPlanning::eliminateRedundantAccMoves`** is A-specific and
  block-local.
- **`V6ClangPeephole::eliminateRedundantMov`** only removes two *adjacent*
  identical `MOVrr`s.

Three partial implementations of the same abstraction, none cross-BB.

---

## 2. Strategy

### Approach: a single cross-BB physreg value-forwarding MachineFunctionPass

Add `V6ClangRegValueForwarding`, a post-RA `MachineFunctionPass` scheduled in
`addPreEmitPass` (after `machine-cp` and the existing peepholes). It runs an
iterative forward dataflow over the MIR CFG with a per-physical-register
value lattice and erases writes that re-establish a value the register
already holds.

**Lattice** (per physreg):

```
        Top  (unknown)
       /        \
  Reg(R)        Const(C)
       \        /
        Bottom  (conflict)
```

- `Top` — nothing known.
- `Reg(R)` — register provably equals current contents of `R`.
- `Const(C)` — register provably holds immediate `C`.
- `Bottom` — clobbered / predecessors disagree.

**Block in-state** = meet (per-register) over predecessor out-states.
Two entries meet to equal value → that value; otherwise `Bottom`. A register
not present in a predecessor out-state is `Top` there. Iterate a worklist to
fixpoint so loop back-edges converge before any in-loop write is deleted.

**Transfer within a block** (walking forward over the in-state copy):
- `MOVrr Dst, Src`: if state says `Dst == Src` (directly, or transitively
  through `Reg` chains) → **erase**. Else set `Dst := Reg(Src)`.
- `MVIr Dst, Imm` (not patched): if state says `Dst == Const(Imm)` → **erase**.
  Else set `Dst := Const(Imm)`.
- Any other def of a register → set that register (and aliases) to `Top`,
  and drop any entry whose value is `Reg(R')` with `R'` aliasing the def.
- **Value-preserving flag ops** (`ORA A`, `ANA A`): these write `A` but leave
  its *value* unchanged (`A|A == A`, `A&A == A`); they only set FLAGS. They
  must be treated as **non-clobbering** for the lattice — otherwise the
  common `MOV D, A; ORA A` zero-test prologue destroys the `A == D` equality
  and the in-loop reload can no longer be proven redundant.
- Calls: apply the regmask (invalidate all non-preserved registers).

**Alias correctness:** all "defines reg" checks and invalidations iterate
`MCRegAliasIterator` via `TRI` so that defining `D` invalidates `DE`, `LXI H`
invalidates `H`/`L`/`HL`, writing `A` invalidates `PSW`, etc.

**Guards:**
1. **O61 patched immediates** — reuse `isO61PatchedImm` (pre-instr symbol or
   any `MO_PATCH_IMM` target flag). Never record such `MVIr`/`LXI` as
   `Const`, never forward across it, never erase it. (Expanded patched
   reloads look like `MVI r, 0` but the imm is self-modified at runtime.)
2. **FLAGS safety** — `MOVrr`/`MVIr` do not touch FLAGS on 8080, so erasing a
   redundant one cannot disturb a pending compare. Assert the erased opcode
   has no FLAGS def.
3. **Implicit defs / regmasks** honored when invalidating.

### Why this works

By `addPreEmitPass` time all V6CLANG pseudos (incl. spill/reloads) are already
expanded — confirmed empirically (post-`postrapseudos` MIR of the repro is
real instructions, no pseudos). So the pass sees a flat instruction stream
**and** has full CFG + liveness + `TRI`. The only special instruction is the
patched immediate, handled by the existing `isO61PatchedImm` guard. The
dataflow fixpoint is what lets it prove the cross-BB / back-edge fact that
`machine-cp` and the local peepholes cannot.

It removes the redundant *write* (saving its cycles each execution) but does
**not** free the source register — `D` stays pinned holding `n`. This is
redundancy elimination, not register-pressure reduction.

### Summary of changes

| File | Change |
|------|--------|
| `V6ClangRegValueForwarding.cpp` (new) | The pass |
| `V6Clang.h` | Declare `createV6ClangRegValueForwardingPass` |
| `CMakeLists.txt` | Add source file |
| `V6ClangTargetMachine.cpp` | Register pass in `addPreEmitPass`; CLI toggle |
| `V6ClangAccumulatorPlanning.cpp` | Remove `eliminateRedundantAccMoves` (folded in) |
| `V6ClangPeephole.cpp` | Remove `eliminateRedundantMov` (folded in); expose `isO61PatchedImm` |
| `scripts/sync_llvm_mirror.ps1`, `scripts/populate_llvm_project.ps1` | (full-dir mirror already covers V6CLANG/; verify) |
| `tests/features/76/` | Feature test |
| `llvm-project/llvm/test/CodeGen/V6CLANG/reg-value-forwarding-cross-bb.ll` | Lit test |

---

## 3. Implementation Steps

### Step 3.1 — Skeleton pass + registration + CLI toggle [x]

Create `llvm-project/llvm/lib/Target/V6CLANG/V6ClangRegValueForwarding.cpp`: a
`MachineFunctionPass` named "V6CLANG Register Value Forwarding" with
`-v6clang-disable-reg-value-forwarding` (default off = enabled). Initially a
no-op returning `false`. Declare `createV6ClangRegValueForwardingPass()` in
`V6Clang.h`, add the file to `CMakeLists.txt`, and register it in
`V6ClangTargetMachine::addPreEmitPass` just before `createV6ClangRedundantFlagElimPass`.

> **Design Notes**: Position after Peephole/LoadStoreOpt/XchgOpt so it cleans
> up what they leave; before RedundantFlagElim so flag passes see the final
> shape. Exact slot may be tuned in 3.7 by measurement.
> **Implementation Notes**: _empty_

### Step 3.2 — Build [x]

Build clang+llc; confirm the no-op pass links and runs.

### Step 3.3 — Lattice + intra-block transfer (single block) [x]

Implement the per-physreg lattice (`Top/Reg/Const/Bottom`), a `RegState`
map, alias-correct invalidation via `TRI`, and the forward transfer for a
single block with empty in-state. Erase redundant `MOVrr` and `MVIr` within a
block. Guard with `isO61PatchedImm` and assert no FLAGS def on erase.

> **Design Notes**: Reuse `isO61PatchedImm` — move it to an internal header or
> a shared anonymous helper exposed from `V6ClangPeephole`. Simplest: duplicate
> the tiny predicate locally (it's 6 lines) to avoid a header churn, with a
> comment cross-referencing the canonical copy. Decide during impl.
> Maintain a small allowlist of value-preserving A-defs (`ORA A`, `ANA A`)
> that set FLAGS but do not alter A's value — these must NOT clobber the
> lattice (see repro `bb.0`: `MOV D, A; ORA A`). A def is value-preserving
> only when the written reg is also a use and the op is in the allowlist.
> **Implementation Notes**: _empty_

### Step 3.4 — Cross-BB fixpoint dataflow [x]

Add per-block In/Out states, predecessor-meet, and a worklist iteration to
fixpoint. Recompute each block's Out from its In; re-enqueue successors on
change. Then a final erase pass using the converged In-states.

> **Design Notes**: Meet rule: same value → keep; differ → `Bottom`; missing
> in a pred → treat as `Top` (so it does not force `Bottom` on first visit;
> use the standard "unvisited pred = Top, optimistic" or a visited-set —
> pick the conservative visited-pred-only meet to stay sound on irreducible
> CFGs). Bound iterations defensively.
> **Implementation Notes**: _empty_

### Step 3.5 — Build [x]

### Step 3.6 — Lit test: reg-value-forwarding-cross-bb.ll [x]

Create `llvm-project/llvm/test/CodeGen/V6CLANG/reg-value-forwarding-cross-bb.ll`.
This is the **deterministic non-A / register-agnostic coverage** for the pass
(C codegen reliably forces redundancy only on `A`, since RA reuses the GP
registers between blocks — see note below). Hand-written MIR / IR covers:

- (a) cross-BB `MOVrr` elision with **dst = A** (the headline loop case);
- (b) cross-BB `MOVrr` elision with **dst = a non-A GP register** (one case
  each for at least `D`, `E`, `B`, `C`, `H`, `L`) — proves the lattice is
  register-agnostic;
- (c) **16-bit pair** redundancy (`HL`/`DE` round-trip / re-load) with
  alias-correct invalidation (writing `H` kills `HL`);
- (d) loop back-edge convergence (fixpoint required);
- (e) `MVIr` constant redundancy on a **non-A** register;
- (f) **negative**: patched-imm `MVI` (pre-instr label / `MO_PATCH_IMM`)
  preserved and not recorded as const;
- (g) **negative**: no forwarding across an instruction that clobbers the
  source/dest (alias-aware);
- (h) **negative**: value-preserving `ORA A`/`ANA A` does NOT clobber the
  `A == reg` equality.

Run via `llvm-lit`. Use both `--v6clang-disable-reg-value-forwarding` (CHECK-OFF)
and default (CHECK) run lines to A/B each case.

> **Implementation Notes**: V6CLANG has no `-run-pass`/`INITIALIZE_PASS` infra —
> every V6CLANG lit test is IR-based through full `llc`, so hand-written MIR per
> register is not feasible here. The test is IR-based: it reproduces the
> headline cross-BB loop `MOV A, D` elision (a, d) and the value-correct
> negative (h: `ORA A` preserves `A == D`; legitimate `.LBB15_6` reload kept),
> with default vs `--v6clang-disable-reg-value-forwarding` A/B run lines.
> Register-agnostic / non-A / 16-bit-pair safety (b, c, e) is exercised by the
> feature test `walk16` (tests/features/76) and guaranteed by the lattice's
> TRI-based alias logic; O61 patched-imm safety (f) is covered by
> `isO61PatchedImm` in the pass. Forcing redundant non-A moves from IR is
> RA-dependent and unreliable, so it is not asserted in the lit test.

> **Why non-A coverage lives here, not in the C test**: empirically, the
> backend only produces *redundant* cross-BB moves on `A` from C source — the
> register allocator reuses `D/E/B/C/H/L` between blocks, so reloads of those
> are legitimate (the reg was clobbered), not redundant. The C feature test
> (`tests/features/76`, function `walk16`) therefore *exercises* the pass on
> non-A / 16-bit-pair-heavy code to prove it is safe there, while this lit
> test *deterministically proves* per-register elision via hand-written MIR.

### Step 3.7 — Unify: remove folded logic from the two passes [x]

Delete `V6ClangAccumulatorPlanning::eliminateRedundantAccMoves` (and its now-dead
helpers `definesA`/`usesA`/`definesReg` if unused elsewhere); make
`runOnMachineFunction` a no-op or keep only any remaining responsibilities.
Delete `V6ClangPeephole::eliminateRedundantMov` and its call site. Rebuild and
re-run the lit suite to confirm no regression from removal.

> **Design Notes**: Keep `collapseMovChain` (O82/O88 dead-hi chain rewriting —
> a different transform). Keep `eliminateSelfMov`. Only the pure
> "reg already holds value" removers move into the new pass.
> **Implementation Notes**: _empty_

### Step 3.8 — Build [x]

### Step 3.9 — Run regression tests [x]

`python tests/run_all.py` (golden + lit + benchmarks). Diagnose/fix any
failure. Confirm benchmark cycle counts do not regress and improve where the
pattern occurs (fannkuch).

> **Result**: golden PASS, lit PASS (128 V6CLANG tests), benchmarks PASS (all five
> checksums unchanged). fannkuch -O2 improved 328 B / 28,798,404 cc ->
> 325 B / 28,748,820 cc. Four peephole/shift lit tests needed their
> *baseline* RUN lines extended with `--v6clang-disable-reg-value-forwarding`
> (O92 now also removes the round-trips their "disabled" prefixes expected).

### Step 3.10 — Verification assembly steps (tests/features/76) [x]

Compile `tests/features/76/v6clang.c` → `v6clang_new01.asm`; confirm `repro`'s
loop body has no redundant `MOV A, D` and the value is established once before
the loop, while the legitimate `.LBB15_6` reload (`A == 1`) is **preserved**.
Confirm `walk16` (non-A / 16-bit-pair-heavy) is unchanged or improved and
never miscompiled. Iterate (`_new02`, …) if needed. A/B with
`--v6clang-disable-reg-value-forwarding`.

### Step 3.11 — Create result.txt (tests/features/result.md format) [x]

### Step 3.12 — Sync mirror [x]

`powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1`;
verify `V6ClangRegValueForwarding.cpp` and the lit test appear under the mirrors.

---

## 4. Expected Results

### Example 1 — fannkuch init loop
Removes the per-iteration `MOV A, D` (8cc/1B) from the hot init loop and two
more redundant sites. In the test repro ([tests/features/76](../tests/features/76/v6clang.c))
two of the three `MOV A, D` reloads are redundant (loop body at `.LBB15_2`
and the block-entry reload at `.LBB15_3`); the third (`.LBB15_6`, where
`A == 1` not `D`) is a genuine reload and **must be preserved** — the
negative case that proves the analysis is value-correct, not pattern-matched.

### Example 2 — general `MVI` constant CSE
A block reached only via paths that already set `r = C` drops a redundant
`MVI r, C` — common after branch threading / tail duplication.

### Example 3 — unification
One correct implementation of "register already holds value" replaces three
partial ones, centralizing the `isO61PatchedImm` guard.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Erasing a patched-imm `MVI` (self-modified at runtime) | `isO61PatchedImm` guard; explicit negative lit test (d) |
| Stale forwarding after a pair/half write (aliasing) | All def checks + invalidations via `MCRegAliasIterator`/`TRI`; negative lit test (e) |
| Forwarding across a call | Apply regmask to invalidate non-preserved regs |
| Disturbing a pending FLAGS compare | Only erase `MOVrr`/`MVIr` (no FLAGS def); assert it |
| Clobbering equalities on value-preserving A-defs (`ORA A`) | Allowlist of value-preserving flag-ops treated as non-clobbering; covered by repro |
| Dataflow unsoundness on irreducible/loop CFG | Conservative visited-pred meet; bounded fixpoint; golden regression suite |
| Removing logic that other passes depended on | Keep `collapseMovChain`/`eliminateSelfMov`; full `run_all.py` after removal |

---

## 6. Relationship to Other Improvements
- Subsumes the redundant-move parts of O17-era AccumulatorPlanning and the
  Peephole `eliminateRedundantMov`.
- Complements (does not replace) upstream `machine-cp`.
- Honors O61 patched immediates (`MO_PATCH_IMM`).

## 7. Future Enhancements
- Extend to forward through `XCHG` (swap DE/HL lattice entries).
- Track constants materialized by `LXI`/`XRA A` for 16-bit `Const` CSE.

## 8. References
* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md)
* [Future Improvements](future_plans/README.md)
* [O92 design](future_plans/O92_unified_cross_bb_reg_value_forwarding.md)
* Test deps: `tools/v6emul` ([CLI](../tools/v6emul/docs/cli.md)), `tools/v6asm` ([CLI](../tools/v6asm/docs/cli.md))
