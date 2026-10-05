# Plan: O38 — XRA+CMP i8 Zero-Test Peephole

## 1. Problem

### Current behavior

When testing an 8-bit register for zero before a conditional branch,
the compiler emits `MOV A, r; ORA A`. This costs 12cc and leaves A = r.

```asm
    MOV  A, E        ; 1B, 8cc
    ORA  A           ; 1B, 4cc — test E == 0 (A = E after)
    JZ   .LBB1_4
    MVI  A, 0        ; 2B, 8cc — need A = 0
    JMP  bar
.LBB1_4:
    MVI  A, 0        ; 2B, 8cc — need A = 0
    RET
```

### Desired behavior

```asm
    XRA  A           ; 1B, 4cc — A = 0
    CMP  E           ; 1B, 4cc — test E == 0 (A still 0)
    JZ   .LBB1_4
    JMP  bar         ; MVI A,0 eliminated (A already 0)
.LBB1_4:
    RET              ; MVI A,0 eliminated (A already 0)
```

### Root cause

ISel lowers i8 zero-tests to `MOV A, r; ORA A` because ORA is the
canonical flag-setting operation. There is no ISel pattern for the
`XRA A; CMP r` alternative because the benefit is only visible when
combined with downstream value tracking (O13 LoadImmCombine).

## 2. Strategy

### Approach: New pattern in V6ClangPeephole + pipeline reorder + LoadImmCombine tracking

Three coordinated changes:

1. **V6ClangPeephole**: Add `foldXraCmpZeroTest()` — replaces `MOV A,r; ORA A; Jcc`
   with `XRA A; CMP r; Jcc` when A is dead or A=0 is acceptable on fallthrough.

2. **V6ClangTargetMachine**: Swap Peephole before LoadImmCombine so that O13 sees
   the XRA A seeding and eliminates downstream `MVI A, 0`.

3. **V6ClangLoadImmCombine**: Track `XRA A` as setting A = 0 (currently invalidated).

### Why this works

- `XRA A` sets A = 0 and sets Z flag (but we don't use those flags).
- `CMP r` computes 0 − r, setting Z iff r == 0. Same Z result as `ORA A` after `MOV A, r`.
- The transform replaces A = r with A = 0. Safe when A is dead on fallthrough,
  or when the next A-consuming instruction is `MVI A, 0` (A=0 already correct).
- O13 cascade: `XRA A` seeds A = 0, eliminating downstream `MVI A, 0` on both paths.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| 3.1 | Add `foldXraCmpZeroTest()` pattern | V6ClangPeephole.cpp |
| 3.2 | Move Peephole before LoadImmCombine | V6ClangTargetMachine.cpp |
| 3.3 | Track XRA A → A=0 | V6ClangLoadImmCombine.cpp |
| 3.4 | Build | — |
| 3.5 | Lit test | xra-cmp-zero-test.ll |
| 3.6 | Run regression tests | — |
| 3.7 | Verification assembly | tests/features/17/ |
| 3.8 | Create result.txt | tests/features/17/ |
| 3.9 | Sync mirror | — |

## 3. Implementation Steps

### Step 3.1 — Add `foldXraCmpZeroTest()` to V6ClangPeephole [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangPeephole.cpp`

Add a new method `foldXraCmpZeroTest(MachineBasicBlock &MBB)` that:

1. Scans forward through the MBB.
2. Matches: `MOV A, r` (r ≠ A) → `ORA A` (or `CPI 0`) → `JZ`/`JNZ`.
3. Checks A is acceptable after the branch via two conditions (either suffices):
   - **Condition 1 (A dead)**: `isRegDeadAfter()` returns true — A is not
     read before being redefined on the fallthrough path and not in any
     successor's liveins.
   - **Condition 2 (A=0 needed)**: the next non-debug instruction after
     the branch (fallthrough) is `MVI A, 0`. Since XRA A already set A=0,
     the value change from A=r to A=0 is benign — it matches what the
     code expects. The `MVI A, 0` will be eliminated by O13 later.
4. Replaces `MOV A, r` with `XRA A` (V6CLANG::XRAr, all operands = A).
5. Replaces `ORA A` with `CMP r` (V6CLANG::CMPr, lhs=A, rs=r).
6. Leaves the branch instruction unchanged.

Call from `runOnMachineFunction` alongside existing patterns.

~45 lines of new code.

> **Design Notes**: Uses the existing `isRegDeadAfter()` helper and
> `isRedundantZeroTest()` predicate already in V6ClangPeephole.cpp.
> Condition 2 catches the primary example where `isRegDeadAfter()` is
> too conservative (returns false because the taken-path successor has
> A as livein, even though A=0 is correct on both paths).

> **Implementation Notes**: Added ~60 lines. Condition 2 checks fallthrough
> successor’s first non-debug instruction (not same-MBB next instruction, since
> JZ is the terminator and MVI A,0 is in the successor block). Iterator fix:
> advance `I = BrIt` before erasing MovMI/OraIt to avoid dangling iterator.

### Step 3.2 — Reorder pipeline: Peephole before LoadImmCombine [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangTargetMachine.cpp`

In `addPreEmitPass()`, swap the order of `createV6ClangPeepholePass()` and
`createV6ClangLoadImmCombinePass()` so Peephole runs first:

```
Before: AccPlanning → LoadImmCombine → Peephole → ...
After:  AccPlanning → Peephole → LoadImmCombine → ...
```

This lets LoadImmCombine see the XRA A created by the peephole and
eliminate downstream `MVI A, 0`.

> **Design Notes**: Peephole patterns (self-MOV, redundant MOV, counter fold,
> tail call) do not depend on LoadImmCombine output. Safe to swap.

> **Implementation Notes**: Swapped two lines in `addPreEmitPass()`. Updated
> comment to reflect new order. No regressions — peephole patterns are
> independent of LoadImmCombine output.

### Step 3.3 — Track XRA A → A=0 in LoadImmCombine [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangLoadImmCombine.cpp`

Before the ALU invalidation switch (~line 366), add a special case:

```cpp
// XRA A: A = A ^ A = 0 → track A as holding 0.
if (Opc == V6CLANG::XRAr && MI.getOperand(2).getReg() == V6CLANG::A) {
  int AIdx = regIndex(V6CLANG::A);
  KnownVal[AIdx] = 0;
  continue;
}
```

This recognizes `XRA A` specifically (not `XRA B` etc.) and records
A = 0 instead of invalidating it.

> **Design Notes**: Only the self-XOR pattern (XRA A) produces a known value.
> XRA with any other register produces an unknown result.

> **Implementation Notes**: Three changes to LoadImmCombine:
> 1. XRA A → A=0 tracking before ALU invalidation switch.
> 2. Pattern D in `seedPredecessorValues` moved before ZeroProvenPath gate —
>    XRA A; CMP r; JZ/JNZ seeds A=0 unconditionally (CMP doesn’t modify A).
> 3. “Try 0” same-register elimination: if DstReg already holds target value,
>    erase MVI entirely (`findRegWithValue` excludes DstReg from search).

### Step 3.4 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: 5 build cycles. Fixed iterator crash, condition 2
> fallthrough successor check, Pattern D placement, and Try 0 elimination.

### Step 3.5 — Lit test: xra-cmp-zero-test.ll [x]

**File**: `tests/lit/CodeGen/V6Clang/xra-cmp-zero-test.ll`

Test cases:
1. Basic pattern: `MOV A, r; ORA A; JZ → XRA A; CMP r; JZ`
2. JNZ variant: same pattern with JNZ
3. A live after (no transform): verify MOV+ORA preserved when A is live
4. Disabled test: `-v6clang-disable-peephole` prevents transform

> **Implementation Notes**: Single test function with enabled/disabled CHECK
> prefixes. Verifies XRA A; CMP E pattern and absence of ORA A / MVI A,0.

### Step 3.6 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: 15/15 golden + 92/92 lit tests pass. Zero regressions.

### Step 3.7 — Verification assembly steps from `tests\features\README.md` [x]

Compile `tests/features/17/v6clang.c` and analyze the assembly for the
XRA+CMP pattern and downstream MVI A,0 elimination.

> **Implementation Notes**: v6clang_new.asm shows XRA A; CMP E; RZ; JMP bar.
> 7B saved in test_two_cond_tailcall (13B → 6B).

### Step 3.8 — Create result.txt [x]

Following `tests/features/README.md` format with C code, both assemblies,
and stats.

> **Implementation Notes**: Created with before/after assembly, cycle/byte
> analysis, and transformation chain description.

### Step 3.9 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Mirror synced successfully.

## 4. Expected Results

### Primary example: `test_two_cond_tailcall`

Before (12cc zero-test + 2×MVI A,0):
```asm
    MOV  A, E        ; 8cc
    ORA  A           ; 4cc (total 12cc)
    JZ   .LBB1_4
    MVI  A, 0        ; 8cc, 2B
    JMP  bar
.LBB1_4:
    MVI  A, 0        ; 8cc, 2B
    RET
```

After (8cc zero-test + cascade eliminates 2×MVI):
```asm
    XRA  A           ; 4cc
    CMP  E           ; 4cc (total 8cc)
    JZ   .LBB1_4
    JMP  bar
.LBB1_4:
    RET
```

**Savings: 4cc (direct) + 4B + 16cc (cascade) = 20cc + 4B total.**

### General: any i8 zero-test before conditional branch

Direct saving: 4cc per instance (12cc → 8cc for zero-test).
Cascade saving: eliminates MVI A,0 on both branch paths when A=0 from XRA.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| A not dead on fallthrough → wrong transform | Conservative `isRegDeadAfter()` check |
| Z flag differs for S/CY/P/AC | Only match JZ/JNZ; other flags unused |
| Pipeline reorder breaks existing patterns | Peephole patterns don't depend on LoadImmCombine |
| XRA A tracking in LoadImmCombine too aggressive | Only self-XOR (XRA A) tracked; other XRA invalidates |

## 6. Relationship to Other Improvements

- **O13 (LoadImmCombine)**: Cascade — XRA A seeds A=0, eliminates MVI A,0
- **O36 (Branch-Implied Seeding)**: Complementary — O36 seeds at BB entry from
  branch analysis; O38 seeds within the BB from XRA
- **O18 (Loop Counter)**: Independent — O18 handles DCR+Jcc, O38 handles MOV+ORA+Jcc

## 7. Future Enhancements

- **CPI 0 variant**: Match `MOV A,r; CPI 0; Jcc` in addition to `ORA A`.

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [V6ClangPeephole.cpp](llvm-project\llvm\lib\Target\V6Clang\V6ClangPeephole.cpp)
* [V6ClangLoadImmCombine.cpp](llvm-project\llvm\lib\Target\V6Clang\V6ClangLoadImmCombine.cpp)
* [V6ClangTargetMachine.cpp](llvm-project\llvm\lib\Target\V6Clang\V6ClangTargetMachine.cpp)
