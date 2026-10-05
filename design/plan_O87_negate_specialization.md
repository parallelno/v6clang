# Plan: O87 Negate Specialization for `-x` / `-1*x` / `x*(-1)`

## 1. Problem

### Current behavior

The V6CLANG backend canonicalizes all negate spellings to subtract-from-zero.

For i16 this currently becomes a full `V6CLANG_SUB16` against a materialized zero
pair, e.g.:

```asm
LXI D, 0
MOV A, E
SUB L
MOV L, A
MOV A, D
SBB H
MOV H, A
```

That costs 52cc and, more importantly for V6CLANG, forces an extra register pair
through register allocation.

For i8 result-only negate where the source is already in `A`, current codegen
uses a scratch register:

```asm
MOV L, A
XRA A
SUB L
```

That costs 16cc and burns an unnecessary GR8 temporary.

### Desired behavior

For i16 canonical `sub 0, x`, select a dedicated negate pseudo before RA and
expand it to:

```asm
XRA A
SUB src_lo
MOV dst_lo, A
SBB A
SUB src_hi
MOV dst_hi, A
```

This costs 32cc and avoids creating the zero pair.

For result-only i8 negate when the source is already in `A`, select a dedicated
negate pseudo and expand it to:

```asm
CMA
INR A
```

This costs 12cc and avoids a scratch GR8.

### Root cause

The backend has no dedicated negate pseudo for canonical `sub 0, x`, so generic
subtract lowering survives all the way to post-RA expansion. That preserves
semantic correctness but is suboptimal for both code quality and register
pressure.

## 2. Strategy

### Approach: select canonical `sub 0, x` into new `V6CLANG_NEG16` / `V6CLANG_NEG8`

Add dedicated pseudos in `V6ClangInstrInfo.td`, teach ISel/lowering to recognize
canonical subtract-from-zero, and add post-RA expansion in `V6ClangInstrInfo.cpp`.

For i16 the pseudo must be introduced before RA so the extra zero pair never
exists in the machine IR.

For i8 the pseudo is legal only for result-only arithmetic, because `CMA; INR A`
does not reproduce subtraction-style carry semantics.

### Why this works

- i16: removes an entire artificial GR16 live range and produces a strictly
  better expansion.
- i8: preserves the existing good non-`A` and memory-source paths while
  specializing the accumulator case.
- Both changes target the canonical DAG shape rather than front-end spelling,
  so they naturally cover `-x`, `-1*x`, and `x*(-1)`.

### Summary of changes

- Add `V6CLANG_NEG16` pseudo and post-RA expansion.
- Add `V6CLANG_NEG8` pseudo and post-RA expansion.
- Teach lowering/selection to form those pseudos from canonical `sub 0, x`.
- Add lit coverage.
- Add feature test folder 69 and compare old/new assembly.

## 3. Implementation Steps

### Step 3.1 — Create O87 feature plan and baseline feature folder [x]

Create this plan and create `tests\features\69\{v6clang.c,c8080.c}` with a
baseline negate-focused testcase.

> **Implementation Notes**: Created this plan plus `tests\features\69\{v6clang.c,c8080.c}`. Generated baseline `tests\features\69\v6clang_old.asm` and `tests\features\69\c8080.asm`.

### Step 3.2 — Add `V6CLANG_NEG16` pseudo and selection [x]

**Files**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td`,
`llvm-project/llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp`

Recognize canonical i16 `sub 0, x` and select a dedicated negate pseudo before
RA.

> **Design Notes**: The main goal is to prevent the zero pair from reaching RA.
> **Implementation Notes**: Added `V6CLANG_NEG16` in `V6ClangInstrInfo.td` and matched canonical i16 `sub 0, x` before RA so the artificial zero pair never enters allocation.

### Step 3.3 — Add `V6CLANG_NEG16` post-RA expansion [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`

Expand `V6CLANG_NEG16` to the 36cc `XRA/SUB/MVI/SBB` sequence.

> **Implementation Notes**: Implemented `V6CLANG_NEG16` expansion in `V6ClangInstrInfo.cpp` as `XRA; SUB; MOV; MVI 0; SBB; MOV`. Verified annotated probe and feature asm both show `;--- V6CLANG_NEG16 ---`.

### Step 3.4 — Add `V6CLANG_NEG8` pseudo and selection [x]

**Files**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td`,
`llvm-project/llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp`

Recognize result-only i8 `sub 0, x` and select a dedicated negate pseudo.

> **Design Notes**: This must not fire on flag-producing subtract paths.
> **Implementation Notes**: Added `V6ClangISD::NEG8` / `V6CLANG_NEG8`. Initial generic `sub i8 0, x` match regressed memory-source byte negates, so final lowering only forms `NEG8` when the RHS DAG value is already copied from incoming `A`.

### Step 3.5 — Add `V6CLANG_NEG8` post-RA expansion [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`

Use `CMA; INR A` only for the `src == A` case. Keep subtract-based emission for
other shapes.

> **Implementation Notes**: `V6CLANG_NEG8` now emits `CMA; INR A` when the source is in `A`, otherwise falls back to subtract-based emission. Added a post-RA fold for an immediately preceding `MOV src, A` so RA-inserted accumulator copies do not hide the fast path.

### Step 3.6 — Build [x]

Build with:

```text
cmd /c "call \"\"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat\"\" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Rebuilt `clang` and `llc` successfully after each backend change using the documented MSVC+ninja command.

### Step 3.7 — Lit test: negate specialization [x]

Add a focused CodeGen lit test covering:

- i16 `-x`
- i16 `-1*x`
- i16 `x*(-1)`
- i8 accumulator negate win
- non-`A`/memory-source non-regression
- flag-sensitive i8 subtract non-match

> **Implementation Notes**: Added `llvm-project/llvm/test/CodeGen/V6CLANG/negate-specialization.ll`. It locks in i16 canonical negates, i8 accumulator specialization, non-`A` i8 fallback, and memory-source non-regression. Front-end spellings (`-x`, `-1*x`, `x*(-1)`) are covered by feature test 69. A temporary `temp\neg8_flag_check.ll` spot-check confirmed the flag-consuming zero-compare path did not form `V6CLANG_NEG8`.

### Step 3.8 — Run regression tests [x]

Run the relevant regression scope at minimum, and widen if needed.

> **Implementation Notes**: `python tests\run_all.py` passed all 3 suites. During the run, `tests\lit\CodeGen\V6CLANG\conditional-call.ll` exposed stale signed zero-condition expectations (`CM`/`CP` were reversed); updated the checks and reran the full suite to green.

### Step 3.9 — Verification assembly steps from `tests\features\README.md` [x]

Compile baseline old asm and post-change new asm for feature folder 69.

> **Implementation Notes**: Generated `tests\features\69\v6clang_new01.asm`. Verified all i16 local/global negates use `V6CLANG_NEG16`, `neg_i8_unary` uses `V6CLANG_NEG8` (`CMA; INR A`), and `neg_i8_global_unary` intentionally remains `V6CLANG_SUB_M_P`.

### Step 3.10 — Make sure result.txt is created [x]

Create `tests\features\69\result.txt` with the required code/asm/stats
comparison.

> **Implementation Notes**: Created `tests\features\69\result.txt` with the test code, converted c8080 asm, c8080 stats, old/new V6CLANG asm, and comparison tables.

### Step 3.11 — Sync mirror [x]

Run `pwsh scripts\sync_llvm_mirror.ps1` after verification is complete.

> **Implementation Notes**: Ran `powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1` successfully after verification and regression.

## 4. Expected Results

### Example 1 — i16 negate

`-x`, `-1*x`, and `x*(-1)` on `int` should stop materializing a zero pair and
should shrink from 52cc/9B to 32cc/6B.

### Example 2 — i8 negate in accumulator

Signed i8 negate when the operand is already in `A` should collapse from the
scratch-register pattern to `CMA; INR A`.

### Example 3 — Register-pressure improvement

The i16 path should reduce pair pressure by eliminating an artificial zero live
range, which is especially valuable on the 3-pair V6CLANG machine.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| i8 negate could break carry-sensitive paths | Restrict `V6CLANG_NEG8` to result-only arithmetic; do not match flag-producing subtracts |
| Late formation would miss the RA benefit | Form `V6CLANG_NEG16` before RA from canonical `sub 0, x` |
| Non-`A` i8 shapes could regress | Keep subtract-based emission for non-`A` and memory-source cases |

---

## 6. Relationship to Other Improvements

O87 complements O75 flag-producing arithmetic SDNodes and O80's liveness-aware
zero-test specialization: both existing features already separate result-only
arithmetic from flag-sensitive paths.

## 7. Future Enhancements

- Extend negate specialization to additional canonicalized arithmetic forms if
  new profitable shapes appear.
- Consider matching wider complement-plus-increment idioms in handwritten
  runtime helpers once the backend path is stable.

## 8. References

- [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
- [V6CLANG Timings](docs\V6ClangInstructionTimings.md)
- [Future Improvements](design\future_plans\README.md)
- [O87 Design](design\future_plans\O87_negate_specialization.md)
