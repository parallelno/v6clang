# Plan: Load-Immediate Combining (Register Value Tracking)

## 1. Problem

### Current behavior

After pseudo expansion and register allocation, the emitted code frequently
contains redundant `MVI r, imm` instructions where:
- Another register already holds the needed immediate value
- The target register already holds `imm ± 1`

This is especially common with zero-byte materialization for zero-extensions:

```asm
MVI  E, 0       ;  8cc, 2B       ; first zero
...
MVI  H, 0       ;  8cc, 2B       ; redundant — E already holds 0
```

### Desired behavior

```asm
MVI  E, 0       ;  8cc, 2B       ; first zero
...
MOV  H, E       ;  8cc, 1B       ; reuse E's known value (saves 1 byte)
```

Or when a register holds `imm ± 1`:

```asm
MVI  B, 5       ;  8cc, 2B       ; B = 5
...
MVI  B, 6       ;  8cc, 2B       ; need B = 6
```

Becomes:
```asm
MVI  B, 5       ;  8cc, 2B       ; B = 5
...
INR  B          ;  8cc, 1B       ; B = B + 1 = 6 (saves 1 byte)
```

### Root cause

Post-RA passes and pseudo expansion don't track register values across
instructions. Each `MVI` is emitted independently, even when the value
could be obtained more cheaply from another register or an increment.

---

## 2. Strategy

### Approach: Post-RA forward scan with register value tracking

Add a new `MachineFunctionPass` (`V6ClangLoadImmCombine`) that runs early in
the pre-emit pipeline (after `AccumulatorPlanning`, before `Peephole`).
It performs a forward scan through each basic block, tracking the known
constant value in each of the 7 GPRs (A, B, C, D, E, H, L).

When encountering `MVI r, imm`:
1. If another register `r'` already holds `imm` → replace with `MOV r, r'`
   (saves 1 byte, same 8cc)
2. If `r` itself holds `imm + 1` → replace with `DCR r` (saves 1 byte,
   same 8cc cost; DCR sets FLAGS but that's fine — tracked by later passes)
3. If `r` itself holds `imm - 1` → replace with `INR r` (saves 1 byte,
   same 8cc cost)
4. Otherwise: keep `MVI` and track the new value

### Why this works

- **Forward scan**: Register values are tracked from the start of each
  basic block (all unknown). Each instruction updates the tracking state.
- **Single-BB**: No inter-BB analysis needed — conservatively reset at
  block boundaries.
- **Post-RA**: Physical registers are known; we directly inspect opcodes.
- **Safe**: Only replaces when the register value is provably known.
  Invalidates tracking when a register is modified by a non-immediate
  instruction (e.g., MOV, ALU result, POP, memory load).

### Why before Peephole

The `MVI → MOV` replacements create new MOV instructions that the Peephole
pass can further simplify (e.g., eliminate self-MOVs, combine with
subsequent patterns). Running before Peephole maximizes cleanup opportunities.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Create pass file | V6ClangLoadImmCombine.cpp | llvm/lib/Target/V6Clang/ |
| Declare factory | createV6ClangLoadImmCombinePass() | V6Clang.h |
| Register in pipeline | After AccumulatorPlanning, before Peephole | V6ClangTargetMachine.cpp |
| Add to build | CMakeLists.txt | llvm/lib/Target/V6Clang/ |
| Lit test | load-imm-combine.ll | tests/lit/CodeGen/V6Clang/ |

---

## 3. Implementation Steps

### Step 3.1 — Create V6ClangLoadImmCombine.cpp [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangLoadImmCombine.cpp`

Implement the post-RA pass:

- Track known values in 7 registers: A, B, C, D, E, H, L
- Use `std::optional<int64_t>` per register (nullopt = unknown)
- On `MVI r, imm`:
  - Check if any other register holds `imm` → emit `MOV r, r'`
  - Check if `r` holds `imm - 1` → emit `INR r`
  - Check if `r` holds `imm + 1` → emit `DCR r`
  - Otherwise keep MVI and record value
- On `MOV r, r'`: copy known value from r' to r
- On `LXI rp, imm16`: set known values for both sub-registers
- On ALU ops that write a register: invalidate that register
- On CALL, RET: invalidate all registers
- On any other write to a register: invalidate it
- Toggle: `-v6clang-disable-load-imm-combine`

> **Design Notes**:
> - `MOV r, r'` preference: prefer non-A source registers to avoid
>   accumulator contention. If multiple registers hold the value, pick
>   the first non-A match.
> - INR/DCR replacement: only when no other register holds the value
>   (MOV is preferred because INR/DCR set FLAGS, which may interfere
>   with later optimizations).
> - FLAGS clobber from INR/DCR: safe because this pass runs before
>   flag-dependent optimizations, and the flag elimination pass runs
>   later to clean up.

> **Implementation Notes**: <empty>

### Step 3.2 — Declare factory in V6Clang.h [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6Clang.h`

Add:
```cpp
FunctionPass *createV6ClangLoadImmCombinePass();
```

> **Implementation Notes**: <empty>

### Step 3.3 — Register in pipeline [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangTargetMachine.cpp`

Add `addPass(createV6ClangLoadImmCombinePass())` after AccumulatorPlanning,
before Peephole in `addPreEmitPass()`.

> **Implementation Notes**: <empty>

### Step 3.4 — Add to CMakeLists.txt [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/CMakeLists.txt`

Add `V6ClangLoadImmCombine.cpp` to the source list.

> **Implementation Notes**: <empty>

### Step 3.5 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: <empty>

### Step 3.6 — Lit test: load-imm-combine.ll [x]

**File**: `tests/lit/CodeGen/V6Clang/load-imm-combine.ll`

Test cases:
1. Two `MVI r, 0` → second replaced with `MOV r, r'`
2. `MVI r, N` followed by `MVI r, N+1` → replaced with `INR r`
3. `MVI r, N` followed by `MVI r, N-1` → replaced with `DCR r`
4. Value invalidation: ALU op between MVI calls prevents combining
5. MOV propagation: `MVI A, 42; MOV B, A; ... MVI C, 42` → `MOV C, B`

> **Implementation Notes**: <empty>

### Step 3.7 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: <empty>

### Step 3.8 — Verification assembly steps from `tests\features\README.md` [x]

Compile the feature test case, analyze assembly, verify MVI→MOV/INR/DCR
replacements.

> **Implementation Notes**: <empty>

### Step 3.9 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: <empty>

---

## 4. Expected Results

### Example 1: Zero-extension high byte

```asm
; Before                          ; After
MVI  E, 0       ;  8cc, 2B       MVI  E, 0       ;  8cc, 2B
MOV  B, E       ;  8cc, 1B       MOV  B, E       ;  8cc, 1B
...                               ...
MVI  H, 0       ;  8cc, 2B  ←    MOV  H, E       ;  8cc, 1B
```
Saves 1 byte per replaced MVI.

### Example 2: Counter increment pattern

```asm
; Before                          ; After
MVI  B, 10      ;  8cc, 2B       MVI  B, 10      ;  8cc, 2B
...                               ...
MVI  B, 11      ;  8cc, 2B  ←    INR  B          ;  8cc, 1B
```
Saves 1 byte.

### Example 3: Multiple zero registers

```asm
; Before                          ; After
MVI  E, 0       ;  8cc, 2B       MVI  E, 0       ;  8cc, 2B
MVI  D, 0       ;  8cc, 2B  ←    MOV  D, E       ;  8cc, 1B
MVI  H, 0       ;  8cc, 2B  ←    MOV  H, E       ;  8cc, 1B
```
Saves 2 bytes total.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| INR/DCR clobber FLAGS unexpectedly | Prefer MOV when possible; INR/DCR only as fallback when no source register available |
| Incorrect value tracking after complex sequences | Conservative invalidation on any non-tracked write; per-BB reset |
| Register pair sub-register tracking errors | Use TRI->getSubReg() for LXI decomposition; test with pair operations |
| Pass ordering conflict with AccumulatorPlanning | Run after AccPlanning (which may insert MOVs); our pass sees final state |

---

## 6. Relationship to Other Improvements

- **O17 (Redundant Flag Elimination)**: Runs later in pipeline; will clean
  up any redundant flag-setting if INR/DCR introduces unnecessary flag sets
  before branches.
- **O18 (Loop Counter Peephole)**: Unaffected — operates on DCR+branch
  patterns after this pass runs.
- **Peephole**: Runs after this pass; can further simplify any MOV patterns
  we introduce.
- **AccumulatorPlanning**: Runs before this pass; its A-register optimizations
  are already applied when we scan.

---

## 7. Future Enhancements

- **Inter-BB analysis**: Track values across basic block boundaries using
  dominator-based analysis for larger savings.
- **LXI combining**: Track 16-bit register pair values and replace
  redundant `LXI rp, imm` when both sub-registers are known.
- **Memory value tracking**: Track values stored to known stack slots
  for reload elimination.

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O13 Feature Description](design\future_plans\O13_load_immediate_combining.md)
* [llvm-mos combineLdImm](design\future_plans\llvm_mos_analysis.md) §S4
