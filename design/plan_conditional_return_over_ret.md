# Plan: O35 — Conditional Return Over RET (Jcc-over-RET → Rcc)

## 1. Problem

### Current behavior

When a conditional branch jumps over a fallthrough `RET`, the backend
emits a 4-byte `Jcc + RET` pair:

```asm
    MOV  A, H
    ORA  L
    JZ   .LBB0_1       ; 3 bytes, 12cc — conditional branch over RET
    RET                 ; 1 byte, 12cc  — fallthrough return
.LBB0_1:
    LXI  HL, 0
    JMP  bar
```

### Desired behavior

Replace the `Jcc skip / RET / skip:` sequence with a single inverted
conditional return `Rcc`:

```asm
    MOV  A, H
    ORA  L
    RNZ                 ; 1 byte, 6cc (not taken) / 12cc (taken)
.LBB0_1:
    LXI  HL, 0
    JMP  bar
```

### Root cause

The existing `invertConditionalBranch` handles `Jcc + JMP` but not
`Jcc + RET`. The existing `foldConditionalReturns` handles `Jcc → RET-only
block` but not the case where the Jcc jumps **over** an inline RET.

## 2. Strategy

### Approach: Add `invertConditionalOverRET()` to V6ClangBranchOpt

Add a new sub-pass that scans each block for the pattern
`Jcc .Lskip / RET / .Lskip:` (where `.Lskip` is the layout successor)
and replaces it with the inverted conditional return `Rcc_inv`.

### Why this works

- The Jcc skips over the RET to reach the next block.
- Inverting the condition and emitting `Rcc_inv` returns when the
  original Jcc would *not* branch — exactly equivalent semantics.
- The code then falls through to the block that was the Jcc target.

### Summary of changes

| File | Change |
|------|--------|
| `V6ClangBranchOpt.cpp` | Add `invertConditionalOverRET()` method |
| `V6ClangBranchOpt.cpp` | Wire into `runOnMachineFunction` after `invertConditionalBranch` |
| `conditional-return-over-ret.ll` | New lit test |

## 3. Implementation Steps

### Step 3.1 — Add `invertConditionalOverRET()` to V6ClangBranchOpt.cpp [x]

Add the method declaration in the class and the implementation:

```cpp
/// Look for: Jcc .Lskip / RET / .Lskip: (layout successor)
/// Transform to: Rcc_inv (inverted conditional return)
bool invertConditionalOverRET(MachineFunction &MF);
```

Algorithm:
1. For each MBB with ≥ 2 instructions.
2. Check that the last instruction is `RET`.
3. Check that the previous instruction is a `Jcc` with an MBB operand.
4. Check that the Jcc target is the layout successor of MBB.
5. Compute the inverted Jcc opcode, then map to Rcc.
6. Replace the Jcc+RET pair with Rcc_inv.
7. Remove the RET block successor edge (the MBB no longer falls through
   to the layout successor in CFG terms — it returns).

> **Implementation Notes**:

### Step 3.2 — Wire into `runOnMachineFunction` [x]

Inserted BEFORE `threadJMPOnlyBlocks` (not after `invertConditionalBranch`
as originally planned). O35 must run before threading to catch Jcc targets
that are still local MBBs.

Also added a JMP-only guard: if the Jcc target is a JMP-only block, O35
defers to threading (which handles it better by redirecting the Jcc
directly to the external target).

> **Implementation Notes**:

### Step 3.3 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**:

### Step 3.4 — Lit test: conditional-return-over-ret.ll [x]

Add `tests/lit/CodeGen/V6Clang/conditional-return-over-ret.ll` with:

1. **test_jcc_over_ret** — basic pattern: `Jcc skip / RET / skip: JMP bar`
   should become `Rcc / JMP bar`.
2. **test_jcc_over_ret_nz** — tests the NZ variant.
3. **Negative: non-layout-successor** — Jcc target is not the next block,
   should NOT transform.

> **Implementation Notes**:

### Step 3.5 — Run lit test [x]

```
llvm-build\bin\llvm-lit tests\lit\CodeGen\V6Clang\conditional-return-over-ret.ll -v
```

> **Implementation Notes**:

### Step 3.6 — Run regression tests [x]

89/89 lit + 15/15 golden = all pass.

```
python tests\run_all.py
```

> **Implementation Notes**:

### Step 3.7 — Verification assembly steps from `tests\features\README.md` [x]

`test_two_arg_tailcall(int x, int y)` with O35: `RNZ` replaces `JZ + RET`.
Savings: 3 bytes, 12-18cc.

Compile from feature test folder 14:
```
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S tests\features\14\v6clang.c -o tests\features\14\v6clang_new01.asm
```

Verify `RNZ` appears instead of `JZ` + `RET` in `test_cond_zero_tailcall`.

> **Implementation Notes**:

### Step 3.8 — Make sure result.txt is created. `tests\features\README.md` [x]

> **Implementation Notes**:

### Step 3.9 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**:

## 4. Expected Results

### test_cond_zero_tailcall

Before (4 bytes for branch+return):
```asm
    JZ   .LBB0_1       ; 3 bytes, 12cc
    RET                 ; 1 byte, 12cc
.LBB0_1:
```

After (1 byte):
```asm
    RNZ                 ; 1 byte, 6cc (fall-through) / 12cc (taken)
```

**Net savings: 3 bytes, 18cc when returning, 6cc when falling through.**

### test_early_return_guard

Any function with `if (cond) return val; <fallthrough tail call>` benefits.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| CFG edges incorrect after transform | Remove the Jcc target successor edge; the MBB now returns and doesn't have a fallthrough successor |
| Interaction with foldConditionalReturns | O35 runs before foldConditionalReturns; they handle disjoint patterns (Jcc-over-RET vs Jcc→RET-block) |
| Pattern rarely fires | Very low cost (~20 lines); fires for any early-return guard over tail call |

---

## 6. Relationship to Other Improvements

- **O28** (Branch Threading): Creates the Jcc-over-RET pattern by threading
  through JMP-only blocks.
- **O30** (Conditional Return): Handles the complementary case where Jcc
  targets a RET-only block. O35 handles inline RET fallthrough.
- **O27** (i16 Zero-Test): Emits `MOV A,H; ORA L` which feeds the Jcc.

## 7. Future Enhancements

- Could be generalized to handle Jcc-over-RET with intervening debug instrs.

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O35 Design](design\future_plans\O35_conditional_return_over_ret.md)
