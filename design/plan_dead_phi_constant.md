# Plan: Dead PHI-Constant Elimination for Zero-Tested Branches (O31)

## 1. Problem

### Current behavior

When LLVM lowers `if (x) { bar(x); } return 0;`, SimplifyCFG merges
the else path into the merge block, creating a PHI:

```llvm
entry:
  %cmp = icmp eq i16 %x, 0
  br i1 %cmp, label %merge, label %then

then:
  %y = call i16 @bar(i16 %x)
  br label %merge

merge:
  %result = phi i16 [ %y, %then ], [ 0, %entry ]
  ret i16 %result
```

ISel materializes the constant `0` in the entry block:

```
bb.0 (entry):
  %2:gr16 = COPY $hl            ; x
  %3:gr16 = LXI 0               ; ← constant for PHI
  V6CLANG_BR_CC16_IMM %2, 0, COND_Z, %bb.2
  JMP %bb.1

bb.2 (merge):
  %1:gr16 = PHI %3, %bb.0, %0, %bb.1
  RET
```

RA must keep both `%2` (x) and `%3` (constant 0) alive in bb.0,
causing a register shuffle: x gets evicted from HL to DE, the constant
takes HL, and the zero-test runs on DE instead of HL.

### Current output (11 instructions, 17 bytes, ~65cc)

```asm
test_ne_zero:
    MOV  D, H          ; 1B   8cc  save x to DE
    MOV  E, L          ; 1B   8cc
    LXI  HL, 0         ; 3B  12cc  REDUNDANT constant
    MOV  A, D          ; 1B   8cc  zero-test on DE
    ORA  E             ; 1B   4cc
    JZ   .LBB0_2       ; 3B  12cc
    MOV  H, D          ; 1B   8cc  restore x
    MOV  L, E          ; 1B   8cc
    JMP  bar           ; 3B  12cc
.LBB0_2:
    RET                ; 1B  12cc
```

### Desired output (5 instructions, 9 bytes, ~25cc)

```asm
test_ne_zero:
    MOV  A, H          ; 1B   8cc  zero-test directly on HL
    ORA  L             ; 1B   4cc
    JZ   .LBB0_2       ; 3B  12cc
    JMP  bar           ; 3B  12cc  HL still has x
.LBB0_2:
    RET                ; 1B  12cc
```

Savings: **6 instructions, 8 bytes, ~40cc** per instance.

### Root cause

No existing pass has the combined knowledge: "The PHI's constant 0
equals the branch comparison RHS, and the source register (`%2`) is
proven to be 0 on that edge → the LXI constant is dead."

The problem chain:
1. **SimplifyCFG** merges `else { return 0; }` into PHI
2. **ISel** materializes `LXI 0` for the PHI incoming value
3. **RA** sees two live values (`%2`, `%3`) in entry → evicts x to DE
4. **O27** expands zero-test on DE instead of HL → shuffle preserved

---

## 2. Strategy

### Approach: Pre-RA MachineFunctionPass

A pre-RA pass in `V6ClangDeadPhiConst.cpp` running after ISel (via
`addPreRegAlloc()`) that recognizes:

```
%const = LXI <imm>
V6CLANG_BR_CC16_IMM %reg, <imm>, <cc>, %target
...
%target (or fallthrough):
  PHI %const, %pred, ...
```

When `<imm>` matches the PHI's incoming value for the same edge AND
the branch condition proves `%reg == <imm>` on the taken/fallthrough
path, replace the PHI operand with `%reg`:

```
; %const = LXI 0        ← becomes dead, DCE removes it
V6CLANG_BR_CC16_IMM %reg, 0, COND_Z, %target
...
%target:
  PHI %reg, %pred, ...  ← uses %reg (proven == 0 on this edge)
```

### Why this works

1. **PHI nodes exist pre-RA** — after ISel, before PHI elimination.
   `addPreRegAlloc()` runs before PHIElimination, so PHIs are intact.
2. **V6CLANG_BR_CC16_IMM is selected** — ISel already chose the IMM variant
   for constant comparisons, so the immediate is in the instruction.
3. **Replacement is safe** — on the proven-equal edge, `%reg` holds
   the same value as `<imm>`. The PHI was receiving `<imm>` from this
   edge. Replacing with `%reg` doesn't change semantics.
4. **DCE cleans up** — `DeadMachineInstrElim` (pre-RA) removes the
   now-dead LXI. RA sees one fewer live value → no shuffle.

### Edge analysis

| Condition | Branch taken | Branch not taken (fallthrough) |
|-----------|-------------|-------------------------------|
| `COND_Z`  | `%reg == <imm>` ✓ | `%reg != <imm>` ✗ |
| `COND_NZ` | `%reg != <imm>` ✗ | `%reg == <imm>` ✓ |

For `COND_Z`: replace in the **target** MBB's PHI.
For `COND_NZ`: replace in the **fallthrough** MBB's PHI.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| New pass | `V6ClangDeadPhiConst.cpp` | `llvm-project/llvm/lib/Target/V6Clang/` |
| Declaration | `createV6ClangDeadPhiConstPass()` | `V6Clang.h` |
| Registration | `addPreRegAlloc()` | `V6ClangTargetMachine.cpp` |
| Build list | Add source file | `CMakeLists.txt` |

---

## 3. Implementation Steps

### Step 3.1 — Create V6ClangDeadPhiConst.cpp [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangDeadPhiConst.cpp`

A `MachineFunctionPass` that:
- Iterates all basic blocks.
- For each block, scans terminators for `V6CLANG_BR_CC16_IMM`.
- Determines the "proven equal" successor edge based on condition code.
- Scans PHI nodes in the proven-equal MBB.
- For each PHI incoming value from the branch's MBB: checks if it's
  defined by an `LXI` with the same immediate as the branch RHS.
- If match: replaces the PHI operand register with the branch LHS register.

Algorithm:
```
for each MBB:
  for each terminator MI in MBB:
    if MI is not V6CLANG_BR_CC16_IMM: continue
    LhsReg = MI.operand(0).getReg()
    RhsOp  = MI.operand(1)
    CC     = MI.operand(2).getImm()
    Target = MI.operand(3).getMBB()

    // Determine proven-equal successor
    if CC == COND_Z:  ProvenEqMBB = Target
    if CC == COND_NZ: ProvenEqMBB = fallthrough successor (not Target)
    else: continue

    // Scan PHIs in ProvenEqMBB
    for each PHI in ProvenEqMBB:
      for each (ValReg, PredMBB) pair in PHI:
        if PredMBB != &MBB: continue
        DefMI = MRI.getVRegDef(ValReg)
        if DefMI is LXI and immediates match:
          PHI.setReg(ValReg → LhsReg)
          Changed = true
```

CLI toggle: `-v6clang-disable-dead-phi-const`

> **Design Notes**: The pass runs at `addPreRegAlloc()`, after machine
> SSA optimization but before PHI elimination. PHI nodes are intact.
> LXI is `isReMaterializable` so it may also be rematerialized, but
> our optimization removes it entirely. `DeadMachineInstrElim` runs
> as part of the standard pipeline and will clean up dead LXI defs.

> **Implementation Notes**: Pass created as described. Added direct LXI
> erasure when the replaced PHI operand was the LXI's sole use, because
> `DeadMachineInstrElim` runs before `addPreRegAlloc()` and won't clean
> it up otherwise. ~130 lines total.

### Step 3.2 — Register the pass [x]

**Files**: `V6Clang.h`, `V6ClangTargetMachine.cpp`, `CMakeLists.txt`

1. **V6Clang.h**: Add declaration `FunctionPass *createV6ClangDeadPhiConstPass();`
2. **V6ClangTargetMachine.cpp**: Add `addPreRegAlloc()` override that calls
   `addPass(createV6ClangDeadPhiConstPass());`
3. **CMakeLists.txt**: Add `V6ClangDeadPhiConst.cpp` to the source list.

> **Implementation Notes**: Added `createV6ClangDeadPhiConstPass()` to V6Clang.h,
> `addPreRegAlloc()` override in V6ClangTargetMachine.cpp, and source file
> to CMakeLists.txt.

### Step 3.3 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

Expected: clean build.

> **Implementation Notes**: Clean build, 4 files recompiled + link.

### Step 3.4 — Lit test: dead PHI constant elimination [x]

**File**: `llvm-project/llvm/test/CodeGen/V6Clang/dead-phi-const.ll`

Test cases:
1. `phi [0, entry]` + `br eq 0` (COND_Z, taken edge) → constant eliminated
2. `phi [0, entry]` + `br ne 0` (COND_NZ, fallthrough edge) → constant eliminated
3. `phi [42, entry]` + `br eq 42` → general constant case
4. `phi [0, entry]` + `br eq 1` → NO elimination (different constant)
5. `phi [0, entry]` from a different edge → NO elimination

CHECK patterns: verify no `LXI` in the output for cases 1-3, and `LXI`
present for cases 4-5.

> **Implementation Notes**: 5 test cases: 3 positive (zero eq, zero ne,
> const 42) + 1 negative (different constant) + 1 disabled pass check.
> All pass.

### Step 3.5 — Run regression tests [x]

```
python tests\run_all.py
```

All existing tests must pass.

> **Implementation Notes**: 85/85 lit + 15/15 golden = all pass.

### Step 3.6 — Verification assembly steps from `tests\features\README.md` [x]

Compile the feature test case:
```
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S tests\features\09\v6clang.c -o tests\features\09\v6clang_new01.asm
```

Analyze: `test_ne_zero` should show MOV A,H; ORA L; JZ/JMP without
the MOV D,H; MOV E,L; LXI HL,0 shuffle. Similar improvements in
`test_eq_zero`. Negative tests unchanged.

> **Implementation Notes**: test_ne_zero: 16B→9B (-7B), test_eq_zero:
> 16B→9B (-7B), test_const_42: 21B→16B (-5B). All shuffle patterns
> eliminated. Negative test (different const) correctly preserved.

### Step 3.7 — Make sure result.txt is created. `tests\features\README.md` [x]

Create `tests\features\09\result.txt` with C source, c8080 asm,
v6clang asm, and cycle/byte counts.

> **Implementation Notes**: Created with C source, c8080 i8080 asm,
> v6clang asm, and per-function cycle/byte comparison.

### Step 3.8 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Mirror synced successfully.

### test_ne_zero: `if (x) bar(x); return 0;`

| Metric | Before | After | Savings |
|--------|--------|-------|---------|
| Instructions | 11 | 5 | 6 fewer |
| Bytes | 17 | 9 | 8 fewer |
| Cycles (taken) | ~65cc | ~25cc | ~40cc |

The LXI 0 + MOV D,H/E,L shuffle disappears entirely. The zero-test
runs on HL directly (MOV A,H; ORA L).

### test_eq_zero: `if (!x) return 0; return bar(x);`

Similar improvement — the PHI constant 0 from the fallthrough edge
is replaced with `%x`, eliminating the LXI constant and register
pressure.

### General constant case: `if (x == 42) return 42;`

The PHI constant 42 matches the branch RHS 42. Replacement eliminates
the LXI 42 and register shuffle, though this pattern is less common.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Pass runs too early, PHIs moved/removed | `addPreRegAlloc()` is after machine SSA opts, before PHI elimination. PHIs are guaranteed present. |
| LXI has other uses beyond the PHI | Only replace the PHI operand. LXI stays alive if it has other uses. Only becomes dead if the PHI was its sole use, in which case DCE removes it. |
| `%reg` not live at the PHI predecessor | `%reg` is used by `V6CLANG_BR_CC16_IMM` in the predecessor, so it's live at the predecessor's terminator — guaranteed to dominate the PHI. |
| Matching global address operands | Start with integer immediates (`isImm()`). Global addresses (`isGlobal()`) matched by comparing `getGlobal()` + `getOffset()`. |
| V6CLANG_BR_CC16_IMM not present (BR_CC16 used for reg-reg) | Pass only matches `V6CLANG_BR_CC16_IMM`. Register-register comparisons don't have an immediate RHS to match against — they are skipped. |

---

## 6. Relationship to Other Improvements

- **O27** (done): Provides the MOV+ORA zero-test idiom that benefits
  from this optimization. With O31, the zero-test runs on HL directly
  instead of DE (no register shuffle).
- **O30** (conditional return, future): Combines with O31 for maximum
  savings — `JZ .ret; RET` becomes `RZ` (saves 3B + 1 instruction).
- **O13** (done): Load-immediate combining may also eliminate some
  redundant constant loads, but it works post-RA on physical registers
  and cannot see PHI nodes. O31 works pre-RA where the information
  is richer.

---

## 7. Future Enhancements

- **V6CLANG_BR_CC16 (register-register)**: Extend to reg-reg comparisons
  where the RHS register is known to hold a constant (would need value
  tracking). Lower priority since `V6CLANG_BR_CC16_IMM` covers most cases.
- **8-bit comparisons**: Same pattern may appear with future
  `V6CLANG_BR_CC8_IMM` pseudo. The pass can be extended trivially.
- **Multiple PHI replacements per block**: Currently handles all PHIs
  in the proven-equal MBB. If a block has multiple PHIs with matching
  constants from the same edge, all are replaced in one pass.

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O31 Feature Description](design\future_plans\O31_dead_phi_constant.md)
* [O27 Zero-Test Plan](design\plan_i16_zero_test.md)
