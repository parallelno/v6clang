# Plan: O43-fix — SHLD/LHLD→PUSH/POP Safety Guard

## 1. Problem

### Current behavior

O43 (`foldShldLhldToPushPop` in `V6ClangPeephole.cpp`) replaces adjacent
`SHLD addr` / `LHLD addr` pairs with `PUSH HL` / `POP HL` when they
share the same address and the SP delta between them is zero. However,
the fold replaces a memory writeback (SHLD) with a hardware stack push.
If any other `LHLD addr` in the function depends on that writeback,
it will read stale data.

### Desired behavior

Before folding, verify that no other `LHLD addr` is reachable from the
folded pair without passing through a covering `SHLD addr`. If an
uncovered reader exists, block the fold — the SHLD writeback is needed.

### Root cause

`foldShldLhldToPushPop` only scans forward within the current BB from
the SHLD to find a matching LHLD. It does not check whether the address
is read elsewhere — via loop back-edge, cross-BB path, or earlier in
the same BB.

### Impact

In the `interleaved_add` loop (static stack mode, O16 disabled), O43
folds the `SHLD __v6clang_ss+0` / `LHLD __v6clang_ss+0` pair into `PUSH HL` /
`POP HL`. The `LHLD __v6clang_ss+0` at the top of the loop reads a stale
pointer — the loop processes `src2[0]` every iteration instead of `src2[i]`.

---

## 2. Strategy

### Approach: CFG-aware BFS safety check

Add a helper function `isUncoveredLhldReachable()` that performs a
forward BFS from the folded LHLD through `MBB.successors()`. It checks
if any other `LHLD addr` is reachable without passing through a covering
`SHLD addr`. If so, the fold is blocked.

### Why this works

The fold removes the memory writeback. Any `LHLD addr` that was reading
the value written by the folded SHLD will now read stale data. The BFS
finds exactly those readers by exploring all forward-reachable paths and
stopping propagation at any covering SHLD. If no uncovered LHLD is
found, the fold is safe.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Add safety helper | `isUncoveredLhldReachable()` | V6ClangPeephole.cpp |
| Guard the fold | Call helper before replacing SHLD/LHLD | V6ClangPeephole.cpp |
| Lit test: negative | interleaved_add loop — fold must NOT happen | shld-lhld-push-pop-peephole.ll |
| Regression | Existing sumarray test unchanged — fold still happens | shld-lhld-push-pop-peephole.ll |

---

## 3. Implementation Steps

### Step 3.1 — Add `isUncoveredLhldReachable` helper [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp`

Add a static helper before `foldShldLhldToPushPop`:

```cpp
/// Check if any LHLD of the same address is reachable from AfterD
/// without passing through a covering SHLD. ShldC is the SHLD being
/// folded — it doesn't count as a covering store.
static bool isUncoveredLhldReachable(
    MachineBasicBlock &MBB,
    MachineBasicBlock::iterator AfterD,
    MachineBasicBlock::iterator ShldC,
    const MachineOperand &Addr) {

  // 1. Scan remainder of current BB after the folded LHLD.
  for (auto I = AfterD, E = MBB.end(); I != E; ++I) {
    if (I->getOpcode() == V6CLANG::SHLD && isSameAddress(Addr, I->getOperand(1)))
      return false;  // another SHLD covers all forward paths
    if (I->getOpcode() == V6CLANG::LHLD && isSameAddress(Addr, I->getOperand(1)))
      return true;   // uncovered reader in same BB
  }

  // 2. BFS through successor BBs.
  SmallPtrSet<MachineBasicBlock *, 8> Visited;
  SmallVector<MachineBasicBlock *, 8> Worklist;

  for (auto *Succ : MBB.successors())
    if (Visited.insert(Succ).second)
      Worklist.push_back(Succ);

  while (!Worklist.empty()) {
    MachineBasicBlock *Cur = Worklist.pop_back_val();
    bool IsSelf = (Cur == &MBB);

    // Self-loop: scan from BB top to ShldC (C is being folded, not a cover).
    auto ScanEnd = IsSelf ? MachineBasicBlock::iterator(ShldC) : Cur->end();

    for (auto I = Cur->begin(); I != ScanEnd; ++I) {
      if (I->getOpcode() == V6CLANG::SHLD && isSameAddress(Addr, I->getOperand(1)))
        goto next_bb;  // covered — don't follow successors
      if (I->getOpcode() == V6CLANG::LHLD && isSameAddress(Addr, I->getOperand(1)))
        return true;   // uncovered reader
    }

    // No kill found — propagate to successors.
    for (auto *Succ : Cur->successors())
      if (Visited.insert(Succ).second)
        Worklist.push_back(Succ);
    next_bb:;
  }

  return false;  // no uncovered reader reachable
}
```

> **Design Notes**: Uses forward BFS with `MBB.successors()`.
> Self-loop is handled by scanning from BB top to the SHLD being folded
> (which cannot act as a covering store since it's being removed).
> Each BB visited at most once. O(n) total.
> MBB must NOT be pre-inserted into Visited — otherwise the self-loop
> path is never checked (MBB as its own successor gets filtered out).
>
> **Implementation Notes**: Added as static helper ~50 lines before `foldShldLhldToPushPop`.

### Step 3.2 — Guard the fold in `foldShldLhldToPushPop` [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp`

Insert the guard immediately before the "Replace SHLD with PUSH HL"
block, after `if (Abort || !Found) continue;`:

```cpp
    // Safety: check that no uncovered LHLD reads this address.
    if (isUncoveredLhldReachable(MBB, std::next(MatchIt), I, ShldAddr))
      continue;
```

> **Implementation Notes**: Inserted after `if (Abort || !Found) continue;`.

### Step 3.3 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Build succeeded: `[4/4] Linking CXX executable bin\clang.exe`.

### Step 3.4 — Lit test: add negative test case [x]

**File**: `tests/lit/CodeGen/V6CLANG/shld-lhld-push-pop-peephole.ll`

Add a second function to the existing lit test that exercises the bug
scenario: a loop where LHLD at the top reads a slot that is SHLD+LHLD'd
later in the same BB. The negative CHECK ensures SHLD survives (fold
blocked).

The function should be a static-stack leaf function with a loop body that:
- Loads from a static slot at the top (LHLD)
- Modifies the value
- Stores back (SHLD) + immediately reloads (LHLD) — the RA artifact pair
- Loops back

The CHECK lines verify:
- `SHLD __v6clang_ss.func_name` is preserved (NOT replaced by PUSH HL)
- The existing sumarray test still shows PUSH/POP (positive case unchanged)

> **Implementation Notes**: Added `interleaved_add` function from real C test IR. CHECK lines verify LHLD→SHLD→LHLD sequence with `{{$}}` anchors to distinguish from +2/+7 slots.

### Step 3.5 — Run lit test [x]

```
python tests\run_all.py
```

Or targeted:
```
llvm-build\bin\llvm-lit tests\lit\CodeGen\V6CLANG\shld-lhld-push-pop-peephole.ll -v
```

> **Implementation Notes**: `shld-lhld-push-pop-peephole.ll` PASS (test #80 of 102).

### Step 3.6 — Run regression tests [x]

```
python tests\run_all.py
```

All existing tests must pass. Key tests to watch:
- `shld-lhld-push-pop-peephole.ll` — positive + negative
- `spill-forwarding.ll` — O16 interaction
- All static-stack related tests

> **Implementation Notes**: 102/102 tests pass. Golden PASS. Lit PASS.

### Step 3.7 — Verification assembly steps from `tests\features\README.md` [x]

Create test folder `tests/features/29/` with:
- `v6clang.c` — interleaved_add with leaf-attributed functions
- `c8080.c` — matching c8080 version
- Compile baseline: `v6clang_old.asm` (before fix)
- Compile new: `v6clang_new01.asm` (after fix)
- Analyze: verify the SHLD is preserved (not folded to PUSH HL)

> **Implementation Notes**: `v6clang_new01.asm` compiled. SHLD at line 51 preserved (was PUSH HL in v6clang_old.asm).

### Step 3.8 — Make sure result.txt is created [x]

Create `tests/features/29/result.txt` with:
- The C test case
- Before/after assembly comparison
- Stats showing the correctness fix (SHLD preserved)

> **Implementation Notes**: Created `tests/features/29/result.txt` with bug description, before/after comparison.

### Step 3.9 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Mirror sync complete.

---

## 4. Expected Results

### Example 1: interleaved_add loop (static stack, O16 disabled)

Before fix — O43 incorrectly folds:
```asm
.LBB0_2:
        LHLD    __v6clang_ss+0        ; reads stale ptr (PUSH below doesn't update slot)
        ...
        PUSH    HL                ; ← incorrect: was SHLD, slot not updated
        POP     HL                ; ← incorrect: was LHLD, value from HW stack
        ...
        JNZ     .LBB0_2
```

After fix — O43 correctly preserves SHLD:
```asm
.LBB0_2:
        LHLD    __v6clang_ss+0        ; reads correct updated ptr
        ...
        SHLD    __v6clang_ss+0        ; ← preserved: slot correctly updated
        ...                       ; (LHLD eliminated by O16, or kept if O16 disabled)
        JNZ     .LBB0_2
```

### Example 2: sumarray loop (positive case unchanged)

```asm
.LBB0_1:
        PUSH    HL                ; ← still folded (no uncovered LHLD elsewhere)
        ...
        POP     HL                ; ← still folded
        PUSH    HL
        ...
        POP     HL
```

No regression.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Over-conservative: blocks folds that are actually safe (e.g., nested loops) | Acceptable — correctness first. The lost optimization is rare (~12cc/4B per missed pair) |
| BFS walk cost on large functions | O(n) per candidate. 8080 functions are tiny. Negligible. |
| Missed edge case in CFG walk | The BFS is complete — visits every reachable BB. Self-loop handled explicitly. |
| Interaction with O16 | O16 removes RELOADs before expansion, so SHLD/LHLD pairs may not exist. No conflict — the fix guards only pairs that do exist. |

---

## 6. Relationship to Other Improvements

- **O16** — masks this bug by eliminating the RELOAD16 pseudo, preventing
  the SHLD/LHLD pair from forming. The fix is needed for O16-disabled
  compilations and for future cases where O16 can't eliminate the reload.
- **O42** — liveness-aware expansion. Complementary, no conflict.
- **O44** — XCHG cancellation. Runs before O43. No conflict.
- **O45** — POP/PUSH cancellation. Runs after O43. The fix may expose
  fewer PUSH/POP pairs for O45 to cancel, but this is correct behavior.

---

## 7. Future Enhancements

- **Precision improvement**: Per-path reachability analysis could allow
  folds that the BFS conservatively blocks. E.g., nested loops where
  each loop has its own covering SHLD before the LHLD.
- **Fuse with O16**: If O16 could mark "this slot has a covering SHLD
  on all paths", O43 could use that information instead of its own BFS.

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O43 Design](design\future_plans\O43_shld_lhld_to_push_pop.md)
* [O43 Bugfix Design](design\future_plans\O43_fix_shld_lhld_safety_guard.md)
* [O16 Design](design\future_plans\O16_store_to_load_forwarding.md)
