# O92 — Unified Cross-BB Physical-Register Value Forwarding

**Source:** V6CLANG — observed in `tests/benchmarks_c/asm/v6clang_fannkuch_O2.s` (`main`), reproduced in `temp/acc_loop_repro2.c`
**Savings:** 8cc, 1B per eliminated `MOV r, s` / `MVI r, imm`; recurs **per loop iteration** when the redundant write sits in a loop body
**Frequency:** Any loop/region where a value already resident in a physical register is re-materialised (re-`MOV`'d or re-`MVI`'d) on entry to or inside a block — common for accumulator reloads of loop-invariant values
**Complexity:** Medium — iterative cross-BB dataflow (fixpoint over the CFG), but lives in the existing `MachineFunctionPass` peephole vehicle
**Risk:** Medium — physical-register liveness + alias tracking + the O61 patched-immediate guard; bugs corrupt a register value silently. By preEmit there are **no V6CLANG pseudos left** (all expanded, incl. spill/reloads), so the only special-case is the patched `MVI`/`LXI`/`STA`/`SHLD`.
**Dependencies:** None new. Subsumes parts of `V6ClangAccumulatorPlanning` and `V6ClangPeephole`; complements (does not replace) upstream `machine-cp`
**Status:** [ ] not started

---

## Problem

On the 8080 nearly every value flows through a small fixed register file, and
the single accumulator `A` is the only ALU port. The register allocator and
ISel frequently emit a write that re-establishes a value a register *already
holds*. The canonical case is an accumulator reload of a loop-invariant value
that the allocator parked in a general register.

### Concrete instance (fannkuch `main`, first init loop)

```asm
; %bb.0
        LDA     __v6clang_a.repro     ; A = n
        MOV     D, A              ; D = n
        ORA     A                 ; A unchanged (= n), sets Z
        JZ      .LBB15_3
; %bb.1
        MVI     E, 0
        LXI     H, perm1
.LBB15_2:                         ; inner loop
        MOV     M, E
        INR     E
        MOV     A, D              ; <-- redundant: A ALREADY = D on every iter
        CMP     E
        INX     H
        JNZ     .LBB15_2
```

At loop entry `A` already equals `D` (established in `bb.0`), and the loop body
never redefines `A` or `D`. Therefore `MOV A, D` is redundant on **every**
iteration — it should be deleted outright (0cc), not hoisted.

The same source shows two more redundant `MOV A, D` sites (the second-loop
preheader and `bb.6`). The reload of `n` is the i8 `CMP`/`CPI` operand, and
`CMP` requires its left operand in `A` (register class `acc` = physical `A`
only), which is what generates the reload pattern.

### Why this generalises beyond `A`

The underlying fact is register-agnostic: **if physical register `R` is already
known to hold value `V` (another register, or a constant), a later write of `V`
into `R` is redundant.** This covers:

- `MOV r, s` when `r` already equals `s`,
- `MVI r, imm` when `r` already holds `imm`,
- the accumulator-reload case as one instance.

---

## Root-cause analysis

The redundancy is established in one block and carried across a CFG edge
(including a loop back-edge). No existing mechanism removes it:

1. **`machine-cp` (upstream MachineCopyPropagation, runs twice).** Reasons
   **intra-block** only. It cannot prove `A == D` holds on entry to `.LBB15_2`
   from the predecessor *and* survives the back-edge, so it leaves the `MOV A, D`.

2. **`V6ClangAccumulatorPlanning::eliminateRedundantAccMoves`.** A-specific and
   **local**: it eliminates `MOV A,X; MOV X,A` round-trips and redundant
   `MOV X,A` within a block via value tracking. It does not carry an
   "A holds X on block entry" fact across edges.

3. **`V6ClangPeephole::eliminateRedundantMov` / `collapseMovChain`.** Local MOV/MVI
   cleanups, single forward scan within a block.

So three mechanisms each implement a fragment of the same abstraction — "reg
already holds value, drop the redundant write" — none of them cross-BB, and each
re-derives its own guards (notably the O61 patched-immediate skip; see
`isO61PatchedImm` in `V6ClangPeephole.cpp`).

### Pipeline timing makes this tractable

By the time `addPreEmitPass` runs, **all V6CLANG pseudos are already expanded** —
including the spill/reload family. The relevant expanders all run in the
postRegAlloc region, *before* `addPreEmitPass`:

- `ExpandPostRAPseudos` lowers `V6CLANG_LOAD8_P`/`STORE8_P`, `V6CLANG_DAD`, `INX16`,
  `BUILD_PAIR`, etc. (see `V6ClangInstrInfo::expandPostRAPseudo`).
- `V6ClangSpillPatchedReload` (in `addPostRegAlloc`) rewrites *eligible*
  spill/reload groups into the patched `MVI r,0` / `LXI rp,0` form, tagged with
  a `.LLo61_N:` pre-instr label and `MO_PATCH_IMM` on the imm operand.
- `PrologEpilogInserter::eliminateFrameIndex` (`V6ClangRegisterInfo.cpp`) expands
  every *remaining* `V6CLANG_SPILL8`/`RELOAD8` (and 16-bit forms) into real
  `STA`/`LDA` / O64-ladder instructions.

Confirmed empirically (post-`postrapseudos` MIR of the repro): the inner loop is
already real instructions — `MOVMr`, `INRr`, `MOVrr`, `CMPr`, `INX` — with **no
pseudos**. So a preEmit pass sees a fully-flat instruction stream **and** has
full MIR CFG + liveness + `TRI`.

**Consequence:** there is *no* opaque-pseudo hazard. The expanded patched
reloads, however, look like ordinary `MVI r, 0` (or `LXI`/`STA`/`SHLD`) yet
their immediate byte is self-modified at runtime — so the one real special-case
is the O61 patched-immediate guard (`isO61PatchedImm` / `MO_PATCH_IMM`), exactly
as existing V6CLANG peepholes already handle.

This also corrects an earlier mis-framing: a "peephole" here is a
`MachineFunctionPass` and already uses liveness (`MBB.isLiveIn`,
`Succ->isLiveIn(FLAGS)`) and cross-BB reachability (`isUncoveredLhldReachable`,
"any forward path including loop back-edges"). The MIR-pass vs. peephole
distinction is not real — they are the same vehicle.

---

## Proposed solution

A single **physical-register value-forwarding** `MachineFunctionPass` at
`addPreEmitPass`, running **after** `machine-cp` and the existing peepholes so it
mops up the cross-BB cases they structurally cannot reach.

### Lattice

Per physical register, a value lattice:

```
        ⊤  (unknown)
       /        \
  equals-reg-R   equals-const-C
       \        /
        ⊥  (conflict / clobbered)
```

- `Top` — nothing known.
- `Reg(R)` — this register provably equals the current contents of `R`.
- `Const(C)` — this register provably holds immediate `C`.
- `Bottom` — clobbered / conflicting across predecessors.

State is a map `PhysReg -> LatticeVal`, computed at block entry by **meet over
predecessors** and propagated forward through the block. Iterate to a
**fixpoint** over the CFG (worklist) so loop back-edges converge — the back-edge
must agree before a write inside the loop may be deleted.

### Transfer / elimination

Walking a block with the in-state:
- `MOV r, s` — if state says `r == s` (directly, or transitively via `Reg`
  chains), **erase**. Else update `r := Reg(s)`.
- `MVI r, imm` — if state says `r == Const(imm)`, **erase**. Else
  `r := Const(imm)`.
- Any other def of `r` (explicit or implicit) — `r := Top` (then re-derive if
  it is itself a tracked move).
- On erase, only the *write* is removed; FLAGS are not touched (`MOV`/`MVI`
  don't set flags on 8080, so no flag-liveness hazard — but assert this).

### Invalidation (alias-correct)

8080 pairs alias their halves. Any def of `R` must invalidate, via
`MCRegAliasIterator`/`TRI`:
- `R` itself and its aliases (e.g. def of `D` kills `DE`; `LXI H` kills `H`,
  `L`, `HL`; writing `A` kills `PSW`),
- every lattice entry whose value is `Reg(R')` where `R'` aliases the defined
  register (a stale "equals R'" must drop when `R'` changes).

### Guards (correctness core)

1. **O61 patched immediates (the only special-case).** Spill/reloads are
   already expanded by preEmit, so there is no pseudo to model — but the
   *eligible* ones became patched `MVI r,0` / `LXI rp,0` / `STA`/`SHLD` whose
   immediate is self-modified at runtime (the literal `0` is overwritten by an
   earlier spill). Reuse `isO61PatchedImm` (pre-instr symbol or any
   `MO_PATCH_IMM` target flag): never record such a `MVI`/`LXI` as `Const`,
   never forward across it, and never erase a write the patch chain depends on.

3. **Calls / regmasks.** A `CALL` (and `Ccc`/`RST`) clobbers per its regmask —
   invalidate every register the mask does not preserve.

4. **Implicit defs.** Honor `implicit-def` operands (e.g. `DAD` def of `HL`,
   ALU def of `FLAGS`) when invalidating. Note that some expanded reloads route
   through `A` (the O64 non-A ladder), so their `A` clobber is already an
   explicit/implicit def on the real instructions — no pseudo modelling needed.

### What it removes vs. what it does NOT do

- **Removes** the redundant *write* (the per-iteration `MOV A, D`), saving its
  cycles every time the block executes. In fannkuch this deletes the loop-body
  reload entirely.
- Does **not** free the source register. `D` stays pinned holding `n` across the
  function regardless — this is redundancy elimination, **not** register-pressure
  reduction. (Important: do not advertise a pressure win.)

---

## Unification plan

Fold the two overlapping **V6CLANG** redundant-move mechanisms into this pass:

- Replace `V6ClangAccumulatorPlanning::eliminateRedundantAccMoves` (its
  redundant-A-move/value-tracking part). Keep AccumulatorPlanning's
  **reordering/scheduling** role — that is a different job.
- Replace `V6ClangPeephole::eliminateRedundantMov` and the redundant-MOV portion of
  `collapseMovChain` (keep the dead-hi / build-pair-specific collapses that are
  not pure value-forwarding).
- Centralise the `isO61PatchedImm` guard so it cannot be forgotten in one place.

Do **not** remove upstream `machine-cp` — it is generic infrastructure other
passes rely on. The new pass runs after it and handles only the cross-BB cases
`machine-cp` cannot.

---

## Implementation sketch

1. New file `llvm/lib/Target/V6CLANG/V6ClangRegValueForwarding.cpp` (+ mirror under
   `llvm-project/...`), `MachineFunctionPass`.
2. CLI toggle `-v6clang-disable-reg-value-forwarding` (double-dash via `-mllvm`).
3. Register in `V6ClangTargetMachine::addPreEmitPass` **after** the existing
   peephole/loadstore passes (position TBD by measurement; likely just before
   `RedundantFlagElim`).
4. Worklist fixpoint over MBBs; per-block in/out lattice maps; alias-correct
   invalidation via `TRI`.
5. Wire `createV6ClangRegValueForwardingPass` into `V6Clang.h`, `CMakeLists.txt`,
   `V6ClangTargetMachine.cpp`. Add xcopy lines to **both** `sync_llvm_mirror.ps1`
   and `populate_llvm_project.ps1` (per repo convention for new backend files).
6. Excise the folded logic from `V6ClangAccumulatorPlanning` / `V6ClangPeephole`.

---

## Testing

- **Feature test:** new `tests/features/NN/` from `temp/acc_loop_repro2.c`;
  assert the loop body has no `MOV A, D` and the value is established once before
  the loop.
- **Lit test:** `llvm-project/llvm/test/CodeGen/V6CLANG/reg-value-forwarding-cross-bb.ll`
  covering (a) cross-BB `MOV` elision, (b) loop back-edge convergence, (c)
  `MVI` constant redundancy, (d) **negative**: a patched-imm `MVI` (carrying a
  `.LLo61_N:` pre-instr label / `MO_PATCH_IMM`) is preserved and is **not**
  recorded as `Const(0)`, (e) **negative**: a value is not forwarded across an
  expanded reload that clobbers the source/destination register.
- **Regression guard:** the real-fannkuch case where the preheader does
  `XRA A` (a spill) — `A` does **not** hold `n` at loop entry there, so the
  reload must be **kept**. Verify the pass leaves it.
- Run `python tests/run_all.py` (golden + lit + benchmarks); confirm benchmark
  cycle counts drop and no golden diffs regress.

---

## Verification commands

```pwsh
# Build
pwsh scripts\build.ps1 -SkipTests

# Repro before/after
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 temp\acc_loop_repro2.c -S `
  -o temp\acc_loop_repro2.s -mllvm -mv6clang-annotate-pseudos

# A/B the pass
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 temp\acc_loop_repro2.c -S -o - `
  -mllvm --v6clang-disable-reg-value-forwarding | Select-String "MOV.*A, D"
```
