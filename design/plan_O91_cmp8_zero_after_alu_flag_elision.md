# Plan: O91 — Elide V6CLANG_CMP8_ZERO After Flag-Setting ALU Op (MOV R,A bridge)

## 1. Problem

### Current behavior

After O89 (dead hi-byte elision in `V6CLANG_XOR16`/`V6CLANG_AND16`/`V6CLANG_OR16`), a
`(u8)(a OP b) == 0` comparison emits:

```asm
;--- V6CLANG_XOR16 (DstHi dead, O89) ---
MOV  A, E          ;  8cc  1B   A = lhs_lo
XRA  L             ;  4cc  1B   A = lo result, Z = (result==0) ← VALID Z
MOV  L, A          ;  8cc  1B   DstLo = result; FLAGS untouched
;--- V6CLANG_CMP8_ZERO L (shape 2) ---
XRA  A             ;  4cc  1B   ← Z already valid — REDUNDANT
CMP  L             ;  4cc  1B   ← REDUNDANT
JZ   .zero
```

`XRA L` sets `Z = (result == 0)`. `MOV L, A` does not touch FLAGS. The
entire `XRA A; CMP L` expansion of `V6CLANG_CMP8_ZERO L` is provably redundant.

### Desired behavior

```asm
;--- V6CLANG_XOR16 (DstHi dead, O89+O91) ---
MOV  A, E          ;  8cc  1B
XRA  L             ;  4cc  1B   Z = (result==0) — used directly
JZ   .zero         ; 12cc  3B
```

`MOV L, A`, `XRA A`, and `CMP L` are all dropped (−16cc, −3B per site).

### Root cause

`V6ClangRedundantFlagElim` only eliminates `ORA A` / `ANA A` (identity
operations). It has no concept of "register R holds A's value at the time Z
was last set," so it cannot recognise that `XRA A; CMP R` restates the same
Z bit that a prior ALU op already produced.

The pattern the pass misses:

```
<ALU writes A, sets Z>   ; ZFlagValid = true; A = result
MOV R, A                 ; R = result; A, FLAGS untouched
XRA A                    ; ZFlagValid is true — but pass does not check here
CMP R                    ; Z recalculated identically, then ZFlagValid = false
```

---

## 2. Strategy

### Approach: extend `V6ClangRedundantFlagElim` with `AValueRegs` tracker

Alongside the existing `bool ZFlagValid`, add:

```cpp
SmallSet<Register, 4> AValueRegs;          // regs that equal A's last-ALU value
DenseMap<Register, MachineInstr *> AValueSrc; // the MOV R,A that wrote each reg
```

**State transitions** (in `runOnMachineFunction`):

| Trigger | ZFlagValid | AValueRegs / AValueSrc |
|---------|------------|------------------------|
| `isAluWritesAAndFlags(MI)` | → true | clear both; insert A (no src MI needed for A itself) |
| `MOV R, A` while `ZFlagValid && R != A` | unchanged | insert R → &MI in AValueSrc |
| `isWritesANoFlags` (dst = A) | → false | clear both |
| `isWritesFlagsNoA` or control flow | → false | clear both |
| anything else | unchanged | unchanged (unless R explicitly written) |

**New elimination rule** (fires before state update):

When `ZFlagValid == true` and the current instruction is `XRA A`:
1. Peek at the immediately following MI.
2. If it is `CMP R` with `R ∈ AValueRegs`:
   - Erase `AValueSrc[R]` (the `MOV R, A` — now a dead store).
   - Erase `XRA A`.
   - Erase `CMP R`.
   - Do NOT advance `ZFlagValid` or clear `AValueRegs`; Z is still valid.
   - `Changed = true`; continue scan.

### Why this works

After `XRA L` (or any `isAluWritesAAndFlags` op), A holds the result and
Z is correct. `MOV L, A` copies that same value to L without touching FLAGS.
At `XRA A`, Z is still valid and L == A, so `XRA A` produces the all-zero
result; `CMP L` then just computes `0 ^ 0 = 0` and sets Z again — identical
to the existing Z. The sequence is provably a no-op w.r.t. flags.

Guards against false firing:
- `XRA A` with `ZFlagValid = false` → not a zero-clear shaped as CMP (skip).
- `CMP R` with `R ∉ AValueRegs` → R may not equal A's ALU result (skip).
- If `R ∈ AValueRegs` but has additional uses after `CMP R` → the `MOV R, A`
  erasure would be wrong; guard with a liveness check before erasing `AValueSrc[R]`.

### Summary of changes

| File | Change |
|------|--------|
| `llvm-project/llvm/lib/Target/V6Clang/V6ClangRedundantFlagElim.cpp` | Add `AValueRegs` / `AValueSrc`; new elimination rule for `XRA A` + `CMP R` pattern |
| `llvm-project/llvm/test/CodeGen/V6Clang/cmp8-zero-redundant-after-alu.ll` | New lit test: three ops × dead/live hi; control cases |
| `tests/features/73/` | Feature test: C source, baseline, new asm, result.txt |

---

## 3. Implementation Steps

### Step 3.1 — Add `AValueRegs` / `AValueSrc` trackers to `V6ClangRedundantFlagElim` [ ]

**File:** `llvm-project/llvm/lib/Target/V6Clang/V6ClangRedundantFlagElim.cpp`

Inside `runOnMachineFunction`, alongside `bool ZFlagValid`, declare:

```cpp
SmallSet<Register, 4> AValueRegs;
DenseMap<Register, MachineInstr *> AValueSrc;
```

#### Helper: `isMOVrA`

Add a private static helper that returns the destination register when MI is
`MOV R, A` (i.e. `MOVrr` with src = A, dst ≠ A), or `NoRegister` otherwise:

```cpp
static Register getMOVrADest(const MachineInstr &MI) {
  if (MI.getOpcode() != V6CLANG::MOVrr)
    return Register();
  Register Dst = MI.getOperand(0).getReg();
  Register Src = MI.getOperand(1).getReg();
  return (Src == V6CLANG::A && Dst != V6CLANG::A) ? Dst : Register();
}
```

#### Elimination rule — insert **before** the existing state-update block:

```cpp
// O91: XRA A immediately followed by CMP R where R∈AValueRegs
// → both are redundant when ZFlagValid (Z already reflects A's ALU result).
if (ZFlagValid && isXraA(MI)) {
  auto NextIt = std::next(MI.getIterator());
  if (NextIt != MBB.end()) {
    MachineInstr &NextMI = *NextIt;
    if (NextMI.getOpcode() == V6CLANG::CMPr) {
      Register CmpSrc = NextMI.getOperand(1).getReg();
      if (AValueRegs.count(CmpSrc)) {
        // Check that the MOV R,A bridge is not used elsewhere after CMP R.
        MachineInstr *BridgeMI = AValueSrc.lookup(CmpSrc);
        bool BridgeSafe = !BridgeMI || isBridgeDead(CmpSrc, NextIt, MBB);
        if (BridgeSafe) {
          if (BridgeMI) BridgeMI->eraseFromParent();
          MI.eraseFromParent();      // XRA A
          NextMI.eraseFromParent(); // CMP R
          Changed = true;
          // ZFlagValid and AValueRegs unchanged — Z still valid from prior ALU.
          continue;
        }
      }
    }
  }
}
```

`isXraA` is a new private helper (analogous to `isOraA` / `isAnaA`):

```cpp
static bool isXraA(const MachineInstr &MI) {
  if (MI.getOpcode() != V6CLANG::XRAr) return false;
  // XRAr: (outs Acc:$dst), (ins Acc:$lhs, GR8:$rs)
  return MI.getOperand(2).getReg() == V6CLANG::A;
}
```

`isBridgeDead` scans from `NextIt+1` to end-of-block and successor liveins
to confirm `CmpSrc` is not read:

```cpp
static bool isBridgeDead(Register R, MachineBasicBlock::iterator After,
                         const MachineBasicBlock &MBB) {
  // Scan remaining instructions in block.
  for (auto It = std::next(After), E = MBB.end(); It != E; ++It) {
    if (It->readsRegister(R)) return false;
    if (It->definesRegister(R)) return true; // redefined before any use
  }
  // Check successor liveins.
  for (const MachineBasicBlock *Succ : MBB.successors())
    if (Succ->isLiveIn(R)) return false;
  return true;
}
```

#### State update additions — insert **after** the existing update block:

```cpp
// Track MOV R,A copies that propagate the ALU result.
if (ZFlagValid) {
  Register MovDst = getMOVrADest(MI);
  if (MovDst.isValid()) {
    AValueRegs.insert(MovDst);
    AValueSrc[MovDst] = &MI;
    continue; // handled; do not fall into the reset path
  }
}

// Any write to a reg in AValueRegs (other than the MOV R,A already handled)
// invalidates it.
for (const MachineOperand &MO : MI.operands()) {
  if (MO.isReg() && MO.isDef()) {
    Register DefReg = MO.getReg();
    AValueRegs.erase(DefReg);
    AValueSrc.erase(DefReg);
  }
}
```

Also clear both trackers wherever `ZFlagValid` is set to false:

```cpp
// (existing reset sites)
} else if (isWritesANoFlags(MI) || isWritesFlagsNoA(MI)) {
  ZFlagValid = false;
  AValueRegs.clear(); AValueSrc.clear();
} else if (isControlFlow(MI)) {
  ZFlagValid = false;
  AValueRegs.clear(); AValueSrc.clear();
}
```

And clear both when `isAluWritesAAndFlags` fires:

```cpp
if (isAluWritesAAndFlags(MI)) {
  ZFlagValid = true;
  AValueRegs.clear(); AValueSrc.clear();
  AValueRegs.insert(V6CLANG::A); // A holds the fresh result (no bridge MI)
```

> **Design Notes:**
> - The tracker only needs `MOVrr` with src=A. `LDA`/`LDAX`/`POP PSW` write A
>   without setting FLAGS and already cause `ZFlagValid=false`, so they
>   implicitly reset the trackers too.
> - `AValueRegs` is cheap: at most a handful of registers (B/C/D/E/H/L) can
>   hold a copy of A between two ALU ops in a typical BB.
> - The `isBridgeDead` check is conservative (false → keep bridge, no opt).
>   This ensures correctness in unusual RA outputs where DstLo has extra uses.

> **Implementation Notes:** (fill after completion)

---

### Step 3.2 — Build [ ]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes:** (fill after completion)

---

### Step 3.3 — New lit test `cmp8-zero-redundant-after-alu.ll` [ ]

**File:** `llvm-project/llvm/test/CodeGen/V6Clang/cmp8-zero-redundant-after-alu.ll`

Cover the following cases:

| Function | Pattern | Expected (O91) |
|----------|---------|----------------|
| `xor16_cmp_zero` | `(u8)(i16^i16)==0` | `MOV A,r; XRA r; J{Z,NZ}` (no XRA A / CMP) |
| `and16_cmp_zero` | `(u8)(i16&i16)==0` | `MOV A,r; ANA r; J{Z,NZ}` |
| `or16_cmp_zero`  | `(u8)(i16\|i16)==0` | `MOV A,r; ORA r; J{Z,NZ}` |
| `xor16_to_i8` | no zero-test, DstHi dead | unchanged from O89 (3 insn) — no regression |
| `xor16_full` | full i16 result | unchanged (6 insn) — no regression |
| `xor8_cmp_zero` | pure i8 XOR==0 | not affected by O91 (no MOV bridge) |

Key FileCheck directives:

```llvm
; CHECK-LABEL: xor16_cmp_zero:
; CHECK:       MOV A,
; CHECK-NEXT:  XRA
; CHECK-NOT:   MOV {{[BCDEHL]}}, A
; CHECK-NOT:   XRA A
; CHECK-NOT:   CMP
; CHECK:       J{{Z|NZ}}
```

> **Implementation Notes:** (fill after completion)

---

### Step 3.4 — Run lit test [ ]

```
llvm-build\bin\llvm-lit llvm-project\llvm\test\CodeGen\V6Clang\cmp8-zero-redundant-after-alu.ll -v
```

> **Implementation Notes:** (fill after completion)

---

### Step 3.5 — Run regression tests [ ]

```
python tests\run_all.py
```

All tests must pass (current baseline: all green).

> **Implementation Notes:** (fill after completion)

---

### Step 3.6 — Verification assembly (from `tests\features\README.md`) [ ]

Compile `tests/features/73/v6clang.c` with the new compiler:

```
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S tests\features\73\v6clang.c -o tests\features\73\v6clang_new01.asm
```

Verify:
- `xor16_cmp_zero`: 3 instructions (`MOV A,r; XRA r; Jcc`), 8B, 44cc worst
- `and16_cmp_zero`: 3 instructions (`MOV A,r; ANA r; Jcc`), 8B, 44cc worst
- `or16_cmp_zero`:  3 instructions (`MOV A,r; ORA r; Jcc`), 8B, 44cc worst
- `xor16_to_i8`:   unchanged — `MOV A,r; XRA r; RET`
- `xor16_full`:    unchanged — full 6-instruction sequence

> **Implementation Notes:** (fill after completion)

---

### Step 3.7 — Create `result.txt` (from `tests\features\result.md`) [ ]

Create `tests/features/73/result.txt` with:
- C test case code
- c8080 asm (main + all functions, converted to i8080 mnemonics)
- c8080 stats table (worst cycles, bytes per function)
- v6clang old asm (from `v6clang_old.asm`)
- v6clang new asm (from `v6clang_new01.asm`)
- Comparison table: c8080 / v6clang-old / v6clang-new (cycles, bytes)

> **Implementation Notes:** (fill after completion)

---

### Step 3.8 — Sync mirror [ ]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

Verify that `llvm/lib/Target/V6Clang/V6ClangRedundantFlagElim.cpp` and
`tests/lit/CodeGen/V6Clang/cmp8-zero-redundant-after-alu.ll` reflect the changes.

> **Implementation Notes:** (fill after completion)

---

## 4. Expected Results

### Example 1 — `xor16_cmp_zero`

```c
u8 xor16_cmp_zero(u16 a, u16 b) { return (u8)(a ^ b) == 0; }
```

**Before O91 (after O89):** 60cc, 11B
```asm
    MOV  A, E
    XRA  L
    MOV  L, A
    XRA  A
    CMP  L
    JZ   .zero
    XRA  A
    RET
.zero:
    INR  A
    RET
```

**After O91:** 44cc, 8B (−16cc, −3B)
```asm
    MOV  A, E
    XRA  L
    JZ   .zero
    XRA  A
    RET
.zero:
    INR  A
    RET
```

### Example 2 — `and16_cmp_zero`

```c
u8 and16_cmp_zero(u16 a, u16 b) { return (u8)(a & b) == 0; }
```

Same saving: `MOV L,A + XRA A + CMP L` (−16cc, −3B) dropped.

### Example 3 — `or16_cmp_zero`

```c
u8 or16_cmp_zero(u16 a, u16 b) { return (u8)(a | b) == 0; }
```

Same saving.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `AValueSrc[R]` bridge MI erased while R still has other uses | `isBridgeDead` check before erasure; conservative: skip opt if R live |
| O61 patched-imm symbol on `MOV R, A` (MO_PATCH_IMM) | `getMOVrADest` checks `getTargetFlags() == 0`; patched MOVs are skipped |
| Pre-instr-symbol on `XRA A` or `CMP R` | Check `getPreInstrSymbol()` on both before erasing; skip opt if set |
| `DenseMap` invalidation if `BridgeMI` is erased during iterator walk | Erase `BridgeMI` first (it is earlier in the block), then erase `XRA A` / `CMP R` |
| False trigger when `ZFlagValid` is true from a different prior op | Harmless: `XRA A; CMP R` with `R == A's value` is always a flag no-op |

---

## 6. Relationship to Other Improvements

- **O89** (dead hi-byte elision) creates the `MOV R,A; XRA A; CMP R` sequence
  that O91 eliminates. Without O89 the full 6-instruction pair expansion lands
  in A, so `V6CLANG_CMP8_ZERO` fires shape 1 (`ORA A`) which `V6ClangRedundantFlagElim`
  already handles.
- **O80** (`V6CLANG_CMP8_ZERO` pseudo) introduced the shape 2 (`XRA A; CMP R`)
  expansion path that O91 targets.
- **O17** (`V6ClangRedundantFlagElim`) is the pass being extended.

---

## 7. Future Enhancements

- Generalise to other flag-preserving `MOV`-chain lengths (e.g. `MOV B,A; MOV C,B`),
  though this is unlikely to arise naturally from ISel.
- Extend to `ANA A; CMP R` (shape 2 of a future ANA-based zero-test), if added.

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [Design doc](design\future_plans\O91_cmp8_zero_after_alu_flag_elision.md)
* [V6ClangRedundantFlagElim.cpp](llvm\lib\Target\V6Clang\V6ClangRedundantFlagElim.cpp)
