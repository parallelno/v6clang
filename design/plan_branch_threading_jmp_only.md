# Plan: Branch Threading Through JMP-Only Blocks (O28)

## 1. Problem

### Current behavior

When a conditional branch targets a basic block that contains only an
unconditional `JMP`, the backend emits the Jcc to the intermediate
block, which then unconditionally jumps to the final target. This
wastes 3 bytes and 12cc for the intermediate JMP instruction.

```asm
; BB0:
    MOV  A, H
    ORA  L
    JNZ  .LBB1         ; 3B 12cc — conditional branch to JMP-only block
    ; fall through to BB2
; BB1:
    JMP  bar            ; 3B 12cc — only instruction in block (tail call)
; BB2:
    LXI  HL, 0
    RET
```

### Desired behavior

```asm
; BB0:
    MOV  A, H
    ORA  L
    JNZ  bar            ; 3B 12cc — redirect directly to tail call target
    ; fall through to BB2
; BB2:
    LXI  HL, 0
    RET
; BB1 removed (dead code, no predecessors)
```

### Root cause

The existing `V6ClangBranchOpt` pass handles Jcc+JMP pairs within the
**same block** (via `invertConditionalBranch`), but does not look
across block boundaries. When a conditional branch targets a separate
block whose only content is a `JMP`, the indirection persists.

This pattern appears frequently after tail call optimization (O14/O23)
creates JMP-only blocks for tail calls.

---

## 2. Strategy

### Approach: Add `threadJMPOnlyBlocks()` to V6ClangBranchOpt

Add a new method to scan all branches (both conditional and
unconditional). If a branch targets a block containing exactly one
instruction — a `JMP` to an MBB — redirect the branch directly to
the JMP's final target and update CFG edges.

### Why this works

1. **Conservative**: Only threads through blocks with exactly 1
   instruction (JMP to MBB). No risk of changing semantics.
2. **CFG correctness**: `MBB.replaceSuccessor()` updates successor
   lists atomically. Dead blocks are cleaned up by the existing
   `removeDeadBlocks()` pass.
3. **No register/flag effects**: JMP has no side effects — redirecting
   past it is always safe.

### Run order within V6ClangBranchOpt::runOnMachineFunction

```
threadJMPOnlyBlocks      ← NEW: redirect branches through JMP-only blocks
invertConditionalBranch  — may fire on exposed patterns after threading
removeRedundantJMP       — cleans up fall-through JMPs
foldConditionalReturns   — Jcc→RET becomes Rcc
removeDeadBlocks         — removes orphaned JMP-only blocks
```

Threading first maximizes opportunities for later passes: after
redirecting a Jcc past a JMP-only block, the inversion or fallthrough
removal may become applicable.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Add threadJMPOnlyBlocks | Redirect branches past JMP-only blocks | V6ClangBranchOpt.cpp |
| Wire into runOnMachineFunction | Call before invertConditionalBranch | V6ClangBranchOpt.cpp |
| Lit test | branch-threading.ll | tests/lit/CodeGen/V6CLANG/ |
| Regression tests | run_all.py | tests/ |
| Feature test | tests/features/13/ | tests/features/ |

---

## 3. Implementation Steps

### Step 3.1 — Add `threadJMPOnlyBlocks()` to V6ClangBranchOpt.cpp [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangBranchOpt.cpp`

Add `threadJMPOnlyBlocks` method declaration to the class and implement it.
Update `runOnMachineFunction` to call it before `invertConditionalBranch`.
Update the file header comment to list optimization #5.

```cpp
/// Thread conditional/unconditional branches through JMP-only successor blocks.
/// If a branch targets a block whose only instruction is JMP target,
/// redirect the branch to target directly.
bool V6ClangBranchOpt::threadJMPOnlyBlocks(MachineFunction &MF) {
  bool Changed = false;

  for (MachineBasicBlock &MBB : MF) {
    for (MachineInstr &MI : MBB.terminators()) {
      // Must be a branch to an MBB (Jcc or JMP).
      if (MI.getOpcode() != V6CLANG::JMP && !getInvertedJcc(MI.getOpcode()))
        continue;
      if (!MI.getOperand(0).isMBB())
        continue;

      MachineBasicBlock *Target = MI.getOperand(0).getMBB();

      // Check if Target is a JMP-only block (exactly 1 non-debug instruction).
      MachineBasicBlock::iterator FirstNonDbg = Target->getFirstNonDebugInstr();
      if (FirstNonDbg == Target->end())
        continue;
      if (FirstNonDbg->getOpcode() != V6CLANG::JMP)
        continue;
      if (!FirstNonDbg->getOperand(0).isMBB())
        continue;
      // Verify it's the only non-debug instruction.
      MachineBasicBlock::iterator Next = std::next(FirstNonDbg);
      while (Next != Target->end() && Next->isDebugInstr())
        ++Next;
      if (Next != Target->end())
        continue;

      // Redirect our branch to the JMP's final target.
      MachineBasicBlock *FinalTarget = FirstNonDbg->getOperand(0).getMBB();
      MI.getOperand(0).setMBB(FinalTarget);

      // Update CFG edges.
      MBB.replaceSuccessor(Target, FinalTarget);
      Changed = true;
    }
  }

  return Changed;
}
```

> **Design Notes**: Uses `getFirstNonDebugInstr()` and skips debug instrs
> after the JMP to be robust with `-g` builds. The `replaceSuccessor` call
> handles the case where FinalTarget is already a successor (merges edges).
> The `getInvertedJcc` check identifies all 8 conditional branch opcodes.
> **Implementation Notes**: Added `threadJMPOnlyBlocks()` method (~40 lines) that handles both
> `V6CLANG::JMP` (intra-function) and `V6CLANG::V6CLANG_TAILJMP` (tail call) in target blocks.
> For MBB targets: uses `setMBB()` + `replaceSuccessor()`. For non-MBB targets
> (global address, external symbol): uses `ChangeToGA()`/`ChangeToES()`/`ChangeToMCSymbol()`
> + `removeSuccessor()`. Also extended `invertConditionalBranch` to handle V6CLANG_TAILJMP
> (Jcc + V6CLANG_TAILJMP in same block → inverted Jcc with tail-call target).
> Added `isMBB()` guards to `removeRedundantJMP`, `invertConditionalBranch`, and
> `foldConditionalReturns` to handle non-MBB branch operands created by threading.
> Updated file header comment to list optimization #5 (branch threading).
> Wired into `runOnMachineFunction` as first pass (before invertConditionalBranch).

### Step 3.2 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Clean build, 4 targets rebuilt. Three iterations:

### Step 3.3 — Lit test: branch-threading.ll [x]

**File**: `tests/lit/CodeGen/V6CLANG/branch-threading.ll`

Test cases:
1. Conditional branch to JMP-only block → redirected to final target
2. Negative test: non-JMP-only block → no threading
3. Pass disabled → no threading

> **Implementation Notes**: 2 test functions: `test_thread_tailcall` (JNZ bar from
> threading through V6CLANG_TAILJMP-only block, with DISABLED check for JNZ .LBB),
> `test_no_thread` (negative: non-JMP-only block not threaded).
> Also updated 2 existing lit tests: tail-call-opt.ll (dispatch: JMP func_b → JNZ func_b
> from V6CLANG_TAILJMP inversion), conditional-tail-call.ll (cond_tail_b: JMP bar → JZ bar
> from threading).

### Step 3.4 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: 88/88 lit + 15/15 golden all pass.

### Step 3.5 — Verification assembly steps from `tests\features\README.md` [x]

Compile `tests\features\13\v6clang.c` to `v6clang_new01.asm` and verify
that conditional branches through JMP-only blocks are threaded.

> **Implementation Notes**: v6clang_new01.asm confirms: test_cond_zero_tailcall
> 15B→11B (JZ .LBB → JZ bar, eliminating JMP-only block — 3B 12cc saved).
> test_simple_tailcall already optimal via O30+O14. test_two_cond_tailcall
> uses CALL (not tail call) so threading doesn't apply.

### Step 3.6 — Make sure result.txt is created. `tests\features\README.md` [x]

> **Implementation Notes**: result.txt created with c8080 vs v6clang comparison.
> Overall: 60B (c8080) vs 36B (v6clang) = 40% smaller.

### Step 3.7 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Mirror sync complete.

---

## 4. Expected Results

### Example 1: Conditional tail call threading

Before:
```asm
test_pattern_a:
    MOV  A, H           ; 1B  8cc
    ORA  L              ; 1B  4cc
    JNZ  .LBB0_1        ; 3B 12cc — branch to JMP-only block
    LXI  HL, 0          ; 3B 12cc
    RET                 ; 1B 12cc
.LBB0_1:
    JMP  bar            ; 3B 12cc — tail call (only instruction)
```
Total: 12B, 60cc (taken path)

After:
```asm
test_pattern_a:
    MOV  A, H           ; 1B  8cc
    ORA  L              ; 1B  4cc
    JNZ  bar            ; 3B 12cc — directly to tail call target
    LXI  HL, 0          ; 3B 12cc
    RET                 ; 1B 12cc
; .LBB0_1 removed by dead block removal
```
Total: 9B, 48cc (taken path). Savings: **3B, 12cc**.

### Example 2: JMP chain threading

Before:
```asm
.LBB0_1:
    JMP  .LBB0_2       ; 3B 12cc
.LBB0_2:
    JMP  final_target   ; 3B 12cc
```

After:
```asm
.LBB0_1:
    JMP  final_target   ; 3B 12cc — direct
; .LBB0_2 removed if no other predecessors
```
Savings: **3B, 12cc** when the intermediate block is eliminated.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Infinite threading loop (A→B→A) | Only threads JMP-only blocks; a JMP-only block targeting itself would be an infinite loop in the original code too. The pattern is impossible in well-formed IR. |
| Successor list corruption | Uses `replaceSuccessor()` which handles duplicates. |
| Dead blocks left behind | Existing `removeDeadBlocks()` handles cleanup. |

---

## 6. Relationship to Other Improvements

- **O14/O23** (tail calls): Create JMP-only blocks (tail call targets)
  that are the primary beneficiaries of this optimization.
- **O27** (i16 zero-test): Creates compact conditional branches that
  frequently target tail-call JMP-only blocks.
- **O30** (conditional return): Runs after threading — may further
  simplify patterns exposed by threading.
- **O31** (dead PHI constant elimination): Reduces blocks, creating
  more JMP-only patterns.

---

## 7. Future Enhancements

- **Multi-level threading**: Thread through chains of JMP-only blocks
  (A→B→C where both B and C are JMP-only). Current single-pass handles
  one level; iterating would handle deeper chains.
- **Conditional return through JMP-only blocks**: If a Jcc targets a
  JMP-only block whose JMP targets a RET-only block, could directly
  emit Rcc. Currently requires two separate passes (threading + return
  folding).

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O28 Design](design\future_plans\O28_branch_threading_jmp_only.md)
* [V6ClangBranchOpt.cpp](llvm-project\llvm\lib\Target\V6CLANG\V6ClangBranchOpt.cpp)
