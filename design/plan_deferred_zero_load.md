# Plan: O37 — Deferred Zero-Load After Zero-Test (Pre-RA Constant Sinking)

## 1. Problem

### Current behavior

When both paths after a zero-test need `HL=0`, ISel hoists
`LXI HL, 0` into the common dominator (before the branch). This
evicts the live value `x` from HL to DE, adding a register shuffle:

```c
int test_cond_zero_return_zero(int x) {
    if (x == 0) return bar(0);
    return 0;
}
```

Current output (11 bytes):
```asm
test_cond_zero_return_zero:
    MOV  D, H          ; 1B, 8cc — save x to DE
    MOV  E, L          ; 1B, 8cc
    LXI  HL, 0         ; 3B, 12cc — hoist: both paths need HL=0
    MOV  A, D          ; 1B, 8cc — zero-test via DE
    ORA  E             ; 1B, 4cc
    JZ   bar           ; 3B, 12cc
    RET                ; 1B, 12cc
```

### Desired behavior

```asm
test_cond_zero_return_zero:
    MOV  A, H          ; 1B, 8cc — zero-test directly on HL
    ORA  L             ; 1B, 4cc
    JZ   bar           ; 3B, 12cc — HL already 0 (branch-proven by O36)
    LXI  HL, 0         ; 3B, 12cc — only needed on NZ path (return 0)
    RET                ; 1B, 12cc
```

Savings: 4 bytes, 16cc (11B → 7B).

### Root cause

ISel materializes `i16 0` once in the common dominator since both
successors use it. This forces HL to be occupied with the constant
before the branch, evicting the live value `x` to DE. The compiler
doesn't realize that on the zero-taken path, HL is already 0 from
the branch condition (O36 handles that later).

The fix must act **before RA** to prevent the conflict. Post-RA fixes
cannot undo register pressure damage already baked in.

---

## 2. Strategy

### Approach: Pre-RA Constant Sinking Pass

A custom `V6ClangConstantSinking` pass that runs **before RA** in
`addPreRegAlloc()`. For each constant materialization (`LXI rp, imm`
or `MVI r, imm`) in a block ending with a conditional branch:

1. Check the vreg def is used only in successor blocks (not between
   the def and the terminator, and its vreg not used by the
   terminator itself)
2. Clone the constant materialization into the start of each successor
   that uses the vreg
3. Update all uses in that successor to refer to the clone's def
4. Erase the original from the dominator

### Why this works

- Pre-RA: operates on virtual registers. No physical register
  conflicts yet — RA will see the shorter live ranges and allocate
  without the eviction.
- RPO iteration: handles nested sinking in a single pass (dominators
  visited before successors).
- After RA, O36 (branch-implied value propagation) eliminates the
  cloned `LXI HL, 0` on the zero-taken path since HL is proven 0.
- Register-agnostic: sinks any LXI/MVI, not just HL.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| New pass file | V6ClangConstantSinking.cpp | llvm-project/llvm/lib/Target/V6CLANG/ |
| Declare factory | createV6ClangConstantSinkingPass() | V6Clang.h |
| Register in pipeline | addPreRegAlloc() before DeadPhiConst | V6ClangTargetMachine.cpp |
| Add to build | CMakeLists.txt | llvm-project/llvm/lib/Target/V6CLANG/ |
| Lit test | constant-sinking.ll | tests/lit/CodeGen/V6CLANG/ |
| Pass toggle | -v6clang-disable-constant-sinking | CLI option |

---

## 3. Implementation Steps

### Step 3.1 — Create V6ClangConstantSinking.cpp [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangConstantSinking.cpp`

Create the pre-RA constant sinking pass. Key logic:

```
For each MBB in RPO:
  For each MI that is LXI or MVI:
    If the MI defines a virtual register:
      DstReg = MI.getOperand(0).getReg()
      Collect all uses of DstReg via MRI.use_instructions()
      If ALL uses are in successor blocks of MBB (none in MBB itself):
        For each successor that has uses:
          Clone MI at the top of the successor (after PHIs/labels)
          Create new vreg, replace all uses in that successor
        Erase original MI
```

Pass structure:
- Inherit `MachineFunctionPass`
- CLI toggle: `-v6clang-disable-constant-sinking`
- RPO iteration via `ReversePostOrderTraversal<MachineFunction*>`
- ~60-80 lines

> **Design Notes**: Use `MachineRegisterInfo::use_instructions()` to
> find all uses of the vreg. Use `MRI.createVirtualRegister()` for
> the cloned def's register. Insert clones after PHIs at successor
> entry (use `getFirstNonPHI()` or `SkipPHIsAndLabels()`).

> **Implementation Notes**: (empty — filled after completion)

### Step 3.2 — Register pass in pipeline and build system [x]

**Files**:
- `llvm-project/llvm/lib/Target/V6CLANG/V6Clang.h` — add declaration
- `llvm-project/llvm/lib/Target/V6CLANG/V6ClangTargetMachine.cpp` — add to `addPreRegAlloc()`
- `llvm-project/llvm/lib/Target/V6CLANG/CMakeLists.txt` — add source file

Add `createV6ClangConstantSinkingPass()` to `addPreRegAlloc()` **after**
`createV6ClangDeadPhiConstPass()` — DeadPhiConst must run first to
eliminate branch-proven constants before sinking moves them.

> **Implementation Notes**: Order reversed during implementation.
> Original plan had sinking first, but DeadPhiConst needs to see
> constants in the dominator to match its pattern. Final order:
> DeadPhiConst → ConstantSinking.

### Step 3.3 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: (empty)

### Step 3.4 — Lit test: constant-sinking.ll [x]

**File**: `tests/lit/CodeGen/V6CLANG/constant-sinking.ll`

Test cases:
1. **LXI sinking (both paths use zero)** — `if (x==0) call(0); return 0;`
   Verify LXI HL,0 is NOT before the branch; appears only in fallthrough.
2. **MVI sinking** — similar with 8-bit constant.
3. **Negative: local use** — constant used between def and branch → not sunk.
4. **Negative: single successor** — no conditional branch → not sunk.
5. **Disabled pass** — `-v6clang-disable-constant-sinking` preserves original.

> **Implementation Notes**: (empty)

### Step 3.5 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: (empty)

### Step 3.6 — Verification assembly steps from `tests\features\README.md` [x]

Compile the feature test case and verify the assembly improvement.

> **Implementation Notes**: (empty)

### Step 3.7 — Make sure result.txt is created. `tests\features\README.md` [x]

> **Implementation Notes**: (empty)

### Step 3.8 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: (empty)

---

## 4. Expected Results

### Example 1: test_cond_zero_return_zero

Before (11B, 64cc):
```asm
    MOV  D, H          ; 1B, 8cc
    MOV  E, L          ; 1B, 8cc
    LXI  HL, 0         ; 3B, 12cc
    MOV  A, D          ; 1B, 8cc
    ORA  E             ; 1B, 4cc
    JZ   bar           ; 3B, 12cc
    RET                ; 1B, 12cc
```

After (7B, 48cc):
```asm
    MOV  A, H          ; 1B, 8cc
    ORA  L             ; 1B, 4cc
    JZ   bar           ; 3B, 12cc
    LXI  HL, 0         ; 3B, 12cc
    RET                ; 1B, 12cc
```

### Example 2: Register pressure relief

The real win is freeing DE before RA. In non-trivial functions, the
avoided eviction prevents 2-3 spills (50-150cc, 6-18B savings).

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Code size increase from cloning into multiple successors | Only fires when constant is used in ≥2 successors; LXI/MVI are `isReMaterializable` so RA can remat anyway |
| Breaking existing lit tests | Run full regression suite after implementation |
| PHI interference from new vreg | Insert clones after all PHIs using `SkipPHIsAndLabels()` |
| Infinite sinking in loops | RPO iteration + "only sink to successors" prevents revisiting |

---

## 6. Relationship to Other Improvements

- **O31 (DeadPhiConst)**: Runs after this pass in `addPreRegAlloc()`. Sinking may create opportunities for DeadPhiConst.
- **O36 (Branch-Implied Value Propagation)**: Post-RA pass that eliminates the cloned `LXI HL, 0` on the zero-taken path. O37 creates the setup that O36 exploits.
- **O13 (LoadImmCombine)**: Post-RA pass with `seedPredecessorValues()`. Already handles the post-RA side; O37 provides the pre-RA enabler.

---

## 7. Future Enhancements

- Add cost-model awareness to decide whether sinking is profitable.

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O37 Design](design\future_plans\O37_deferred_zero_load.md)
* [O36 Design](design\future_plans\O36_redundant_lxi_after_zero_test.md)
