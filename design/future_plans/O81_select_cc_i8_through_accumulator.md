# O81 — i8 `SELECT_CC` Materialization Through Accumulator

## 1. Problem

`V6CLANG_SELECT_CC` (the i8 conditional-select pseudo, defined in
[V6ClangInstrInfo.td](llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.td#L652)) is
expanded by `V6ClangTargetLowering::EmitInstrWithCustomInserter`
([V6ClangISelLowering.cpp](llvm-project/llvm/lib/Target/V6Clang/V6ClangISelLowering.cpp#L1415))
into a diamond CFG:

```
BB:                          ; predecessor
  ...                        ; FLAGS-setter (CMP / ANI / ...)
  MVI <vT>, <true_imm>       ; materialize true arm  (when arm is a constant)
  MVI <vF>, <false_imm>      ; materialize false arm (when arm is a constant)
  J<inv> SinkBB              ; branch on inverted condition
TrueBB:                      ; fallthrough true path (empty)
SinkBB:
  vD = PHI(vT from TrueBB, vF from BB)
  ... = vD                   ; consumer (typically V6CLANG_STORE8_P)
```

The PHI's three virtual registers (`vT`, `vF`, `vD`) end up coalesced into a
single GR8 vreg by the register coalescer. The allocator picks any GR8
register — usually whichever is least contended.

For `fillScreen` in [temp/test_v6clangllvm/test.c](temp/test_v6clangllvm/test.c), the
inner loop's select compiles to:

```asm
.LBB15_2:
    LDAX D                   ; A := *src
    ANI  4                   ; A := A & 4 ; FLAGS = result
    JNZ  .LBB15_4
    MVI  C, 0                ; false arm  (2B / 7cc)
    JMP  .LBB15_5
.LBB15_4:
    MVI  C, 0x4F             ; true  arm  (2B / 7cc)
.LBB15_5:
    MOV  M, C                ; store
```

Register `A` is **dead** between the `JNZ` and the join (`b & 4` is consumed
by the branch), but the allocator picked `C`. Re-routing the select through
the dead accumulator would save 3cc on the zero path via the existing
O55 / "MVI A,0 → XRA A" peephole:

```asm
.LBB15_2:
    LDAX D
    ANI  4
    JNZ  .LBB15_4
    XRA  A                   ; false arm  (1B / 4cc)  — −1B / −3cc
    JMP  .LBB15_5
.LBB15_4:
    MVI  A, 0x4F             ; true  arm  (2B / 7cc)
.LBB15_5:
    MOV  M, A                ; store      (1B / 7cc)  — same
```

Per-iter win: roughly **+1.5cc geomean** (the zero path executes half the
iterations) and **−1B** of code size. For a 64×25 = 1600-iter loop that is
≈ **2400cc / +1 free GR8 inside the loop**. The freed register (`C` in this
example) becomes available for outer-loop counter promotion or further
spill reduction.

## 2. Why the allocator picks the wrong register today

Traced via `-print-after-all -filter-print-funcs=fillScreen`:

1. **After ISel** the chain is briefly tagged `acc` (when constrained
   experimentally), e.g. `%18:acc = MVIr 79`, `%19:acc = MVIr 0`,
   `%20:acc = PHI %19, %18`, `V6CLANG_STORE8_P %20:acc, ...`.

2. **`Register Coalescer`** calls `MachineRegisterInfo::recomputeRegClass()`
   on the merged vreg. Both `MVIr` (`outs GR8:$rd`) and `V6CLANG_STORE8_P`
   (`ins GR8:$src`) accept the broader `GR8` class. The coalescer keeps the
   **largest** class that satisfies every operand constraint (`GR8`), to
   maximise allocator flexibility. The `acc` constraint is dropped.

3. **In `greedy`**, processing order is roughly: longer / acc-constrained
   live ranges first, short GR8 live ranges later.
   - `%25:acc` (outer `y` counter, forced to A by `CPI %25, 25` in the outer
     latch) is live across the whole inner loop → tries A.
   - `%16:acc` (`LDAX D` result in bb.2) is also forced to A and conflicts
     with `%25` in bb.2 → greedy spills `%25` (`V6CLANG_SPILL8` at bb.1 entry,
     `V6CLANG_RELOAD8` at bb.6).
   - By the time greedy reaches the short-lived merged vreg (`%30:gr8`),
     A is logically "owned" by `%25` and the eviction analysis does not
     re-consider A even though it is physically free between the spill
     and the reload.
   - `HL = %29:gr16` (dest pointer), `DE = %28:gr16` (src pointer),
     `B = %27:gr8` (inner counter) are also taken. **`C` is the first
     free entry in alloc order after A is rejected** → `%30` gets `C`.

Two non-fixes that **were tried and confirmed insufficient**:

- **Soft regalloc hint** `MRI.setRegAllocationHint(DstReg, 0, V6CLANG::A)` —
  greedy still rejected A (it was not the assignment-time interference
  cost that drove the choice; it was the alloc-order traversal after A
  was filtered out as occupied by `%25`).
- **Class constraint** `MRI.setRegClass(DstReg/TrueReg/FalseReg, AccRegClass)`
  — the `acc` class was set at ISel time but the coalescer widened it back
  to `gr8` per (2) above.

## 3. Proposed design

Restructure the `V6CLANG_SELECT_CC` (i8) inserter to materialize the result
**through physreg `$a`** instead of through a vreg PHI, when it is
profitable and safe. The 16-bit `V6CLANG_SELECT_CC16` is left untouched — it
has no analogous A-routing benefit and its current diamond is consumed by
[V6ClangBranchOpt::foldZeroSelectReturn](llvm-project/llvm/lib/Target/V6Clang/V6ClangBranchOpt.cpp#L383).

### 3.1. Eligibility predicate

All of the following must hold at the inserter point:

1. **i8 select**: `MI.getOpcode() == V6CLANG::V6CLANG_SELECT_CC`.
2. **A is dead at the inverted branch position in BB**. Use the same
   `isRegDeadAtMI(V6CLANG::A, MI, MBB, &RI)` helper as the O77 store-pseudo
   expansion. This protects callers like `a + ((b & 4) ? K0 : K1)` where
   A holds the addend across the select.
3. **Both arms are rematerializable constants**: the `MachineInstr`
   defining `TrueReg` and `FalseReg` is a `V6CLANG::MVIr` (or `LXI` lo/hi
   half, etc.) with **no register operands**, located in `BB` (so it is
   safe to sink into a new child block), single-use (the select), and
   marked `isReMaterializable`.

   This restriction keeps the design minimal. Computed arms (e.g.,
   `LDAX D` results, ADD chains) require duplication or extra COPYs that
   may erode the win and are deferred to a follow-up (§6).

### 3.2. CFG rewrite

Replace the current 3-block expansion with a 4-block diamond:

```
BB:                          ; everything BEFORE the select EXCEPT the
                             ; MVIs that defined TrueReg / FalseReg
  ...
  J<cc>  TrueBB              ; un-inverted branch
                             ; (BB falls through to FalseBB)
FalseBB:                     ; sunk false-arm materialization
  MVIr   $a, <false_imm>     ; or XRA A via the O55 peephole when imm=0
  JMP    SinkBB
TrueBB:                      ; sunk true-arm materialization
  MVIr   $a, <true_imm>
                             ; (TrueBB falls through to SinkBB)
SinkBB:
  DstReg = COPY $a           ; physreg → vreg join
  ...                        ; existing successors / uses
```

Successor / predecessor edges:
- `BB` → {`TrueBB`, `FalseBB`}, equal weight (preserve original probability
  if known).
- `FalseBB` → `SinkBB`, `TrueBB` → `SinkBB`.
- Original out-edges of BB transfer to `SinkBB` (same `splice` /
  `transferSuccessorsAndUpdatePHIs` as today).

Liveness bookkeeping:
- Erase the original defining `MVIr` instructions from `BB` and recreate
  them in the respective branch block, with the **physreg `$a` as the
  def** (`RegState::Define`) and an `implicit-def $flags` marker
  (consistent with how `MVIr` is encoded — MVI does not actually touch
  flags, but `XRAr A` does; emitting the flags marker uniformly keeps
  the O55 peephole-rewrite easy).
- `FalseBB` and `TrueBB` get `$a` added as **live-out** to `SinkBB` via
  `SinkBB->addLiveIn(V6CLANG::A)`.
- `BB` must not carry `$a` live-out (verifier requirement).
- The trailing `COPY DstReg, $a` in `SinkBB` is placed at the block head
  (before any reschedulable user), and `DstReg`'s class stays `GR8`. The
  RegisterCoalescer is expected to coalesce `DstReg` with `$a` whenever
  `$a` is dead at the end of `DstReg`'s live range; otherwise a
  fallback `MOV r, A` survives — neutral vs. today.

### 3.3. Interaction with the O55 zero → `XRA A` peephole

`MVI A, 0` is rewritten to `XRA A` by the existing peephole when FLAGS are
dead. After this design, the false arm becomes `MVI A, 0` *unconditionally
guarded by `J<cc>`*, with no consumer of FLAGS between the new MVI and the
`JMP SinkBB`. The peephole therefore fires deterministically on the false
arm whenever the immediate is zero — that is the entire source of the
3cc / 1B win.

Symmetric: if the **true** arm is zero (CC inversion would put the zero
on the true side), apply the same rewrite there. The inserter does not
need to choose — emit `MVI A, 0` and let O55 do the rewrite.

### 3.4. Code outline

`EmitInstrWithCustomInserter`, i8 branch only, after harvesting
`DstReg / TrueReg / FalseReg / CC`:

```cpp
MachineRegisterInfo &MRI = MF->getRegInfo();
const V6ClangRegisterInfo &TRI = *Subtarget.getRegisterInfo();

auto isImmRemat = [&](Register R) -> MachineInstr * {
  if (!R.isVirtual()) return nullptr;
  MachineInstr *Def = MRI.getUniqueVRegDef(R);
  if (!Def || Def->getParent() != BB) return nullptr;
  if (Def->getOpcode() != V6CLANG::MVIr) return nullptr;
  if (!MRI.hasOneNonDBGUse(R)) return nullptr;
  return Def;
};

MachineInstr *TrueDef  = isImmRemat(TrueReg);
MachineInstr *FalseDef = isImmRemat(FalseReg);
bool ADead = isRegDeadAtMI(V6CLANG::A, MI, *BB, &TRI);

if (MI.getOpcode() == V6CLANG::V6CLANG_SELECT_CC &&
    TrueDef && FalseDef && ADead) {
  // --- 4-block "through-A" form ---
  int64_t TrueImm  = TrueDef->getOperand(1).getImm();
  int64_t FalseImm = FalseDef->getOperand(1).getImm();

  MachineBasicBlock *FalseBB = MF->CreateMachineBasicBlock();
  MachineBasicBlock *TrueBB  = MF->CreateMachineBasicBlock();
  MachineBasicBlock *SinkBB  = MF->CreateMachineBasicBlock();
  // ... insert, splice tail of BB to SinkBB, transfer successors ...

  TrueDef->eraseFromParent();
  FalseDef->eraseFromParent();

  unsigned JccOpc = /* non-inverted JCC for CC */;
  BuildMI(BB, DL, TII.get(JccOpc)).addMBB(TrueBB);
  BB->addSuccessor(TrueBB);
  BB->addSuccessor(FalseBB);

  BuildMI(FalseBB, DL, TII.get(V6CLANG::MVIr), V6CLANG::A).addImm(FalseImm);
  BuildMI(FalseBB, DL, TII.get(V6CLANG::JMP)).addMBB(SinkBB);
  FalseBB->addSuccessor(SinkBB);

  BuildMI(TrueBB, DL, TII.get(V6CLANG::MVIr), V6CLANG::A).addImm(TrueImm);
  TrueBB->addSuccessor(SinkBB);

  SinkBB->addLiveIn(V6CLANG::A);
  BuildMI(*SinkBB, SinkBB->begin(), DL, TII.get(TargetOpcode::COPY), DstReg)
      .addReg(V6CLANG::A, RegState::Kill);

  MI.eraseFromParent();
  return SinkBB;
}

// Fall back to existing 3-block diamond.
```

### 3.5. MachineBlockPlacement layout

After MBP the canonical layout becomes:

```
BB:        ... ; J<cc> TrueBB
FalseBB:   MVI A, 0     (→ XRA A by O55)
           JMP SinkBB
TrueBB:    MVI A, 0x4F
SinkBB:    MOV M, A     ; (or whatever the consumer is)
```

MBP may rotate the diamond and swap the fall-through (true vs. false).
That is fine — both arms are symmetric in this design.

## 4. Risks and mitigations

| # | Risk | Mitigation |
|---|------|-----------|
| 1 | `$a` live-in to `SinkBB` mis-tracked → verifier failure or stale-A miscompile downstream | Strict `addLiveIn(V6CLANG::A)` on `SinkBB`; verify with `-verify-machineinstrs` in lit. |
| 2 | A live across the select (e.g., `a + (cond ? K0 : K1)` with `a` held in A) | Gate on `isRegDeadAtMI(V6CLANG::A, ...)`; fall back to existing 3-block form otherwise. |
| 3 | `FLAGS` clobbered by `XRA A` rewrite when SinkBB consumers depend on flags from the CMP | The diamond already destroys FLAGS by virtue of the conditional branch; FLAGS are dead at SinkBB entry today. Re-verify after change. |
| 4 | RegisterCoalescer fails to coalesce `DstReg` with `$a` due to interference past the consumer | Falls back to `MOV r, A` at SinkBB head → neutral vs. today (no MVI-pair to compare against, since the materialization already happened in A). |
| 5 | Increased pressure on `$a` in functions with many selects + heavy A users (CPI / INR / LDAX / calls) | Eligibility gate (§3.1) — both arms must be rematerializable constants. Computed arms keep the 3-block form. |
| 6 | `V6ClangBranchOpt::foldZeroSelectReturn` and related branch folds (O15 / O23 / O30 / O35) pattern-match the 3-block diamond | Audit each folder. The 4-block form only fires when both arms are pure immediates; the foldZeroSelectReturn pattern requires a `RET` in the join — disjoint set in practice, but verify with the lit suite. |
| 7 | MachineSink / MachineCSE lose the ability to merge identical `MVIr 0`s across selects | These optimizations did not fire in any observed V6CLANG asm; low practical exposure. Re-measure with benchmarks. |
| 8 | Lit tests that pin specific select-cc asm need updating | Expected. The new form is strictly equal or shorter; update goldens. |

## 5. Expected impact

`fillScreen` benchmark (uint8_t IV-narrowed, post-O80 baseline):

| Metric | Before | After | Δ |
|---|---|---|---|
| Inner-loop false-path bytes | 2 (`MVI C, 0`) | 1 (`XRA A`) | −1B |
| Inner-loop false-path cycles | 7 | 4 | −3cc |
| Inner iterations per outer | 64 | 64 | — |
| Outer iterations | 25 | 25 | — |
| `fillScreen` total | — | ≈ −2400cc, −1B code size | — |
| Free GR8 inside inner loop | 0 (C used by select) | 1 (C, B both free except counter) | +1 |

Aggregate benchmark suite delta: expected geomean **−0.1 to −0.3%** cycles
on workloads with i8 immediate-arm selects in hot loops; flat elsewhere.

## 6. Follow-ups (out of scope for O81)

- **F-O81a**: extend eligibility to one-arm-constant / one-arm-vreg by
  emitting `MOV A, <vreg>` in the corresponding branch block.
- **F-O81b**: extend to `V6CLANG_SELECT_CC16` via routing through `HL` (DAD-
  friendly) with analogous liveness gating.
- **F-O81c**: when both arms are constants whose difference is ±1, fuse
  with the conditional branch into `INR A` / `DCR A` after a single
  `MVI A, base` in BB (skips the diamond entirely).

## 7. Test plan

1. **fillScreen golden**: update [tests/.../fillScreen*.ll](tests) or add a
   new lit test checking the `XRA A` / `MVI A, 0x4F` / `MOV M, A` shape.
2. **A-live negative case**: lit test with `r = a + (cond ? K0 : K1)`
   where `a` is held in A across the select; confirm the 3-block form is
   chosen and asm is unchanged from baseline.
3. **Computed-arm negative case**: `r = cond ? *p : *q` (both arms are
   loads); confirm the 3-block form is chosen.
4. **Branch-fold interaction**: re-run all existing
   `conditional_return*.ll`, `conditional_call*.ll`,
   `select_cc_zero_test.ll`, `branch_threading*.ll` tests; confirm no
   regressions.
5. **Benchmark suite**: `python tests/benchmarks_c/run_benchmarks.py`
   before/after; expect non-negative geomean.
6. **Verifier**: build with `LLVM_ENABLE_EXPENSIVE_CHECKS=ON` for the
   lit run that exercises this path.
