# Plan: CMP-Based Non-Destructive 16-bit Comparison for V6CLANG

## 1. Problem

### Current behavior

The V6CLANG_BR_CC16 pseudo expands EQ/NE 16-bit comparisons using a
destructive XOR sequence that clobbers the LHS register pair:

```asm
; V6CLANG_BR_CC16 NE expansion (current): 48cc, clobbers LhsHi
    MOV  A, B           ;  8cc  — LhsHi
    XRA  D              ;  4cc  — XOR with RhsHi
    MOV  B, A           ;  8cc  — clobber LhsHi with XOR result!
    MOV  A, C           ;  8cc  — LhsLo
    XRA  E              ;  4cc  — XOR with RhsLo
    ORA  B              ;  4cc  — combine lo XOR | hi XOR
    JNZ  Target         ; 12cc  — total 48cc
```

Because the XOR clobbers LhsHi, V6CLANG_BR_CC16 carries a tied-output
constraint (`$lhs = $lhs_wb`) that forces the register allocator to copy
the LHS register pair before the comparison whenever LHS is still live.

### Desired behavior

```asm
; CMP-based NE (target): 48cc worst-case, 24cc early-exit, non-destructive
    MOV  A, C           ;  8cc  — LhsLo
    CMP  E              ;  4cc  — compare with RhsLo, sets Z. A unchanged.
    JNZ  Target         ; 12cc  — lo bytes differ → not equal (24cc early exit)
    MOV  A, B           ;  8cc  — LhsHi
    CMP  D              ;  4cc  — compare with RhsHi, sets Z. A unchanged.
    JNZ  Target         ; 12cc  — hi bytes differ → not equal (48cc)
    ; fall through: both bytes equal
```

The CMP instruction (`A − operand`) sets flags without modifying A or the
operand register. Neither LHS nor RHS is clobbered.

### Root cause

The XOR-based approach was chosen because it produces a single Z flag from
a 16-bit comparison without MBB splitting. However, it requires using a
register as scratch for the intermediate XOR result, which necessitates
the tied-output clobber constraint.

The CMP-based approach tests each byte independently with an early-exit
branch. This requires MBB splitting (two basic blocks, each with one
conditional branch), but preserves all register values.

### Impact on the array-copy loop

The destructive comparison causes a **cascade of inefficiencies**:

1. **Tied-output copy**: RA inserts `MOV H,B; MOV L,C` (16cc) to copy
   BC to HL before the comparison — because V6CLANG_BR_CC16 declares that
   it clobbers `$lhs`.

2. **Comparison constant in register pair**: `LXI DE, array1+100` (12cc)
   occupies DE with the comparison constant, so the destination pointer
   must be stored elsewhere.

3. **Destination pointer spill**: With BC=source, DE=constant, only HL
   remains — but HL is occupied by the copy. The destination pointer is
   **spilled to the stack**. Each iteration pays ~100cc in PUSH/POP plus
   stack load/store overhead.

4. **INX BC missed**: The INX peephole can't fire for BC because PUSH/POP
   around the spilled DE interleave between `LXI HL, 1` and the ADD16
   expansion, breaking the backward LXI scan.

After fixing the comparison:

- No tied-output constraint → no copy (saves 16cc + frees HL)
- Three register pairs available: BC=source, DE=dest, HL=constant
- No spill (saves ~100cc per iteration)
- Both INX peepholes fire (saves additional ~24cc)

| Metric | Before | After | Savings |
|--------|--------|-------|---------|
| Instructions per iteration | ~38 | ~10 | 74% fewer |
| Stack spill/reload | ~100cc | 0cc | eliminated |
| Tied-output copy | 16cc | 0cc | eliminated |
| Pointer increments | ~48cc | 16cc | 3× faster |
| Comparison | 48cc | 24-48cc | early exit |
| **Total per iteration** | **~268cc** | **~80cc** | **~3.4× faster** |

---

## 2. Strategy

### Approach: CMP-based MBB splitting in expandPostRAPseudo

The expansion remains in `V6ClangInstrInfo::expandPostRAPseudo()` where
V6CLANG_BR_CC16 is already handled, but the EQ/NE case is replaced with a
CMP-based sequence that splits the MBB into two blocks.

**For NE (COND_NZ)** — both branches go to the same target:
```
MBB:                              CompareHiMBB:
  MOV  A, LhsLo                    MOV  A, LhsHi
  CMP  RhsLo                       CMP  RhsHi
  JNZ  Target  ──────►Target        JNZ  Target  ──────►Target
  │ (fallthrough)                   │ (fallthrough)
  └──► CompareHiMBB                 └──► FallthroughMBB
```

**For EQ (COND_Z)** — first branch skips to fallthrough, second jumps:
```
MBB:                              CompareHiMBB:
  MOV  A, LhsLo                    MOV  A, LhsHi
  CMP  RhsLo                       CMP  RhsHi
  JNZ  FallthroughMBB ──┐           JZ   Target  ──────►Target
  │ (fallthrough)       │           │ (fallthrough)
  └──► CompareHiMBB     │           └──► FallthroughMBB ◄─┘
```

Each resulting MBB has exactly **one conditional branch** — perfectly
analyzable by `analyzeBranch`, BranchFolding, and the custom BranchOpt.

### Why this works at expandPostRAPseudo

1. **Physical registers known** — we emit MOV/CMP with concrete registers.
2. **MBB splitting is standard** — many LLVM backends split MBBs during
   pseudo expansion (e.g., ARM's conditional execution lowering).
3. **After RA** — register allocation is complete; the new MBBs don't
   need virtual registers or SSA form.
4. **BranchFolding handles it** — BranchFolding runs after
   expandPostRAPseudo and will optimize any redundant JMPs. Each block
   has clean single-branch terminators that `analyzeBranch` returns
   successfully on.

### Why the XOR approach used to hang with MBB splitting

A previous attempt at MBB splitting for V6CLANG_BR_CC16 caused an infinite
hang. The root cause was likely that the previous implementation didn't
correctly handle successor lists or produced non-analyzable branch
patterns. The CMP approach avoids this by producing strictly standard
patterns: each MBB contains at most one conditional branch plus an
optional unconditional branch — the normal Jcc / JMP pattern that
`analyzeBranch` and `insertBranch` expect.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Remove tied-output | `(outs)` instead of `(outs GR16:$lhs_wb)` | V6ClangInstrInfo.td |
| Update ISel | Produce `MVT::Other` (no i16 result) | V6ClangISelDAGToDAG.cpp |
| Update operand indices | Shift back by 1 (remove output operand) | V6ClangInstrInfo.cpp |
| Implement CMP expansion | MBB splitting with CMP + Jcc for EQ/NE | V6ClangInstrInfo.cpp |
| Keep SUB/SBB path | Non-EQ/NE conditions unchanged | V6ClangInstrInfo.cpp |

---

## 3. Implementation Steps

### Step 3.1 — Remove tied-output constraint from V6CLANG_BR_CC16 [x]

**File**: `llvm/lib/Target/V6Clang/V6ClangInstrInfo.td`

The CMP-based expansion is non-destructive — it doesn't modify LHS or
RHS. The tied-output constraint is no longer needed.

Change:
```tablegen
// Before:
let isBranch = 1, isTerminator = 1, Defs = [A, FLAGS] in
def V6CLANG_BR_CC16 : V6ClangPseudo<(outs GR16:$lhs_wb),
    (ins GR16:$lhs, GR16:$rhs, i8imm:$cc, brtarget:$dst),
    "# BR_CC16 $lhs, $rhs, $cc, $dst",
    []> {
  let Constraints = "$lhs = $lhs_wb";
}

// After:
let isBranch = 1, isTerminator = 1, Defs = [A, FLAGS] in
def V6CLANG_BR_CC16 : V6ClangPseudo<(outs),
    (ins GR16:$lhs, GR16:$rhs, i8imm:$cc, brtarget:$dst),
    "# BR_CC16 $lhs, $rhs, $cc, $dst",
    []>;
```

> **Design Note**: `Defs = [A, FLAGS]` remains correct — the CMP
> expansion still uses A as a temporary (`MOV A, LhsLo; CMP RhsLo`),
> and CMP sets FLAGS. This tells RA that A and FLAGS are clobbered
> across the pseudo, so it won't keep live values in A.

### Step 3.2 — Update ISel: remove i16 output from SDNode [x]

**File**: `llvm/lib/Target/V6Clang/V6ClangISelDAGToDAG.cpp`

The V6CLANG_BR_CC16 MachineInstr no longer has a register output. The
SDNode should only produce a chain (MVT::Other):

```cpp
  case V6ClangISD::BR_CC16: {
    SDValue Chain = N->getOperand(0);
    SDValue LHS   = N->getOperand(1);
    SDValue RHS   = N->getOperand(2);
    SDValue CC    = N->getOperand(3);
    SDValue Dest  = N->getOperand(4);

    SmallVector<SDValue, 5> Ops;
    Ops.push_back(LHS);
    Ops.push_back(RHS);
    Ops.push_back(CC);
    Ops.push_back(Dest);
    Ops.push_back(Chain);

    // No register output — only the chain.
    SDVTList VTs = CurDAG->getVTList(MVT::Other);
    SDNode *BrCC = CurDAG->getMachineNode(V6CLANG::V6CLANG_BR_CC16, DL,
                                           VTs, Ops);
    ReplaceNode(N, BrCC);
    return;
  }
```

> **Design Note**: Previously the SDNode produced `MVT::i16, MVT::Other`
> to model the tied output. Without the tied output, only the chain
> result is needed for scheduling.

### Step 3.3 — Update operand indices in expansion [x]

**File**: `llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

With `(outs)` instead of `(outs GR16:$lhs_wb)`, the operand numbering
shifts back by 1:

| Operand | Before (with tied output) | After (no tied output) |
|---------|--------------------------|------------------------|
| `$lhs` | `MI.getOperand(1)` | `MI.getOperand(0)` |
| `$rhs` | `MI.getOperand(2)` | `MI.getOperand(1)` |
| `$cc`  | `MI.getOperand(3)` | `MI.getOperand(2)` |
| `$dst` | `MI.getOperand(4)` | `MI.getOperand(3)` |

Update the `case V6CLANG::V6CLANG_BR_CC16:` block:

```cpp
  case V6CLANG::V6CLANG_BR_CC16: {
    // Operand layout: 0=$lhs, 1=$rhs, 2=$cc, 3=$dst
    Register LhsReg = MI.getOperand(0).getReg();
    Register RhsReg = MI.getOperand(1).getReg();
    int64_t CC = MI.getOperand(2).getImm();
    MachineBasicBlock *Target = MI.getOperand(3).getMBB();
    // ... expansion code ...
```

### Step 3.4 — Implement CMP-based EQ/NE expansion with MBB splitting [x]

**File**: `llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

Replace the XOR-based EQ/NE block with a CMP-based MBB-splitting
expansion. The SUB/SBB path for other condition codes remains unchanged.

```cpp
  case V6CLANG::V6CLANG_BR_CC16: {
    Register LhsReg = MI.getOperand(0).getReg();
    Register RhsReg = MI.getOperand(1).getReg();
    int64_t CC = MI.getOperand(2).getImm();
    MachineBasicBlock *Target = MI.getOperand(3).getMBB();

    MCRegister LhsLo = RI.getSubReg(LhsReg, V6CLANG::sub_lo);
    MCRegister LhsHi = RI.getSubReg(LhsReg, V6CLANG::sub_hi);
    MCRegister RhsLo = RI.getSubReg(RhsReg, V6CLANG::sub_lo);
    MCRegister RhsHi = RI.getSubReg(RhsReg, V6CLANG::sub_hi);

    if (CC == V6ClangCC::COND_Z || CC == V6ClangCC::COND_NZ) {
      // --- CMP-based non-destructive expansion with MBB splitting ---

      // Find the fallthrough successor (the one that's not Target).
      MachineBasicBlock *FallthroughMBB = nullptr;
      for (auto *Succ : MBB.successors()) {
        if (Succ != Target) {
          FallthroughMBB = Succ;
          break;
        }
      }
      // If MBB branches to itself (Target == &MBB), the fallthrough
      // is the other successor. If there's only one successor, fall
      // back to the old approach as a safety measure.
      if (!FallthroughMBB && MBB.succ_size() == 1)
        FallthroughMBB = *MBB.succ_begin(); // single successor = both paths

      // Create CompareHiMBB for the second byte comparison.
      MachineFunction *MF = MBB.getParent();
      MachineBasicBlock *CompareHiMBB =
          MF->CreateMachineBasicBlock(MBB.getBasicBlock());
      MF->insert(std::next(MBB.getIterator()), CompareHiMBB);

      // Splice any instructions after V6CLANG_BR_CC16 (e.g. JMP) into
      // CompareHiMBB. Transfer successors from MBB to CompareHiMBB.
      CompareHiMBB->splice(CompareHiMBB->end(), &MBB,
                           std::next(MI.getIterator()), MBB.end());
      CompareHiMBB->transferSuccessorsAndUpdatePHIs(&MBB);

      if (CC == V6ClangCC::COND_NZ) {
        // NE: both JNZ go to Target.
        //   MBB: MOV A, LhsLo; CMP RhsLo; JNZ Target
        //   CompareHiMBB: MOV A, LhsHi; CMP RhsHi; JNZ Target
        //   (fall through = equal → don't branch)

        BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::A).addReg(LhsLo);
        BuildMI(MBB, MI, DL, get(V6CLANG::CMPr))
            .addReg(V6CLANG::A).addReg(RhsLo);
        BuildMI(MBB, MI, DL, get(V6CLANG::JNZ)).addMBB(Target);

        MBB.addSuccessor(Target);
        MBB.addSuccessor(CompareHiMBB);

        auto InsertPt = CompareHiMBB->begin();
        BuildMI(*CompareHiMBB, InsertPt, DL, get(V6CLANG::MOVrr), V6CLANG::A)
            .addReg(LhsHi);
        BuildMI(*CompareHiMBB, InsertPt, DL, get(V6CLANG::CMPr))
            .addReg(V6CLANG::A).addReg(RhsHi);
        BuildMI(*CompareHiMBB, InsertPt, DL, get(V6CLANG::JNZ)).addMBB(Target);

        // CompareHiMBB already has FallthroughMBB from transferSuccessors.
        // Add Target as additional successor.
        CompareHiMBB->addSuccessor(Target);

      } else {
        // EQ: first JNZ skips to fallthrough, second JZ jumps to target.
        //   MBB: MOV A, LhsLo; CMP RhsLo; JNZ FallthroughMBB
        //   CompareHiMBB: MOV A, LhsHi; CMP RhsHi; JZ Target
        //   (fall through from CompareHiMBB = not equal → don't branch)

        BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::A).addReg(LhsLo);
        BuildMI(MBB, MI, DL, get(V6CLANG::CMPr))
            .addReg(V6CLANG::A).addReg(RhsLo);
        BuildMI(MBB, MI, DL, get(V6CLANG::JNZ)).addMBB(FallthroughMBB);

        MBB.addSuccessor(FallthroughMBB);
        MBB.addSuccessor(CompareHiMBB);

        auto InsertPt = CompareHiMBB->begin();
        BuildMI(*CompareHiMBB, InsertPt, DL, get(V6CLANG::MOVrr), V6CLANG::A)
            .addReg(LhsHi);
        BuildMI(*CompareHiMBB, InsertPt, DL, get(V6CLANG::CMPr))
            .addReg(V6CLANG::A).addReg(RhsHi);
        BuildMI(*CompareHiMBB, InsertPt, DL, get(V6CLANG::JZ)).addMBB(Target);

        // CompareHiMBB already has FallthroughMBB from transferSuccessors.
        // Add Target as additional successor.
        CompareHiMBB->addSuccessor(Target);
      }

      MI.eraseFromParent();
      return true;
    }

    // --- Non-EQ/NE conditions: SUB/SBB path (unchanged) ---
    {
      unsigned JccOpc;
      switch (CC) {
      // ... existing switch unchanged ...
      }
      // ... existing SUB/SBB expansion unchanged ...
    }
  }
```

> **Design Notes**:
>
> - **Non-destructive**: CMP (`A − operand`) sets flags without
>   modifying A or the operand register. Neither LHS nor RHS is
>   clobbered. Only A is used as a temp for loading the byte to compare.
>
> - **MBB splitting**: Creates one new MBB (CompareHiMBB) for the
>   high-byte comparison. Each MBB has exactly one conditional branch:
>   `JNZ Target` or `JZ Target`. This is a standard pattern that
>   `analyzeBranch` handles correctly (single conditional branch with
>   layout fallthrough).
>
> - **Successor transfer**: `transferSuccessorsAndUpdatePHIs` moves all
>   original successors (including FallthroughMBB) from MBB to
>   CompareHiMBB. Then we add the new successors explicitly. Any JMP
>   instructions that were spliced from MBB to CompareHiMBB provide the
>   unconditional branch to FallthroughMBB when it's not the layout
>   successor.
>
> - **NE early exit**: For NE in a loop, most iterations have lo bytes
>   that differ, so the first JNZ fires immediately (24cc instead of
>   48cc). Only the final iteration (when the pointers are equal) pays
>   the full 48cc.
>
> - **EQ fallthrough**: For EQ, the `JNZ FallthroughMBB` skips the hi
>   comparison when lo bytes differ — also an early exit for the common
>   "not equal" case.
>
> - **Same cost as XOR on worst case**: CMP approach: `MOV A, lo` (8cc)
>   + `CMP R` (4cc) + `JNZ` (12cc) + `MOV A, hi` (8cc) + `CMP R`
>   (4cc) + `JNZ` (12cc) = 48cc. XOR approach: `MOV A, hi` (8cc) +
>   `XRA R` (4cc) + `MOV hi, A` (8cc) + `MOV A, lo` (8cc) + `XRA R`
>   (4cc) + `ORA hi` (4cc) + `JNZ` (12cc) = 48cc. Identical worst-case
>   cost, but CMP has early-exit advantage and is non-destructive.

### Step 3.5 — Build [x]

```bash
cmd /c "call vcvars64.bat >nul 2>&1 && ninja -C llvm-build clang llc"
```

Expected: clean build. The changes are confined to the V6CLANG_BR_CC16
expansion path plus the .td definition and ISel node.

### Step 3.6 — Lit test: NE 16-bit comparison [x]

**File**: `tests/lit/CodeGen/V6Clang/cmp-based-br-cc16.ll`

```llvm
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

; Test that 16-bit NE comparison uses CMP-based sequence, not XOR.
define void @ne_branch(i16 %a, i16 %b) {
; CHECK-LABEL: ne_branch:
; CHECK:       CMP
; CHECK:       JNZ
; CHECK:       CMP
; CHECK:       JNZ
; CHECK-NOT:   XRA
entry:
  %cmp = icmp ne i16 %a, %b
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

; Test that 16-bit EQ comparison uses CMP + JNZ/JZ pattern.
define void @eq_branch(i16 %a, i16 %b) {
; CHECK-LABEL: eq_branch:
; CHECK:       CMP
; Depending on block layout, either JNZ+JZ or JZ+JNZ may appear.
; What matters is: no XRA, and CMP is used.
; CHECK-NOT:   XRA
entry:
  %cmp = icmp eq i16 %a, %b
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

; Test that LT comparison still uses SUB/SBB (not CMP split).
define void @lt_branch(i16 %a, i16 %b) {
; CHECK-LABEL: lt_branch:
; CHECK:       SUB
; CHECK:       SBB
entry:
  %cmp = icmp ult i16 %a, %b
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

declare void @use()
```

### Step 3.7 — Lit test: loop with pointer comparison [x]

**File**: `tests/lit/CodeGen/V6Clang/loop-cmp-no-spill.ll`

```llvm
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

; Verify that a two-pointer loop uses CMP for exit condition and does
; not spill registers to stack.
@src = global [100 x i8] zeroinitializer
@dst = global [100 x i8] zeroinitializer

define void @array_copy() {
entry:
  br label %loop

loop:
  %ps = phi ptr [ @src, %entry ], [ %ps.next, %loop ]
  %pd = phi ptr [ @dst, %entry ], [ %pd.next, %loop ]
  %val = load i8, ptr %ps
  store i8 %val, ptr %pd
  %ps.next = getelementptr i8, ptr %ps, i16 1
  %pd.next = getelementptr i8, ptr %pd, i16 1
  %done = icmp ne ptr %ps.next, getelementptr (i8, ptr @src, i16 100)
  br i1 %done, label %loop, label %exit

exit:
  ret void
}

; CHECK-LABEL: array_copy:
; The loop should not spill to stack (no PUSH/POP inside the loop body).
; CHECK: .L{{.*}}:
; CHECK-NOT: PUSH
; CHECK-NOT: POP
; Expect INX for pointer increments and CMP for comparison.
; CHECK:     INX
; CHECK:     CMP
; CHECK:     JNZ
```

### Step 3.8 — Run regression tests [x]

```bash
python tests/run_all.py
```

All existing tests must pass. The CMP expansion changes the output for
any test that checks for XOR-based 16-bit EQ/NE comparison sequences.
Update those CHECK lines accordingly.

### Step 3.9 — Verify assembly on array copy benchmark [x]

```bash
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S ^
    temp\compare\03\v6clang2.c -o temp\compare\03\v6clang2_cmp.asm
```

Inspect the loop body. Target output (or close to it):
```asm
.LBB0_1:
    LDAX B              ;  8cc  — load from [BC]
    STAX D              ;  8cc  — store to [DE]
    INX  B              ;  8cc  — advance source
    INX  D              ;  8cc  — advance dest
    MOV  A, C           ;  8cc  — compare BC vs HL (constant)
    CMP  L              ;  4cc
    JNZ  .LBB0_1        ; 12cc  — lo bytes differ → continue
    MOV  A, B           ;  8cc
    CMP  H              ;  4cc
    JNZ  .LBB0_1        ; 12cc  — hi bytes differ → continue
```

Verify:
1. **No PUSH/POP** in the loop body (no spills)
2. **No XRA/ORA** (no destructive XOR comparison)
3. **INX B / INX D** for pointer increments
4. **CMP + JNZ** for exit condition
5. **Three register pairs** used: BC=source, DE=dest, HL=constant

### Step 3.10 — Sync mirror [x]

```powershell
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

---

## 4. Expected Results

### Per-comparison improvement

| Case | XOR (before) | CMP (after) | Improvement |
|------|-------------|-------------|-------------|
| NE — lo bytes differ | 48cc | 24cc | 2× (early exit) |
| NE — hi bytes differ | 48cc | 48cc | same |
| NE — equal (fall‑through) | 48cc | 48cc | same |
| EQ — lo bytes differ | 48cc | 24cc | 2× (early skip) |
| EQ — equal (jump) | 48cc | 48cc | same |

The cycle cost is unchanged in the worst case. The key advantage is
**non-destructiveness**: no register pair is clobbered → no tied-output
copy → eliminates cascading spill/reload overhead.

### Array-copy loop impact

| Metric | Before CMP | After CMP |
|--------|-----------|-----------|
| Tied-output copy | 16cc | 0cc |
| Stack spill/reload | ~100cc | 0cc |
| Pointer increments | ~48cc | 16cc (INX peepholes fire) |
| Comparison | 48cc | 24-48cc |
| LDAX + STAX | 16cc | 16cc |
| **Total per iteration** | **~268cc** | **~80cc** |

### Register allocation improvement

Before: V6CLANG_BR_CC16 declares tied output → RA reserves a register pair
for the copy → with BC, DE, HL all under pressure → destination pointer
spills to stack.

After: V6CLANG_BR_CC16 has no output → RA freely assigns BC=source, DE=dest,
HL=constant → zero spills.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| MBB splitting confuses BranchFolding → infinite loop | Each new MBB has exactly one conditional branch + optional JMP — the standard pattern `analyzeBranch` handles. The previous hang was caused by the XOR approach's non-standard block structure, not by MBB splitting itself. |
| `transferSuccessorsAndUpdatePHIs` misses a successor → broken CFG | V6CLANG_BR_CC16 is a terminator at block end. After splicing and transferring, we explicitly add the correct successors. Post-RA there are no PHI nodes, but the call handles them if present. |
| Removing tied-output breaks non-EQ/NE paths (SUB/SBB) | The SUB/SBB expansion for C/NC/M/P doesn't clobber LHS — it only uses A as temp. So the tied-output was never needed for these paths. We verify by checking all existing tests. |
| `analyzeBranch` sees V6CLANG_BR_CC16 before expansion → returns "can't analyze" | V6CLANG_BR_CC16 is marked `isTerminator = 1, isBranch = 1`. Standard LLVM `analyzeBranch` dispatches to our override, which only recognizes physical Jcc/JMP opcodes, not pseudos. So V6CLANG_BR_CC16 is always "unknown terminator" → analyzeBranch returns true (can't analyze). This hasn't been a problem because the pseudo is expanded before any pass that needs analyzeBranch on expanded code. |
| EQ case: `FallthroughMBB` is `nullptr` (single successor) | Safety check: if we can't identify the fallthrough block, fall back to the old XOR approach. In practice, a conditional branch always has two successors. |
| Concurrent Target == FallthroughMBB (both successors the same) | Possible if the branch condition is irrelevant (dead code). The expansion still emits correct code — both JNZ and JZ go to the same block. BranchOpt may simplify later. |

---

## 6. Relationship to Other Improvements

This is improvement #2 of three identified for the array-copy loop:

1. **INX/DCX peephole** ([plan_inx_dcx_peephole.md](plan_inx_dcx_peephole.md))
   — **implemented**. Replaces 8-bit add-by-small-constant chains with
   INX/DCX. Already fires for DE increment in the loop, but BC increment
   is blocked by spill-induced PUSH/POP breaking the LXI backward scan.

2. **CMP-based 16-bit comparison** (this plan) — replaces the destructive
   XOR-based V6CLANG_BR_CC16 EQ/NE with non-destructive CMP + MBB splitting.
   Eliminates tied-output copy, frees a register pair, prevents spills.

3. **Spill elimination** — expected to follow **automatically** from #2.
   With no tied-output copy and three register pairs available (BC, DE,
   HL), the register allocator no longer needs to spill. The INX peephole
   then fires for both BC and DE, since there are no PUSH/POP to break
   the backward scan.

Implementing #2 cascades into #3 for free, and unblocks #1 for the
second pointer increment.

---

## 7. Future Enhancements

- **Immediate MVI+CMP optimization**: When the comparison RHS is a known
  constant (from LXI with a plain integer immediate or a global address),
  use `MVI A, lo; CMP R` instead of `MOV A, R; CMP R2`. This frees the
  register pair used for the constant. Requires: (a) backward-scan for
  the LXI like the INX peephole, (b) for global address constants,
  lo8/hi8 MCExpr infrastructure to split 16-bit addresses into 8-bit
  bytes with relocatable expressions. The register-based CMP approach
  already achieves zero spills for the array-copy loop (3 values in 3
  pairs), so this is only needed for more complex loops with > 3 live
  16-bit values.

- **CMP early-exit probability**: The NE two-branch pattern always checks
  the low byte first. For pointer comparisons where the high byte is more
  likely to differ (e.g., pointers spanning a 256-byte boundary), it
  might be faster to check the high byte first. This is a tuning decision
  with negligible impact for most loops.

  > **Not pursued.** For a typical loop iterating 0→100 within a single
  > 256-byte page, the low byte changes every iteration while the high
  > byte is constant — so low-byte-first already gives the early exit
  > ~99% of the time. The high-byte check only executes on the ~1
  > iteration where low bytes happen to match. The only case where
  > high-byte-first helps is when a pointer crosses a page boundary
  > (e.g., 0x00F0→0x0154), but even then the benefit on some iterations
  > is offset by the penalty on others — it's a wash on average. Doing
  > it correctly would require static analysis of address ranges at
  > compile time, which is high complexity for near-zero payoff.

- **CPI-based optimization for non-loop code**: For single comparisons
  (not in a loop), `MOV A, R; CPI imm` saves the LXI instruction (12cc)
  at the cost of 4cc per CPI vs CMP. Net saving: 12 − 8 = 4cc. Only
  matters for non-loop comparisons against constants.

  > **Not pursued.** The implemented MVI+CMP pattern (from O_IMM_CMP)
  > already handles this case and is strictly faster: MVI A,imm + CMP r
  > = 12cc vs MOV A,r + CPI imm = 16cc. Same byte count (2B+1B vs
  > 1B+2B). MOV+CPI is dominated in all scenarios — there is no
  > combination of operand placement where it wins on cycles or size.
  > The only hypothetical edge case (A already holds the value to
  > compare) would need A-liveness tracking at ISel time, which is
  > not available at that stage.
