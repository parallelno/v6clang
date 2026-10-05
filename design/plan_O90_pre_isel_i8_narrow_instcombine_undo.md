# Plan: O90 — Pre-ISel i8 Narrowing (Undo InstCombine Widening)

## 1. Problem

### Current behavior

`V6ClangTypeNarrowing.cpp` already has `tryNarrowAndConst` which narrows
`(and i16 X, C)` to `zext(and i8 (trunc X), C)` when C ≤ 0xFF.
However it has two gaps:

1. **PHI sibling guard blocks it for hot loops**: When X is a loop PHI that
   has any i16 sibling PHIs, the guard returns early.  In `lfsr16`, `lfsr`
   is a PHI with two i16 siblings (`acc` and `i`), so the narrowing never
   fires — even though the AND result is only used for a single zero-test
   with no register-persistence requirement.

2. **`or` and `xor` not handled**: Only `Instruction::And` is collected in
   Phase 2.  `(or i16 X, C)` and `(xor i16 X, C)` with C ≤ 0xFF are equally
   expensive (expand to `V6CLANG_OR16` / `V6CLANG_XOR16`, 6 instructions each) and
   equally narrowable.

Result for `u8 lsb = (u8)(lfsr & 1); if (lsb)`:

```asm
; --- V6CLANG_AND16 (6 insn) + SPILL + CMP16_ZERO ---
LXI   B, 1          ; 12cc  materialise constant 1
MOV   A, L          ;  8cc
ANA   C             ;  4cc  lo byte AND
MOV   C, A          ;  8cc
MOV   A, H          ;  8cc  hi byte (= 0 always)
ANA   B             ;  4cc  hi AND with 0 — always 0
; spill + CMP16_ZERO ~32cc
; Total: ~76cc per iteration (plus spill overhead)
```

### Desired behavior

```asm
MOV  A, C           ;  8cc  lfsr lo byte
ANI  1              ;  8cc  AND immediate, sets Z flag
JNZ  .taken         ; 12cc
; Total: 28cc — flags already set by ANI, no separate zero-test needed
```

### Root cause

InstCombine's `computeKnownBits` fold removes the user's `trunc` and widens
`icmp ne (trunc i16 X), 0` → `icmp ne i16 X, 0`.  The widened AND stays at
i16, the PHI sibling guard blocks `tryNarrowAndConst`, and ISel emits
`V6CLANG_AND16` + `V6CLANG_CMP16_ZERO`.

The guard was added to prevent a spill/reload regression when the AND result
needs to be kept alive in a register.  But when ALL users of the AND are
zero-tests (`icmp eq/ne %r, 0`), the result never needs to persist — it only
sets flags.  The guard is too conservative in that case.

---

## 2. Strategy

### Approach

Extend `V6ClangTypeNarrowing.cpp`:

1. **Relax PHI sibling guard for pure zero-test uses**: When every user of
   `(and i16 X, C)` is `icmp eq/ne %r, 0`, bypass the PHI sibling check.
   The narrowed AND result only sets flags and needs no register allocation.

2. **Generalize to `or` and `xor`**: Rename `tryNarrowAndConst` to
   `tryNarrowBitwiseConst` (taking the opcode as a parameter) and extend
   Phase 2 to collect `Or` and `Xor` i16 operations with C ≤ 0xFF.

### Why this works

- `(and/or/xor i16 X, C) == 0` iff `(and/or/xor i8 (trunc X), C8) == 0`
  when C ≤ 0xFF — mathematically identical.
- The `trunc i16 to i8` is free on V6CLANG (lo sub-register of a register pair).
- `ANI`/`ORI`/`XRI` are 2-byte immediates that set Z directly — no separate
  `V6CLANG_CMP16_ZERO` needed downstream.
- The PHI sibling concern (register pressure) does not apply when the result
  is a transient flag-setting value.

### Summary of changes

| File | Change |
|------|--------|
| `V6ClangTypeNarrowing.cpp` | Rename `tryNarrowAndConst` → `tryNarrowBitwiseConst`; add zero-test guard relaxation; extend Phase 2 to `Or`/`Xor` |
| `V6Clang.h` | No change needed (pass creation function unchanged) |
| Lit test (new) | `bitwise-narrow-const.ll` covering `and`/`or`/`xor` in PHI loop context |

---

## 3. Implementation Steps

### Step 3.1 — Relax PHI sibling guard + generalize to or/xor [x]

In `llvm-project/llvm/lib/Target/V6Clang/V6ClangTypeNarrowing.cpp`:

1. Add helper `allUsersAreZeroTests(Value *V)` that returns true when every
   user is `icmp eq/ne V, 0`.

2. Rename `tryNarrowAndConst` → `tryNarrowBitwiseConst(BinaryOperator *BO)`
   — accept `And`, `Or`, `Xor` at i16 with constant RHS ≤ 0xFF.

3. In `tryNarrowBitwiseConst`, before the PHI sibling guard, check:
   ```cpp
   bool pureZeroTest = allUsersAreZeroTests(BO);
   if (!pureZeroTest) {
     // apply existing PHI sibling guard
   }
   ```

4. In `runOnFunction` Phase 2, collect `And`, `Or`, `Xor` (not just `And`),
   and call `tryNarrowBitwiseConst` for each.

5. Update the class declaration to reflect the rename.

> **Design Notes**: `allUsersAreZeroTests` must check both operand positions of
> the icmp (the BO value can be operand 0 or 1).  Zero is `ConstantInt::get(Ty, 0)`.
> Use `PatternMatch::m_Zero()` for robustness.

> **Implementation Notes**: Implemented `allUsersAreZeroTests` that checks all users are `icmp eq/ne V, 0` using `m_Zero()`. The plan's rename of `tryNarrowAndConst` → `tryNarrowBitwiseConst` was **not** done — analysis showed `or`/`xor` with zero-test are NOT safely narrowable (hi byte of `or i16 X, C` is X_hi, unknown). Only `and` is safe (hi byte = X_hi & 0 = 0). Kept `tryNarrowAndConst`, relaxed only the PHI sibling guard when `allUsersAreZeroTests(And)` is true.

### Step 3.2 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Build clean, 5 files recompiled (V6ClangTypeNarrowing.cpp + dependent objects).

### Step 3.3 — Lit test: bitwise-narrow-const.ll [x]

Create `llvm-project/llvm/test/CodeGen/V6Clang/bitwise-narrow-const.ll` covering:

- `and_zero_test_phi_sibling`: `and i16 PHI, 1` with i16 siblings — must emit `ANI 1`
- `or_narrow_const`: `or i16 x, 0x80` result used as i8 — `ORI 0x80`
- `xor_narrow_const`: `xor i16 x, 0x55` result used as i8 — `XRI 0x55`
- `and_wide_const`: `and i16 x, 0x1234` — must NOT narrow (C > 0xFF)
- `and_live_hi`: result assigned to i16 — must NOT narrow when hi byte needed

Run: `python llvm-build\bin\llvm-lit.py llvm-project\llvm\test\CodeGen\V6Clang\bitwise-narrow-const.ll`

> **Implementation Notes**: Created `type-narrow-bitwise-const.ll` (not `bitwise-narrow-const.ll`). 4 test cases: (1) `and_zerotest_phi_siblings` — PHI + siblings, zero-test only → `ANI` emitted, no `LXI`; (2) `and_live_result_no_narrow` — result used as i16 return → must NOT narrow; (3) `and_large_const_no_narrow` — C=3855 > 0xFF → must NOT narrow; (4) `and_no_siblings_baseline` — PHI with no siblings → `ANI`. All 4 pass. Key fix required: `.ll` must have `target triple = "i8080-unknown-v6clang"` for the pass to fire.

### Step 3.4 — Run regression tests [x]

```
python tests\run_all.py
```

All lit + golden + benchmark tests must pass.

> **Implementation Notes**: All 151 lit tests pass (including new test at position 148). All 16 golden tests pass. All 5 benchmarks pass with correct checksums (lfsr16=0x1D). lfsr16 v6clang -O2: 1,410,320 cc.

### Step 3.5 — Verification assembly steps [x]

Compile the feature test assembly:
```
llvm-build\bin\clang.exe -target i8080-unknown-v6clang -O2 -S
    tests\features\72\v6clang.c
    -o tests\features\72\v6clang_new01.asm
```

Also recompile the lfsr16 benchmark to confirm the improvement:
```
llvm-build\bin\clang.exe -target i8080-unknown-v6clang -O2 -S
    tests\benchmarks_c\src\lfsr16.c
    -o tests\benchmarks_c\asm\v6clang_lfsr16_O2.s
```

Verify in feature test: `ANI`/`ORI`/`XRI` present, no `LXI rp,const`, no `V6CLANG_AND16`/`OR16`/`XOR16` for the narrowable cases.

> **Implementation Notes**: Compiled `v6clang_new01.asm`. Confirmed `ANI 1` in `lfsr_step` hot loop and `and_lsb_branch`. The small non-loop functions (`and_nibble`, `or_hi_bit`, `xor_pattern`) were already optimal (DAGCombiner trunc path, unchanged by O90). `and_wide` correctly still emits V6CLANG_AND16 (C > 0xFF guard).

### Step 3.6 — Create result.txt [x]

Create `tests\features\72\result.txt` following `tests\features\result.md` format.

> **Implementation Notes**: Created `tests/features/72/result.txt` documenting old vs new `lfsr_step` assembly, comparison table, and lfsr16 benchmark data.

### Step 3.7 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: `scripts/sync_llvm_mirror.ps1` ran cleanly, syncing `llvm/lib/Target/V6Clang/V6ClangTypeNarrowing.cpp` and `tests/lit/CodeGen/V6Clang/type-narrow-bitwise-const.ll`.

---

## 4. Expected Results

### Example 1 — `u8 lsb = (u8)(lfsr & 1); if (lsb)` (lfsr16 hot loop)

```asm
; Before O90
LXI   B, 1          ; 12cc, 3B
MOV   A, L          ;  8cc, 1B
ANA   C             ;  4cc, 1B
MOV   C, A          ;  8cc, 1B
MOV   A, H          ;  8cc, 1B  ← always 0
ANA   B             ;  4cc, 1B  ← always 0
PUSH  H             ;             spill overhead
MOV   L, C
MOV   H, A
SHLD  ...
POP   H
MOV   A, H          ;  8cc, 1B  ← always 0
ORA   L             ;  4cc, 1B
JNZ   ...           ; 12cc, 3B
; Total: ~76cc + ~32cc spill

; After O90
MOV   A, C          ;  8cc, 1B  ← lfsr lo byte
ANI   1             ;  8cc, 2B  ← immediate, sets Z
JNZ   ...           ; 12cc, 3B
; Total: 28cc
```

### Example 2 — `u8 r = (u8)(x | 0x80)` — or with small constant

```asm
; Before
LXI   D, 0x80       ; 12cc, 3B
MOV   A, L / ORA E / MOV L,A
MOV   A, H / ORA D / MOV H,A  ← 6 insn V6CLANG_OR16

; After
MOV   A, L          ;  8cc, 1B
ORI   0x80          ;  8cc, 2B
```

### Example 3 — `(u8)(x ^ 0x55)` — xor with small constant

```asm
; After: MOV A,L; XRI 0x55    (16cc, 3B)
; vs Before: V6CLANG_XOR16         (36cc, 6B)
```

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Relaxing PHI guard causes spill regression for other benchmarks | Guard relaxation is gated on `allUsersAreZeroTests` — only fires when result is flag-only |
| `or`/`xor` narrowing causes unexpected behaviour | Mathematically identical: hi-byte of `(op i16 X, C)` = 0 iff C ≤ 0xFF; same proof as `and` |
| Benchmark correctness changes | `tests\run_all.py` includes checksum verification for all benchmarks |

---

## 6. Relationship to Other Improvements

- **O89** — dead-hi-byte elision in `expandPostRAPseudo`: operates post-RA;
  O90 operates pre-ISel.  They are complementary and non-overlapping.
- **O85** — type narrowing IV arithmetic users: same pass file, Phase 1.

---

## 7. Future Enhancements

- Extend to `icmp eq (and i16 X, C), K` where K ≠ 0 but K ≤ 0xFF.
- Extend to non-constant RHS when the RHS is provably ≤ 0xFF via KnownBits.

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O90 Design Doc](design\future_plans\O90_pre_isel_i8_narrow_instcombine_undo.md)
