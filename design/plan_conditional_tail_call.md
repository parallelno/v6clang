# Plan: Conditional Tail Call Optimization (O23)

## 1. Problem

### Current behavior

The O14 peephole (`eliminateTailCall` in `V6ClangPeephole.cpp`) converts
`CALL target; RET` → `JMP target` only when both instructions are in the
same basic block. When a conditional branch splits tail-call code into
separate blocks, `CALL` ends one block and `RET` sits alone in its
layout successor — O14 misses it.

```asm
; test_pattern_a: if (x) return bar(x); return 0;
.LBB0_1:
    MOV  H, D        ;  8cc
    MOV  L, E        ;  8cc
    CALL bar         ; 18cc  ← missed tail call
.LBB0_2:
    RET              ; 12cc
```

### Desired behavior

```asm
.LBB0_1:
    MOV  H, D        ;  8cc
    MOV  L, E        ;  8cc
    JMP  bar         ;  4cc  ← tail call
.LBB0_2:
    RET              ; 12cc  (still needed for other paths)
```

### Root cause

`eliminateTailCall` only scans for `CALL; RET` within a single MBB.
When conditional logic places `CALL` at the end of a block that falls
through to a RET-only successor, the pattern spans two blocks and is
not recognized.

---

## 2. Strategy

### Approach: Extend `eliminateTailCall` with cross-block pattern

Add a second pattern to `eliminateTailCall` in `V6ClangPeephole.cpp`:
if the last non-debug instruction in a block is `CALL`, and the block
has exactly one successor that contains only `RET`, replace `CALL`
with `V6CLANG_TAILJMP` and remove the successor edge.

### Why this works

- `CALL` as last instruction means no work is done between the call
  and the fallthrough to `RET` — this IS a tail call.
- The successor block (`RET`-only) may still be reachable from other
  predecessors, so it is not removed — only the edge from the current
  block is dropped.
- `V6CLANG_TAILJMP` is `isReturn=1, isBarrier=1`, so the block no longer
  falls through. The CFG is clean.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Cross-block tail call | Check CALL → RET-only successor | V6ClangPeephole.cpp |
| Lit test | New conditional-tail-call.ll | tests/lit/CodeGen/V6CLANG/ |
| Regression tests | run_all.py | tests/ |
| Feature test | tests/features/07/ | tests/features/ |

---

## 3. Implementation Steps

### Step 3.1 — Extend `eliminateTailCall` with cross-block pattern [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp`

After the existing same-block `CALL; RET` check, add a new pattern:

1. If the last non-debug instruction in the block is `CALL`:
2. Check that the block has exactly one successor.
3. Check that the successor contains only `RET` (plus debug instrs).
4. Replace `CALL` with `V6CLANG_TAILJMP`.
5. Remove the successor edge from the CFG.

> **Design Notes**: The `succ_size() == 1` check is correct because
> `CALL` is not a terminator — if it's the last instruction, the block
> has no terminators and falls through to exactly one successor.
> The RET-only successor may have other predecessors (conditional
> branches that skip to the return), so it stays in the function.

> **Implementation Notes**: Added `isRetOnlyBlock()` helper and Pattern 2
> to `eliminateTailCall()`. Refactored existing Pattern 1 (O14) into the
> same function for clarity. ~40 lines net change.

### Step 3.2 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**:

### Step 3.3 — Lit test: conditional-tail-call.ll [x]

**File**: `tests/lit/CodeGen/V6CLANG/conditional-tail-call.ll`

Test cases:
1. Pattern A: `if (x) return bar(x); return 0;` → CALL→JMP in conditional block
2. Pattern B: `if (x) return 0; return bar(x);` → CALL→JMP in fallthrough block
3. Negative: work after CALL (not a tail call) → keeps CALL+RET

> **Implementation Notes**:

### Step 3.4 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**:

### Step 3.5 — Verification assembly steps from `tests\features\README.md` [x]

Compile `tests\features\07\v6clang.c` to `v6clang_new01.asm` and verify
that the `CALL` instructions in conditional paths are converted to `JMP`.

> **Implementation Notes**:

### Step 3.6 — Make sure result.txt is created. `tests\features\README.md` [x]

> **Implementation Notes**:

### Step 3.7 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**:

---

## 4. Expected Results

### Example 1: test_pattern_a — conditional tail call

```asm
; Before                      ; After
.LBB0_1:                      .LBB0_1:
    MOV  H, D  ;  8cc             MOV  H, D  ;  8cc
    MOV  L, E  ;  8cc             MOV  L, E  ;  8cc
    CALL bar   ; 18cc             JMP  bar    ;  4cc  ← saved 14cc
.LBB0_2:                      .LBB0_2:
    RET        ; 12cc             RET         ; 12cc
```

**Savings**: 14cc per call through this path, same code size.

### Example 2: test_pattern_b — fallthrough tail call

```asm
; Before                      ; After
; %bb.1:                      ; %bb.1:
    CALL bar   ; 18cc             JMP  bar    ;  4cc  ← saved 14cc
.LBB1_2:                      .LBB1_2:
    RET        ; 12cc             RET         ; 12cc
```

**Savings**: 14cc per call through this path.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Removing successor edge corrupts CFG | Only remove edge when CALL is replaced with V6CLANG_TAILJMP (barrier/return) |
| RET-only block removed prematurely | We don't remove it — other predecessors keep it alive; BranchOpt handles dead blocks |
| False match on non-tail CALL | Only matches when CALL is the very last non-debug instruction — no work after the call |

---

## 6. Relationship to Other Improvements

- **O14** (Tail Call Optimization): This is a direct extension. O14 handles
  same-block `CALL; RET`; O23 handles cross-block `CALL` → fallthrough to
  `RET`-only successor.
- **O15** (Conditional Call): O15 converts `Jcc+CALL → Ccc` (conditional
  call instruction). O23 and O15 are complementary — O23 handles the tail
  call case, O15 handles the non-tail-call case.

## 7. Future Enhancements

- **ISel-level tail call recognition**: `LowerTailCall()` in
  `V6ClangISelLowering.cpp` could catch tail calls earlier in the pipeline,
  enabling cases where arguments need shuffling.
- **Sibling calls**: Tail calls to functions with identical argument
  signatures could skip frame setup entirely.

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O23 Feature Description](design\future_plans\O23_conditional_tail_call.md)
* [O14 Plan](design\plan_tail_call_optimization.md)
* [Existing tail call lit test](tests\lit\CodeGen\V6CLANG\tail-call-opt.ll)
