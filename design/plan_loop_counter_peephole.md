# Plan: Loop Counter DEC+Branch Peephole (O18)

## 1. Problem

### Current behavior

V6CLANG emits a redundant flag-setting instruction after `DCR` in loop
counter patterns because the compiler doesn't track that `DCR r` already
sets the Z flag:

**Pattern A (counter in A, most common):**
```asm
DCR  A           ;  8cc   decrement counter, sets Z flag
ORA  A           ;  4cc   redundant flag test
JNZ  loop        ; 12cc   branch if nonzero
; Total: 24cc, 5B
```

**Pattern B (counter in non-A register):**
```asm
DCR  B           ;  8cc   decrement counter in B, sets Z flag
MOV  A, B        ;  8cc   load into A for test
ORA  A           ;  4cc   redundant flag test
JNZ  loop        ; 12cc   branch if nonzero
; Total: 32cc, 7B
```

**Pattern C (decrement through A, per O18 design doc):**
```asm
MOV  A, B        ;  8cc   load counter into A
DCR  A           ;  8cc   decrement
MOV  B, A        ;  8cc   store back
ORA  A           ;  4cc   redundant flag test
JNZ  loop        ; 12cc   branch if nonzero
; Total: 40cc, 8B
```

### Desired behavior

All three patterns reduce to:

```asm
DCR  r           ;  8cc   decrement counter, sets Z flag
JNZ  loop        ; 12cc   branch if nonzero
; Total: 20cc, 4B
```

The 8080's `DCR r` (and `INR r`) sets the Z flag directly. The entire
flag-testing sequence after DCR/INR is redundant.

### Root cause

The comparison `icmp ne i8 %dec, 0` is lowered independently from the
decrement `add i8 %counter, -1`. After register allocation and the
ZeroTestOpt pass (CPI 0 → ORA A), the redundant `ORA A` remains because
no pass tracks that DCR/INR already set Z.

---

## 2. Strategy

### Approach: Post-RA peephole patterns in V6ClangPeephole.cpp

Add a new `foldCounterBranch` method to the existing peephole pass.
Scan each basic block for conditional branches (`JNZ`/`JZ`) preceded by
a `DCR`/`INR` + redundant flag-test sequence. Remove the intermediate
instructions, leaving just `DCR r`/`INR r` + `Jcc`.

### Why this works

1. `DCR r` and `INR r` set the Z flag identically to `ORA A` for the
   purpose of zero-testing. The 8080 manual confirms DCR/INR affect
   Z, S, P, AC flags (all except CY). JNZ/JZ only test Z.

2. Pattern A: `DCR A; ORA A; Jcc` — ORA A is redundant because DCR A
   already set Z. Simply remove ORA A.

3. Pattern B: `DCR r; MOV A,r; ORA A; Jcc` — The DCR r sets Z based on
   the new value of r. MOV A,r + ORA A recomputes the same Z flag.
   Remove MOV A,r and ORA A. Requires A dead after Jcc.

4. Pattern C: `MOV A,r; DCR A; MOV r,A; ORA A; Jcc` — The entire sequence
   computes `r = r - 1` through A. Replace with `DCR r` which does the
   same thing. ORA A is redundant. Requires A dead after Jcc.

5. Post-RA timing: registers are physical, all passes that might insert
   instructions have run. The liveness check is reliable.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Add `isRegDeadAfter` helper | Reuse pattern from V6ClangXchgOpt | V6ClangPeephole.cpp |
| Add `foldCounterBranch` | Match 3 pattern variants, remove redundant ops | V6ClangPeephole.cpp |
| Wire into runOnMachineFunction | Call from main loop | V6ClangPeephole.cpp |
| Lit test | Verify DCR+JNZ/JZ pattern in IR | loop-counter-peephole.ll |

---

## 3. Implementation Steps

### Step 3.1 — Add `isRegDeadAfter` helper and `foldCounterBranch` to V6ClangPeephole.cpp [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangPeephole.cpp`

Add a static `isRegDeadAfter` helper (same pattern as V6ClangXchgOpt.cpp)
and a new `foldCounterBranch` method to the V6ClangPeephole class.

The method scans backward from each `JNZ`/`JZ` instruction looking for
the three pattern variants:

**Pattern A** (`DCR A / INR A; ORA A; Jcc`):
- Match: Jcc at position i, ORA A at i-1, DCR/INR A at i-2.
- Action: Remove ORA A.
- No liveness check needed (A is already live before the sequence).

**Pattern B** (`DCR r / INR r; MOV A,r; ORA A; Jcc`, r ≠ A):
- Match: Jcc at i, ORA A at i-1, MOV A,r at i-2, DCR/INR r at i-3.
- Precondition: A is dead after Jcc (checked by forward scan).
- Action: Remove MOV A,r and ORA A.

**Pattern C** (`MOV A,r; DCR A / INR A; MOV r,A; ORA A; Jcc`):
- Match: Jcc at i, ORA A at i-1, MOV r,A at i-2, DCR/INR A at i-3,
  MOV A,r at i-4.
- Precondition: A is dead after Jcc.
- Action: Replace 5 instructions with DCR/INR r + Jcc.

> **Design Notes**: Pattern order matters — check C first (5 instructions),
> then B (4 instructions), then A (3 instructions), so the longest match
> wins. The INR variant is symmetric: `INR r` also sets Z, so `INR` is
> handled alongside `DCR` in every pattern.

> **Implementation Notes**: Added `isRegDeadAfter` (same pattern as V6ClangXchgOpt),
> `isRedundantZeroTest` (matches both ORA A and CPI 0 — needed because
> ZeroTestOpt runs after Peephole), `isDcrOrInr`, and `foldCounterBranch`.
> Pattern C → B → A order. Wired into runOnMachineFunction before eliminateTailCall.

### Step 3.2 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Build succeeded (12/12 targets, incremental).

### Step 3.3 — Lit test: loop-counter-peephole.ll [x]

**File**: `tests/lit/CodeGen/V6Clang/loop-counter-peephole.ll`

Test cases:
1. `@dcr_a_loop` — counter in A, Pattern A: verify `DCR A` immediately
   followed by `JNZ`, no `ORA A`.
2. `@simple_countdown` — simple countdown loop returning result: verify
   `DCR` + `JNZ` without intervening `ORA`.

> **Implementation Notes**: Three test functions: `dcr_a_loop` (Pattern A with JNZ),
> `dcr_a_jz` (Pattern A with JZ), `inr_a_loop` (INR variant). All pass.

### Step 3.4 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: 76/76 lit + 15/15 golden = all pass.

### Step 3.5 — Verification assembly steps from `tests\features\README.md` [x]

1. Create test folder `tests/features/02/`.
2. Create `v6clang.c` and `c8080.c` with loop counter test cases.
3. Compile baseline assembly, then post-optimization assembly.
4. Analyze and document improvements in `result.txt`.

> **Implementation Notes**: Pattern A fired on `countdown()`: `DCR A; CPI 0; JNZ`
> → `DCR A; JNZ`. Savings: 4cc+1B per iteration. v6clang loop 36cc/iter vs c8080 80cc/iter.

### Step 3.6 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Mirror synced successfully.

---

## 4. Expected Results

### Pattern A — Counter in A (most common)

**Before:**
```asm
.loop:
    DCR  A           ;  8cc
    ORA  A           ;  4cc
    JNZ  .loop       ; 12cc
; Loop overhead: 24cc, 5B per iteration
```

**After:**
```asm
.loop:
    DCR  A           ;  8cc
    JNZ  .loop       ; 12cc
; Loop overhead: 20cc, 4B per iteration
```

**Savings: 4cc + 1B per iteration.**

### Pattern B — Counter in non-A register

**Before:**
```asm
.loop:
    ; ... loop body using A ...
    DCR  B           ;  8cc
    MOV  A, B        ;  8cc
    ORA  A           ;  4cc
    JNZ  .loop       ; 12cc
; Loop overhead: 32cc, 7B per iteration
```

**After:**
```asm
.loop:
    ; ... loop body using A ...
    DCR  B           ;  8cc
    JNZ  .loop       ; 12cc
; Loop overhead: 20cc, 4B per iteration
```

**Savings: 12cc + 3B per iteration.**

### Pattern C — Decrement through A

**Before:**
```asm
.loop:
    MOV  A, B        ;  8cc
    DCR  A           ;  8cc
    MOV  B, A        ;  8cc
    ORA  A           ;  4cc
    JNZ  .loop       ; 12cc
; Loop overhead: 40cc, 8B per iteration
```

**After:**
```asm
.loop:
    DCR  B           ;  8cc
    JNZ  .loop       ; 12cc
; Loop overhead: 20cc, 4B per iteration
```

**Savings: 20cc + 4B per iteration.**

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `DCR r` doesn't set CY flag, but JNZ/JZ only test Z — no issue | Only match JNZ/JZ (Z-flag branches), not JC/JNC |
| A register incorrectly assumed dead | `isRegDeadAfter` checks all successors' livein lists |
| Pattern matches across basic block boundaries | Only match consecutive instructions within same MBB |
| INR r at wraparound (255→0) sets Z=1 — correct for JZ "reached zero" | Semantics preserved: INR 255 = 0 with Z=1, same as ORA 0 |

---

## 6. Relationship to Other Improvements

- **O17 (Redundant Flag Elimination)**: O17 is a general-purpose pass that
  would catch Pattern A (`DCR A; ORA A`). O18 is loop-counter-specific and
  also handles Patterns B and C with register shuffling. O18 subsumes the
  DCR/INR cases of O17.
- **O7 (Loop Strength Reduction)**: Already implemented. O18 complements it
  by optimizing the loop counter overhead that remains after strength reduction.
- **O12 (Global Copy Opt)**: When cross-BB copy optimization is implemented,
  more counters may end up in non-A registers, making Patterns B and C more
  frequent.

---

## 7. Future Enhancements

- Extend to handle `SUI 1` as equivalent to `DCR A` in Pattern C.
- Extend to handle conditional branches other than JNZ/JZ (JM, JP) when
  DCR/INR is followed by sign/parity tests.

> **Not pursued — SUI 1 (April 2026):** Empirical testing across all compiled
> assembly output shows the V6CLANG backend **never emits `SUI`**. LLVM always
> lowers `sub i8 %x, 1` directly to `DCR A` via ISel patterns. Zero
> occurrences of `SUI` in any compiler-generated `.asm` file. Dead pattern.

> **Not pursued — JM/JP sign-flag branches (April 2026):** Tested with
> `while (n >= 0) { result = n; n--; }` — the compiler emits
> `DCR A; CPI 0xFF; JNZ` instead of `DCR A; JP`. LLVM's InstCombine rewrites
> the signed comparison `icmp slt i8 %dec, 0` to `icmp eq i8 %orig, 0`,
> losing the sign-flag semantics. A peephole cannot safely replace
> `CPI 0xFF; JNZ` with `JP` — they are not equivalent for all inputs
> (e.g. A=0x81: DCR→0x80 has sign=1 so JP exits, but 0x80≠0xFF so JNZ
> continues). The correct fix would require preserving `nsw` info at ISel
> level to emit sign-flag tests — a non-trivial ISel change, not a peephole
> extension. Separately, `while (n > 0)` causes register allocation failure
> because LLVM rewrites it to `icmp ugt i8 %x, 1` which requires a CPI
> with a live constant, exhausting 8080's limited registers.

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O18 Design](design\future_plans\O18_loop_counter_peephole.md)
* [llvm-z80 Z80LateOptimization analysis](design\future_plans\llvm_z80_analysis.md) §S8
