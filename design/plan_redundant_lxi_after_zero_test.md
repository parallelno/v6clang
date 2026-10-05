# Plan: Redundant Immediate Load After Branch-Proven Value (O36)

## 1. Problem

### Current behavior

After a conditional branch/return proves something about register values,
immediate loads on the fallthrough path may be redundant. The compiler
does not exploit the value information implied by branch outcomes.

Example — `test_cond_zero_tailcall`:
```asm
test_cond_zero_tailcall:
    MOV  A, H
    ORA  L           ; zero-test x (HL)
    RNZ              ; return x if x != 0
    LXI  HL, 0       ; ← REDUNDANT — HL is already 0 here
    JMP  bar
```

### Desired behavior

```asm
test_cond_zero_tailcall:
    MOV  A, H
    ORA  L
    RNZ
    JMP  bar          ; HL is already 0 — no LXI needed
```

### Root cause

V6ClangLoadImmCombine currently tracks known register values only within a
basic block, starting from `invalidateAll()` at the top of each BB. There
is no cross-block value propagation from predecessor blocks. When a
predecessor ends with a zero-test + conditional branch/return (e.g.,
`MOV A,H; ORA L; RNZ`), the fallthrough block starts with no knowledge
that HL==0 and A==0, so it cannot eliminate redundant `LXI HL, 0`.

## 2. Strategy

### Approach: Seed known values at BB entry in V6ClangLoadImmCombine

Extend V6ClangLoadImmCombine's `processBlock()` method. Before the existing
instruction scan loop, check if the block has a **single predecessor**
whose terminator implies known register values on the fallthrough path.

Recognized patterns:

1. **16-bit zero-test**: `MOV A, rHi; ORA rLo; RNZ/JNZ target`
   — Fallthrough proves: rHi=0, rLo=0, A=0.

2. **8-bit zero-test**: `ORA A; RNZ/JNZ` or `ANA A; RNZ/JNZ`
   — Fallthrough proves: A=0.

3. **CPI imm + JNZ**: `CPI imm; JNZ target`
   — Fallthrough proves: A=imm.

### Why this works

- V6ClangLoadImmCombine already tracks per-register known values and
  eliminates redundant MVI/LXI as MOV/INR/DCR. By seeding the value
  map at block entry, the existing elimination logic handles the rest.
- Single-predecessor check ensures the seeded values are sound — if a
  block has multiple predecessors, the values can't be guaranteed.
- The zero-test idiom (`MOV A,H; ORA L`) is emitted by the V6CLANG_BR_CC16
  zero-compare fast path and ZeroTestOpt, so this pattern is common.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Add seedPredecessorValues | Analyze single pred terminator, seed KnownVal | V6ClangLoadImmCombine.cpp |
| Call before scan loop | Replace bare `invalidateAll()` with seed + fallback | V6ClangLoadImmCombine.cpp |
| Lit test | Verify LXI HL,0 is eliminated after zero-test | load-imm-combine-branch-seed.ll |

## 3. Implementation Steps

### Step 3.1 — Add `seedPredecessorValues()` to V6ClangLoadImmCombine [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangLoadImmCombine.cpp`

Add a new private method `seedPredecessorValues(MachineBasicBlock &MBB)`
that:

1. Checks if MBB has exactly **one** predecessor.
2. Checks that MBB is the **fallthrough** successor of that predecessor
   (pred's layout successor == MBB).
3. Scans backwards from the predecessor's last terminator to find:
   - **Pattern A** (16-bit zero-test): `MOV A, rHi` + `ORA rLo` before
     a Z-flag conditional branch/return (RNZ/JNZ skips fallthrough).
     Seeds: `KnownVal[rHi]=0`, `KnownVal[rLo]=0`, `KnownVal[A]=0`.
   - **Pattern B** (8-bit zero-test): `ORA A` or `ANA A` before RNZ/JNZ.
     Seeds: `KnownVal[A]=0`.
   - **Pattern C** (CPI imm): `CPI imm` before JNZ.
     Seeds: `KnownVal[A]=imm`.
4. For JNZ/RNZ terminators, fallthrough means Z=1 (zero/equal condition).
   For JZ/RZ terminators, fallthrough means Z=0 (non-zero condition) —
   this does NOT prove A=0, so no seeding.
5. Returns true if any values were seeded, false otherwise.

The key insight: only NZ-branch terminators (RNZ, JNZ) allow seeding,
because their fallthrough path means the zero condition was TRUE.

> **Design Notes**: Only the Z flag (NZ/Z branches) is useful for value
> seeding. Carry/Sign/Parity branches don't directly prove register values.
> We keep the analysis simple: only look for the exact instruction sequence
> (no gaps allowed between MOV A,rHi / ORA rLo / terminator).

> **Implementation Notes**: Handles BOTH directions: (1) NZ-branch (JNZ/RNZ)
> fallthrough = Z path, (2) Z-branch (JZ) target = Z path. At LoadImmCombine
> time (before BranchOpt), the compiler often emits JZ to the zero-proven block
> rather than JNZ+fallthrough. Also added LXI rp elimination when both halves
> are already known to hold the correct values.

### Step 3.2 — Integrate seeding into processBlock [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangLoadImmCombine.cpp`

In `processBlock()`, replace:
```cpp
invalidateAll();
```
with:
```cpp
invalidateAll();
seedPredecessorValues(MBB);
```

This preserves the existing behavior (all values start unknown), then
overlays any provable values from the predecessor's terminator.

> **Implementation Notes**: Added call after invalidateAll() in processBlock().

### Step 3.3 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

### Step 3.4 — Lit test: load-imm-combine-branch-seed.ll [x]

**File**: `tests/lit/CodeGen/V6CLANG/load-imm-combine-branch-seed.ll`

Tests:
- Test 1: 16-bit zero-test + RNZ → LXI HL,0 eliminated.
- Test 2: 16-bit zero-test + JNZ → LXI HL,0 eliminated.
- Test 3: CPI imm + JNZ → MVI A,imm eliminated (if applicable).
- Test 4: Multiple predecessors → no seeding (LXI kept).
- Negative test: JZ/RZ fallthrough → no seeding (fallthrough is NZ path).

### Step 3.5 — Run regression tests [x]

```
python tests\run_all.py
```

### Step 3.6 — Verification assembly (`tests\features\README.md`) [x]

Compile the feature test case and analyze the output:
```
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S tests\features\15\v6clang.c -o tests\features\15\v6clang_new01.asm
```

Verify that `test_cond_zero_tailcall` no longer has `LXI HL, 0`.

### Step 3.7 — Make sure result.txt is created (`tests\features\README.md`) [x]

### Step 3.8 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

## 4. Expected Results

### Example 1: Zero-test tail call

Before:
```asm
test_cond_zero_tailcall:
    MOV  A, H
    ORA  L
    RNZ
    LXI  HL, 0       ; 3 bytes, 12cc
    JMP  bar
```

After:
```asm
test_cond_zero_tailcall:
    MOV  A, H
    ORA  L
    RNZ
    JMP  bar          ; LXI HL, 0 eliminated
```

**Savings: 3 bytes, 12cc per instance.**

### Example 2: Null-pointer guard

```c
int handle(int *ptr) {
    if (ptr == 0) return handler(0);
    return *ptr;
}
```

The fallthrough after `MOV A,H; ORA L; RNZ` proves HL=0. Any subsequent
`LXI HL, 0` or `MVI H, 0` / `MVI L, 0` / `MVI A, 0` or `XRA A` will
be eliminated by the existing LoadImmCombine machinery.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Seeding wrong values for multi-predecessor blocks | Single-predecessor + fallthrough check |
| Incorrect pattern match (gap between MOV/ORA/terminator) | Strict backward scan — exactly 3 instructions |
| Seeding for JZ fallthrough (NZ path, values unknown) | Only seed for NZ-branch terminators (RNZ, JNZ) |
| Predecessor has intervening instructions between ORA and branch | Strict adjacency requirement — ORA must immediately precede terminator |

---

## 6. Relationship to Other Improvements

- **O27 (i16 Zero-Test)**: Creates the `MOV A,H; ORA L; Jcc` pattern that
  O36 exploits. O27 is complete and a prerequisite.
- **O35 (Rcc over RET)**: Creates `Rcc + LXI + JMP` sequences that O36
  can simplify by removing the redundant LXI.
- **O13 (LoadImmCombine)**: O36 extends this infrastructure with
  cross-block value seeding; the existing MVI/LXI elimination handles
  the actual optimization.
- **O29 (Cross-BB Imm Propagation)**: O36 is a targeted subset of O29,
  focusing only on branch-implied values rather than general cross-block
  propagation.

## 7. Future Enhancements

None planned — the optimization already covers all register pairs and
all three patterns (16-bit zero-test, 8-bit zero-test, CPI imm).

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O36 Design](design\future_plans\O36_redundant_lxi_after_zero_test.md)
* [V6ClangLoadImmCombine.cpp](llvm-project\llvm\lib\Target\V6CLANG\V6ClangLoadImmCombine.cpp)
