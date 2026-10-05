# Plan: O89 — Dead High-Byte Elision in V6CLANG_AND16 / V6CLANG_OR16 / V6CLANG_XOR16

## 1. Problem

### Current behavior

`V6CLANG_AND16`, `V6CLANG_OR16`, and `V6CLANG_XOR16` always expand to the full 6-instruction
pair-wise sequence in `expandPostRAPseudo`, even when only the low byte of the
result is consumed and `DstHi` is provably dead.

Example — `(u8)(a ^ b)` where both operands are i16:

```asm
;--- V6CLANG_XOR16 ---
MOV  A, E          ; load LhsLo          8cc  1B
XRA  L             ; lo result → A       4cc  1B
MOV  L, A          ; DstLo = L           8cc  1B
MOV  A, D          ; load LhsHi  ← DEAD 8cc  1B
XRA  H             ; hi result    ← DEAD 4cc  1B
                   ; MOV H,A elided by AccPlan (hi never stored)
MOV  A, L          ; reload DstLo        8cc  1B  ← required by hi clobber
RET
; Total: 40cc, 6B
```

The two dead hi-byte instructions clobber A, which forces an extra
`MOV A, DstLo` reload — three wasted instructions in total.

### Desired behavior

```asm
;--- V6CLANG_XOR16 (dead-hi path) ---
MOV  A, E          ; 8cc  1B
XRA  L             ; 4cc  1B
RET                ;      ← A = lo result, no hi work at all
; Total: 12cc, 2B  (AccumulatorPlanning removes MOV L,A + MOV A,L round-trip)
```

### Root cause

In `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp` the
`V6CLANG_AND16` / `V6CLANG_OR16` / `V6CLANG_XOR16` expansion case has no liveness check
before emitting the high-byte sequence:

```cpp
// hi byte — unconditional, even when DstHi is dead
BuildMI(…, MOVrr, A).addReg(LhsHi);
BuildMI(…, OpOpc, A).addReg(A).addReg(RhsHi);
BuildMI(…, MOVrr, DstHi).addReg(A);
```

`isRegDeadAfter` is already used at 10+ other sites in the same file for
exactly this purpose (e.g. V6CLANG_SRA16_RAM_LO line 2720). No new
infrastructure is needed.

---

## 2. Strategy

### Approach: `isRegDeadAfter` guard in `expandPostRAPseudo`

Add a single dead-hi liveness check before the high-byte block in the
shared `V6CLANG_AND16`/`V6CLANG_OR16`/`V6CLANG_XOR16` expansion.

### Why this works

Post-RA liveness is fully computed when `expandPostRAPseudo` fires.
`isRegDeadAfter(MBB, MI.getIterator(), DstHi, &RI)` reliably returns `true`
whenever `DstHi` has no live consumers after the pseudo — exactly the case
for any `(u8)(a OP b)` truncation. The AccumulatorPlanning pass (which runs
before PEI) then observes that A still holds the lo result and removes the
`MOV DstLo, A; MOV A, DstLo` round-trip.

### Summary of changes

| File | Change |
|------|--------|
| `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp` | One `isRegDeadAfter` guard wrapping the 3 hi-byte `BuildMI` calls |
| `llvm-project/llvm/test/CodeGen/V6CLANG/bitwise16-dead-hi.ll` | New lit test covering all 3 ops × dead/live hi cases |
| `tests/features/71/` | Feature test: C source, baseline, new asm, result.txt |
| `design/future_plans/O89_dead_hi_byte_bitwise_ops.md` | Mark complete |
| `design/future_plans/README.md` | ✅ O89 |

---

## 3. Implementation Steps

### Step 3.1 — Add dead-hi guard in V6ClangInstrInfo.cpp [x]

In `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`,
`expandPostRAPseudo` case `V6CLANG_AND16`/`V6CLANG_OR16`/`V6CLANG_XOR16`:

Before the hi-byte block, insert:
```cpp
bool HiDead = isRegDeadAfter(MBB, MI.getIterator(), DstHi, &RI);
```
Then wrap the three hi-byte `BuildMI` calls with `if (!HiDead) { ... }`.

The lo-byte block (always needed) stays unconditional.

> **Design Notes**: `DstHi` must be queried using the *pair* register's
> hi sub-register, which is already computed as `MCRegister DstHi = RI.getSubReg(DstReg, V6CLANG::sub_hi)`.
> This is the same pattern used at line 2720 (`V6CLANG_SRA16_RAM_LO`).

> **Implementation Notes**: Added `bool HiDead = isRegDeadAfter(MBB, MI.getIterator(), DstHi, &RI);` and wrapped the 3 hi-byte `BuildMI` calls in `if (!HiDead) { ... }`. Build was clean.

### Step 3.2 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: `ninja -C llvm-build clang llc` — 5/5 targets, `clang.exe` linked. Zero errors.

### Step 3.3 — Lit test: bitwise16-dead-hi.ll [x]

Create `llvm-project/llvm/test/CodeGen/V6CLANG/bitwise16-dead-hi.ll` covering:

- `xor16_dead_hi` — `trunc (xor i16, i16) to i8`: expect 2 insn, no hi-byte XRAr/MOVrr
- `or16_dead_hi` — `trunc (or i16, i16) to i8`: expect 2 insn, no ORAr for hi
- `and16_dead_hi` — `trunc (and i16, i16) to i8`: expect 2 insn, no ANAr for hi
- `xor16_live_hi` — full `xor i16, i16` (both halves consumed): expect full 6-insn form
- `xor_bytes` — `trunc (xor (lshr i16 by 8), i16) to i8`: checksum pattern

Run: `llvm-build\bin\llc -march=i8080 -mtriple=i8080-unknown-v6clang -verify-machineinstrs
      llvm-project\llvm\test\CodeGen\V6CLANG\bitwise16-dead-hi.ll -o - | FileCheck ...`

Or via lit: `llvm-build\bin\llvm-lit llvm-project\llvm\test\CodeGen\V6CLANG\bitwise16-dead-hi.ll`

> **Implementation Notes**: Created `bitwise16-dead-hi.ll` with 8 functions (3 dead-hi, 2 cmp-zero dead-hi, 3 live-hi control). `CHECK-NOT: XRA {{[BCDEHL]}}` pattern used to avoid false positive from `XRA A` emitted by CMP8_ZERO shape 2. PASS.

### Step 3.4 — Run regression tests [x]

```
python tests\run_all.py
```

All lit + golden tests must pass.

> **Implementation Notes**: 16/16 golden, 149/149 lit (including new `bitwise16-dead-hi.ll`), 5/5 benchmarks. All PASS.

### Step 3.5 — Verification assembly steps from `tests\features\README.md` [x]

Compile the new feature assembly:
```
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S
    tests\features\71\v6clang.c
    -o tests\features\71\v6clang_new01.asm
    -mllvm -mv6clang-annotate-pseudos
```

Examine each function for:
- Dead hi-byte XRA/ORA/ANA + MOVrr gone
- `MOV DstLo, A; MOV A, DstLo` round-trip eliminated by AccumulatorPlanning
- Return/comparison paths correct

> **Implementation Notes**: `v6clang_new01.asm` confirmed — `xor16_to_i8`, `or16_to_i8`, `and16_to_i8`, `xor_bytes` all 3 instructions. `xor16_full` unchanged (6 instructions). Improvements visible as expected.

### Step 3.6 — Make sure result.txt is created. `tests\features\README.md` [x]

Create `tests\features\71\result.txt` following the standard layout:
- C test case code
- c8080 asm (main + dependent functions, i8080 syntax)
- c8080 stats: worst CPU cycles, length in bytes per function
- v6clang old asm
- v6clang new asm
- Comparison table: c8080 / v6clang old / v6clang new

> **Implementation Notes**: `tests/features/71/result.txt` created with C code, c8080 asm, stats, old/new asm comparison, and summary table.

### Step 3.7 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: `scripts\sync_llvm_mirror.ps1` — Mirror sync complete.

---

## 4. Expected Results

### Example 1 — `(u8)(a ^ b)` return (xor16_to_i8)

```asm
; Before O89
MOV  A, E    ; 8cc
XRA  L       ; 4cc
MOV  L, A    ; 8cc
MOV  A, D    ; 8cc  ← dead
XRA  H       ; 4cc  ← dead
MOV  A, L    ; 8cc  ← dead (reload after hi clobber)
RET
; 40cc, 6B

; After O89 + AccumulatorPlanning
MOV  A, E    ; 8cc
XRA  L       ; 4cc
RET
; 12cc, 2B  (−28cc, −4B)
```

### Example 2 — `(u8)a ^ (u8)(a>>8)` (bench_finish checksum, xor_bytes)

```asm
; Before O89
MOV  A, H    ; 8cc  (SRL16_BYTE: H = hi byte = lo of a>>8)
XRA  L       ; 4cc
MOV  L, A    ; 8cc
XRA  A       ; 4cc  ← dead (LhsHi for V6CLANG_XOR16 after SRL16_BYTE = 0)
XRA  H       ; 4cc  ← dead
MOV  A, L    ; 8cc  ← reload
RET
; 36cc, 6B

; After O89 + AccumulatorPlanning
MOV  A, H    ; 8cc
XRA  L       ; 4cc
RET
; 12cc, 2B  (−24cc, −4B)
```

### Example 3 — `(u8)(a & b) == 0` (and16_cmp_zero)

```asm
; Before O89
MOV  A, L    ; 8cc
ANA  E       ; 4cc
MOV  L, A    ; 8cc
MOV  A, H    ; 8cc  ← dead
ANA  D       ; 4cc  ← dead
; V6CLANG_CMP8_ZERO: XRA A; CMP L (shape 2, because A ≠ lo result)
XRA  A       ; 4cc
CMP  L       ; 4cc
JZ / JNZ ...

; After O89  (A = lo result after ANA E; ORA A picks shape 1)
MOV  A, L    ; 8cc
ANA  E       ; 4cc
; V6CLANG_CMP8_ZERO: ORA A (shape 1, flags from ANA already set!)
ORA  A       ; 4cc   ← actually Z is already set, ZeroTestOpt may remove even this
JZ / JNZ ...
; −16cc, −3B
```

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `isRegDeadAfter` false-positive on implicit pair kill | The helper already handles the super-register implicit-kill artifact (see repo notes). Same guard used at 10+ existing sites. |
| AccumulatorPlanning not removing the `MOV DstLo, A` round-trip | AccPlan tracks A content after every ALU op; if it doesn't fire the code is still correct — just misses the bonus saving. |
| CMP8_ZERO shape selection regression | CMP8_ZERO shape is chosen at expansion time; with A = lo result (shape 1 `ORA A`) it is now always available for the `HiDead` path. No risk of regression on the live-hi path. |
| Golden test checksum change | All golden tests use full i16 arithmetic where both halves are live. Dead-hi only fires when the result is explicitly truncated to i8. |

---

## 6. Relationship to Other Improvements

- **O82 (mov-chain-collapse-dead-hi)**: Complementary — O82 collapses redundant `MOV DstHi, X` stores post-expansion; O89 prevents emitting them in the first place.
- **O80 (CMP8_ZERO)**: The CMP8_ZERO shape improves further after O89 — with A = lo result after a dead-hi op, shape 1 (`ORA A`) becomes always available for the truncated-bitop-then-compare pattern.
- **AccumulatorPlanning**: Produces the full 2-instruction return sequence by observing that A still equals DstLo when the hi block is skipped.

---

## 7. Future Enhancements

- **OR16 flag-already-set**: For `V6CLANG_OR16` with `HiDead=true`, the lo-byte
  `ORA RhsLo` already sets Z correctly for the truncated result. A follow-on
  patch can detect this and suppress the downstream `V6CLANG_CMP8_ZERO` entirely.
- **AND16 immediate**: `(u8)(x & IMM)` where IMM < 256 — when `HiDead=true`,
  the hi half `LXI` constant is 0 or 0xFF and can be strength-reduced further.

---

## 8. References

- [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
- [Vector 06c CPU Timings](docs\V6ClangInstructionTimings.md)
- [Future Improvements](design\future_plans\README.md)
- [Feature Description](design\future_plans\O89_dead_hi_byte_bitwise_ops.md)
- [Feature Test](tests\features\71\)
