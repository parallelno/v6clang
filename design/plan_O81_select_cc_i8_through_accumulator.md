# Plan: O81 — `SELECT_CC` i8 Materialization Through Accumulator

## 1. Problem

### Current behavior

`V6CLANG_SELECT_CC` (the i8 conditional-select pseudo) is expanded by
`V6ClangTargetLowering::EmitInstrWithCustomInserter`
([V6ClangISelLowering.cpp](llvm-project/llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp))
into a 3-block diamond with a PHI node:

```
BB:
  MVI <vF>, <false_imm>
  MVI <vT>, <true_imm>
  J<inv> SinkBB
TrueBB:
  (empty)
SinkBB:
  vD = PHI(vT from TrueBB, vF from BB)
  MOV M, vD               ; V6CLANG_STORE8_P / HL-destination consumer
```

The PHI's three virtual registers (`vT`, `vF`, `vD`) coalesce to GR8.
The register allocator then picks any free GR8 — in a double-loop where
the outer counter holds A via `CPI`, the allocator assigns C:

```asm
; fillscreen() inner loop — BEFORE O81
.LBB15_2:
    LDAX  D              ; A := *src
    ANI   4              ; FLAGS set
    JNZ   .LBB15_4
    MVI   C, 0           ; false arm (2B / 8cc) — SUBOPTIMAL
    JMP   .LBB15_5
.LBB15_4:
    MVI   C, 0x4F        ; true  arm (2B / 8cc)
.LBB15_5:
    MOV   M, C           ; store  (1B / 8cc)
```

A is **physically dead** between the branch and the join — the `ANI 4`
result was consumed by the `JNZ` — but the allocator's eviction analysis
does not re-examine A after it filters it out due to the outer counter's
live range. C is picked instead.

### Desired behavior

Route the select through physreg A with a 4-block diamond form. The
existing O55 peephole (`MVI A, 0` → `XRA A` when FLAGS dead) then fires
deterministically on the zero arm, saving 1B / 4cc:

```asm
; fillscreen() inner loop — AFTER O81 (+O55 peephole)
.LBB15_2:
    LDAX  D              ; A := *src
    ANI   4              ; FLAGS set
    JNZ   .LBB15_4
    XRA   A              ; false arm (1B / 4cc) — +1B / +4cc
    JMP   .LBB15_5
.LBB15_4:
    MVI   A, 0x4F        ; true  arm (2B / 8cc)
.LBB15_5:
    MOV   M, A           ; store  (1B / 8cc)
```

### Root cause

The register coalescer widens the vreg class back to `GR8` (from `acc`)
when merging through PHI because `MVIr` accepts `GR8`. Two attempted
non-fixes (regalloc hint, forced class constraint) both failed — the
allocator's traversal order filters out A before the priority queue
reaches the short-lived select vreg. A post-ISel rewrite in
`EmitInstrWithCustomInserter` bypasses regalloc entirely.

Scope: HL-destination case only. STAX-based stores (`V6CLANG_STORE8_P` with
dest in BC/DE) already route through A naturally since `STAX B/D`
requires the value in A.

---

## 2. Strategy

### Approach: 4-block "through-A" diamond in EmitInstrWithCustomInserter

Replace the 3-block diamond (PHI-based) with a 4-block diamond that uses
physreg A directly when all eligibility conditions are met:

```
BB:                           ; condition test (ANI / CMP / etc.)
  J<cc>  TrueBB               ; un-inverted branch
                              ; (fall-through to FalseBB)
FalseBB:
  MVI  A, <false_imm>         ; (→ XRA A by O55 when imm=0)
  JMP  SinkBB
TrueBB:
  MVI  A, <true_imm>
                              ; (fall-through to SinkBB)
SinkBB:
  DstReg = COPY A             ; physreg → vreg; coalesced by RegCoalescer
  ...                         ; existing successors / users
```

**Eligibility predicate** (all must hold):

1. `MI.getOpcode() == V6CLANG::V6CLANG_SELECT_CC` (i8 only; `V6CLANG_SELECT_CC16`
   is left untouched — it interacts with `foldZeroSelectReturn`).
2. `isPhysRegDeadAtMI(V6CLANG::A, MI, *BB, TRI)` — A is not live at MI.
3. Both `TrueReg` and `FalseReg` are single-use `MVIr` defs located in
   `BB` (rematerializable constants; computed arms deferred to F-O81a).

The static helper `isPhysRegDeadAtMI` is copied from `V6ClangInstrInfo.cpp`
(`isRegDeadAtMI` there) as a file-scope function before
`EmitInstrWithCustomInserter`.

### Summary of changes

| File | Change |
|------|--------|
| `llvm-project/llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp` | Add `isPhysRegDeadAtMI` static helper; add 4-block through-A path inside the `V6CLANG_SELECT_CC` case |
| `llvm-project/llvm/test/CodeGen/V6CLANG/select-cc-i8-acc-baseline.ll` | Already created; update `fillscreen_double` CHECK lines from `MVI C, 0` → `XRA A` after O81 is built |
| `tests/features/66/` | Feature regression test folder; baseline already compiled |
| `design/future_plans/README.md` | Mark O81 ✅ |

---

## 3. Implementation Steps

### Step 3.1 — Add `isPhysRegDeadAtMI` helper + 4-block diamond path [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp`

**3.1.1 — Static helper** (add before `EmitInstrWithCustomInserter`):

```cpp
/// Return true if physical register Reg is dead (has no uses before
/// the next def) starting from the instruction following MI in MBB.
/// Mirrors isRegDeadAtMI in V6ClangInstrInfo.cpp.
static bool isPhysRegDeadAtMI(unsigned Reg, const MachineInstr &MI,
                               MachineBasicBlock &MBB,
                               const TargetRegisterInfo *TRI) {
  for (auto I = std::next(MI.getIterator()); I != MBB.end(); ++I) {
    bool usesReg = false, defsReg = false;
    for (const MachineOperand &MO : I->operands()) {
      if (!MO.isReg() || !TRI->regsOverlap(MO.getReg(), Reg)) continue;
      if (MO.isUse() && !MO.isUndef()) usesReg = true;
      if (MO.isDef()) defsReg = true;
    }
    if (usesReg) return false;
    if (defsReg) return true;
  }
  for (MachineBasicBlock *Succ : MBB.successors())
    for (MCRegAliasIterator AI(Reg, TRI, true); AI.isValid(); ++AI)
      if (Succ->isLiveIn(*AI)) return false;
  return true;
}
```

**3.1.2 — Through-A path in `EmitInstrWithCustomInserter`** (add
*before* the existing block-creation code, inside `case V6CLANG::V6CLANG_SELECT_CC:
case V6CLANG::V6CLANG_SELECT_CC16:`):

```cpp
MachineRegisterInfo &MRI = MF->getRegInfo();
const TargetRegisterInfo *TRI =
    BB->getParent()->getSubtarget().getRegisterInfo();

auto isImmRemat = [&](Register R) -> MachineInstr * {
  if (!R.isVirtual()) return nullptr;
  MachineInstr *Def = MRI.getUniqueVRegDef(R);
  if (!Def || Def->getParent() != BB) return nullptr;
  if (Def->getOpcode() != V6CLANG::MVIr) return nullptr;
  if (!MRI.hasOneNonDBGUse(R)) return nullptr;
  return Def;
};

if (MI.getOpcode() == V6CLANG::V6CLANG_SELECT_CC) {
  MachineInstr *TrueDef  = isImmRemat(TrueReg);
  MachineInstr *FalseDef = isImmRemat(FalseReg);
  if (TrueDef && FalseDef && isPhysRegDeadAtMI(V6CLANG::A, MI, *BB, TRI)) {
    int64_t TrueImm  = TrueDef->getOperand(1).getImm();
    int64_t FalseImm = FalseDef->getOperand(1).getImm();

    MachineBasicBlock *FalseBBNew = MF->CreateMachineBasicBlock();
    MachineBasicBlock *TrueBBNew  = MF->CreateMachineBasicBlock();
    MachineBasicBlock *SinkBB     = MF->CreateMachineBasicBlock();
    MachineFunction::iterator It = ++BB->getIterator();
    MF->insert(It, FalseBBNew);
    MF->insert(It, TrueBBNew);
    MF->insert(It, SinkBB);

    SinkBB->splice(SinkBB->begin(), BB,
                   std::next(MachineBasicBlock::iterator(MI)), BB->end());
    SinkBB->transferSuccessorsAndUpdatePHIs(BB);

    // Erase the original MVIr defs from BB (their only use was the select).
    TrueDef->eraseFromParent();
    FalseDef->eraseFromParent();

    // BB: un-inverted conditional branch to TrueBBNew; fall through to FalseBBNew.
    unsigned JccOpc;
    switch (CC) {
    default: llvm_unreachable("Unknown V6CLANG condition code");
    case V6ClangCC::COND_NZ: JccOpc = V6CLANG::JNZ; break;
    case V6ClangCC::COND_Z:  JccOpc = V6CLANG::JZ;  break;
    case V6ClangCC::COND_NC: JccOpc = V6CLANG::JNC; break;
    case V6ClangCC::COND_C:  JccOpc = V6CLANG::JC;  break;
    case V6ClangCC::COND_PO: JccOpc = V6CLANG::JPO; break;
    case V6ClangCC::COND_PE: JccOpc = V6CLANG::JPE; break;
    case V6ClangCC::COND_P:  JccOpc = V6CLANG::JP;  break;
    case V6ClangCC::COND_M:  JccOpc = V6CLANG::JM;  break;
    }
    BuildMI(BB, DL, TII.get(JccOpc)).addMBB(TrueBBNew);
    BB->addSuccessor(FalseBBNew);
    BB->addSuccessor(TrueBBNew);

    // FalseBB: materialize false arm in A, then jump to SinkBB.
    BuildMI(FalseBBNew, DL, TII.get(V6CLANG::MVIr), V6CLANG::A).addImm(FalseImm);
    BuildMI(FalseBBNew, DL, TII.get(V6CLANG::JMP)).addMBB(SinkBB);
    FalseBBNew->addSuccessor(SinkBB);

    // TrueBB: materialize true arm in A; fall through to SinkBB.
    BuildMI(TrueBBNew, DL, TII.get(V6CLANG::MVIr), V6CLANG::A).addImm(TrueImm);
    TrueBBNew->addSuccessor(SinkBB);

    // SinkBB: COPY physreg A → vreg DstReg (coalescer will eliminate).
    SinkBB->addLiveIn(V6CLANG::A);
    BuildMI(*SinkBB, SinkBB->begin(), DL,
            TII.get(TargetOpcode::COPY), DstReg)
        .addReg(V6CLANG::A, RegState::Kill);

    MI.eraseFromParent();
    return SinkBB;
  }
}
```

### Step 3.2 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

### Step 3.3 — Update lit test `select-cc-i8-acc-baseline.ll` [x]

**File**: `llvm-project/llvm/test/CodeGen/V6CLANG/select-cc-i8-acc-baseline.ll`

After O81 fires, `fillscreen_double` now produces `XRA A` / `MOV M, A`
instead of `MVI C, 0` / `MOV M, C`. Update the CHECK lines accordingly.

Also add `select_through_a` positive case: verify that `JNZ` / `XRA A` /
`JMP` / `MVI A, 0x4F` / `MOV M, A` are present in the output.

Verify:
```
llvm-build\bin\llc -march=v6clang llvm-project\llvm\test\CodeGen\V6CLANG\select-cc-i8-acc-baseline.ll -o - | llvm-build\bin\FileCheck llvm-project\llvm\test\CodeGen\V6CLANG\select-cc-i8-acc-baseline.ll
```

### Step 3.4 — Run regression tests [x]

```
python tests\run_all.py
```

If any test fails, diagnose, fix, rebuild, rerun. Update CHECK lines
for any test that previously pinned `MVI C, 0` in a select pattern.

### Step 3.5 — Compile feature test and verify [x]

```
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S tests\features\66\v6clang.c -o tests\features\66\v6clang_new01.asm
```

Expected in `fillscreen` inner loop:
- `JNZ   .LBB*_*`
- `XRA   A`
- `JMP   .LBB*_*`
- `MVI   A, 0x4F`
- `MOV   M, A`

If the improvement is absent, check whether A is actually dead at the
select site (`-print-after-all -filter-print-funcs=fillscreen`).

### Step 3.6 — Create `result.txt` [x]

Per `tests/features/README.md`, `result.txt` must summarise:
- C source functions
- c8080 reference asm + worst-cycle and byte stats
- v6clang before (`v6clang_old.asm`) + worst-cycle / byte stats
- v6clang after (`v6clang_new01.asm`) + worst-cycle / byte stats
- Net change table

### Step 3.7 — Sync mirror and update README [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

Update `design/future_plans/README.md`: add ✅ before
`O81_select_cc_i8_through_accumulator.md`.

---

## 4. Expected impact

`fillscreen` benchmark (64×25 loop, i8 IV-narrowed, post-O80 baseline):

| Metric | Before | After | Δ |
|---|---|---|---|
| False-arm bytes (MVI C, 0 vs XRA A) | 2B | 1B | −1B |
| False-arm cycles | 8cc | 4cc | −4cc |
| Inner iterations | 64 | 64 | — |
| Outer iterations | 25 | 25 | — |
| Half-iterations on false path (avg) | 800 | 800 | — |
| Total false-path savings | — | — | ≈ −3200cc, −1B code |
| Free GR8 inside inner loop | 0 (C used) | 1 (C free) | +1 |

Timing note: `MVI R, n` is 8cc on Vector 06C (not 7cc as in the design
document — timing table at `docs/Vector_06c_instruction_timings.md`
shows 8cc for `MVI R,D8`).

Aggregate benchmark suite delta: geomean **−0.1 to −0.3%** cycles on
workloads with i8 immediate-arm selects in hot HL-destination loops.
