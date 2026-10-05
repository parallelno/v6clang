# Plan: Dual Cost Model (Bytes + Cycles) for V6CLANG

## 1. Problem

### Current behavior

V6CLANG optimization decisions (peephole replacements, pseudo expansion choices,
copy elimination) are ad-hoc — each pass uses hardcoded heuristics. For
example, the `V6CLANG_ADD16` expansion replaces `LXI+DAD` with INX chains when
the constant is `±1..±3`, a threshold chosen manually based on the comment
"INX 8cc beats LXI+DAD 24cc":

```cpp
// V6ClangInstrInfo.cpp — V6CLANG_ADD16 expansion (current)
if (ImmVal >= 1 && ImmVal <= 3) {
  Opc = V6CLANG::INX;
  Count = static_cast<unsigned>(ImmVal);
} else if (ImmVal >= -3 && ImmVal <= -1) {
  Opc = V6CLANG::DCX;
  Count = static_cast<unsigned>(-ImmVal);
}
```

The same hardcoded `±1..±3` range appears in the `V6CLANG_SUB16` expansion.
There is no way to express "prefer speed" vs "prefer size" vs "balanced",
and `-Os`/`-Oz` flags have no effect on backend decision-making.

### Desired behavior

A unified `V6ClangInstrCost` struct captures both byte count and cycle cost for
instruction sequences. A single `isCheaperThan(other, mode)` method composes
them based on the function's optimization goal:

- **Size mode** (`-Os`/`-Oz`): bytes dominate, cycles break ties
- **Speed mode** (`-O2`/`-O3`): cycles dominate, bytes break ties
- **Balanced** (`-O1`): sum of bytes + cycles

The INX/DCX threshold is then derived automatically:

```
3×INX = {3 bytes, 24cc}  vs  LXI+DAD = {4 bytes, 24cc}
  Speed: (24<<32)+3 < (24<<32)+4  →  INX wins  ✓
  Size:  (3<<32)+24 < (4<<32)+24  →  INX wins  ✓

4×INX = {4 bytes, 32cc}  vs  LXI+DAD = {4 bytes, 24cc}
  Speed: (32<<32)+4 > (24<<32)+4  →  DAD wins  ✓
  Size:  (4<<32)+32 > (4<<32)+24  →  DAD wins  ✓
```

### Root cause

No cost infrastructure exists. Each pass reimplements its own break-even
analysis as magic constants. This prevents `-Os`/`-Oz` support, makes new
optimizations fragile, and blocks future cost-aware passes (O12, O13).

---

## 2. Strategy

### Approach: Header-only `V6ClangInstrCost` struct + initial wiring

Create a lightweight `V6ClangInstrCost.h` header with:
- `V6ClangInstrCost{Bytes, Cycles}` struct
- `V6ClangOptMode` enum (`Speed`, `Size`, `Balanced`)
- `value(mode) → int64_t` composition method
- `isCheaperThan(rhs, mode)` comparison
- `operator+`, `operator*` for composing sequence costs
- `getV6ClangOptMode(MachineFunction)` helper to derive mode from attributes
- `V6ClangCost` namespace with pre-defined constants for common instructions

Then wire it into the two existing hardcoded threshold decisions in
`V6ClangInstrInfo.cpp` (ADD16 and SUB16 INX/DCX chain selection).

### Why this works

- **Header-only**: no new `.cpp` file, no CMakeLists change, zero runtime
  overhead when not called
- **Backwards-compatible**: the cost model derives the same threshold (3)
  that the hardcoded logic uses, so no behavioral change for `-O2`
- **Extensible**: future passes (O12 global copy opt, O13 load-immediate
  combining) can query `V6ClangInstrCost` instead of inventing new heuristics
- **`-Os`/`-Oz` ready**: the cost composition changes automatically when
  function attributes request size optimization

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Create cost header | `V6ClangInstrCost` struct + helpers | V6ClangInstrCost.h (new) |
| Wire DAD | INX chain for small constants feeding DAD | V6ClangInstrInfo.cpp |
| Wire ADD16 | Replace hardcoded `±1..±3` with cost comparison | V6ClangInstrInfo.cpp |
| Wire SUB16 | Same cost comparison for subtraction path | V6ClangInstrInfo.cpp |
| Lit test | Verify INX/DCX thresholds under `-O2` and `-Oz` | tests/lit/CodeGen/V6Clang/ |

---

## 3. Implementation Steps

### Step 3.1 — Create `V6ClangInstrCost.h` [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrCost.h` (new)

Header-only struct:

```cpp
struct V6ClangInstrCost {
  int32_t Bytes = 0;
  int32_t Cycles = 0;

  constexpr V6ClangInstrCost() = default;
  constexpr V6ClangInstrCost(int32_t B, int32_t C) : Bytes(B), Cycles(C) {}

  int64_t value(V6ClangOptMode Mode) const;
  bool isCheaperThan(const V6ClangInstrCost &RHS, V6ClangOptMode Mode) const;

  V6ClangInstrCost operator+(const V6ClangInstrCost &RHS) const;
  V6ClangInstrCost operator*(int N) const;
};
```

`V6ClangOptMode` enum with `Speed`, `Size`, `Balanced`.

`getV6ClangOptMode(const MachineFunction&)` helper:
- `Function::hasMinSize() || hasOptSize()` → `Size`
- `getOptLevel() >= Default` → `Speed`
- Otherwise → `Balanced`

`V6ClangCost` namespace with constants derived from V6ClangSchedule.td timing table:

```cpp
namespace V6ClangCost {
  constexpr V6ClangInstrCost INX{1, 8};
  constexpr V6ClangInstrCost LXI{3, 12};
  constexpr V6ClangInstrCost DAD{1, 12};
  constexpr V6ClangInstrCost MOVrr{1, 4};
  constexpr V6ClangInstrCost MOVrM{1, 8};
  constexpr V6ClangInstrCost MOVMr{1, 8};
  constexpr V6ClangInstrCost MVI{2, 8};
  constexpr V6ClangInstrCost ALUreg{1, 4};    // ADD/SUB/ANA/ORA/XRA/CMP r
  constexpr V6ClangInstrCost ALUimm{2, 8};    // ADI/SUI/ANI/ORI/XRI/CPI
  constexpr V6ClangInstrCost PUSH{1, 16};
  constexpr V6ClangInstrCost POP{1, 12};
  constexpr V6ClangInstrCost Jcc{3, 12};
  constexpr V6ClangInstrCost CALL{3, 24};
  constexpr V6ClangInstrCost RET{1, 12};
}
```

> **Implementation Notes**: Created `V6ClangInstrCost.h` header-only with `V6ClangInstrCost` struct, `V6ClangOptMode` enum (Speed/Size/Balanced), `getV6ClangOptMode(MF)` helper, `isCheaperThan`/`isCheaperOrEqual` comparisons, `operator+`/`operator*`, and 21 pre-defined `V6ClangCost::` constants. Used `<<16` shift (not `<<32` as in llvm-mos) since V6CLANG instruction costs fit in 16 bits.

### Step 3.2 — Wire cost model into V6CLANG_DAD expansion [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

Currently `V6CLANG_DAD` always expands to `DAD rp`, even when `rp` was loaded
with a small constant via `LXI rp, N`. For example, `LXI DE, 1; DAD DE`
costs 24cc/4B when `INX HL` costs 8cc/1B.

Add an INX/DCX check before the DAD emission:

```cpp
case V6CLANG::V6CLANG_DAD: {
    Register DstReg = MI.getOperand(0).getReg();
    Register RpReg = MI.getOperand(2).getReg();
    assert(DstReg == V6CLANG::HL && "V6CLANG_DAD operands must be HL");

    // Try INX/DCX chains for small constants.
    if (isFlagsDefDead(MI)) {
      MachineInstr *LXI = findDefiningLXI(MBB, MI.getIterator(), RpReg, &RI);
      if (LXI) {
        int64_t ImmVal = LXI->getOperand(1).getImm();
        if (ImmVal > 0x7FFF) ImmVal -= 0x10000;
        if (ImmVal != 0) {
          unsigned AbsVal = static_cast<unsigned>(
              ImmVal > 0 ? ImmVal : -ImmVal);
          unsigned InxOpc = ImmVal > 0 ? V6CLANG::INX : V6CLANG::DCX;
          V6ClangOptMode Mode = getV6ClangOptMode(*MBB.getParent());
          V6ClangInstrCost InxCost = V6ClangCost::INX * AbsVal;
          V6ClangInstrCost DadCost = V6ClangCost::LXI + V6ClangCost::DAD;
          if (InxCost.isCheaperThan(DadCost, Mode)) {
            for (unsigned I = 0; I < AbsVal; ++I)
              BuildMI(MBB, MI, DL, get(InxOpc), V6CLANG::HL).addReg(V6CLANG::HL);
            Register ConstReg = LXI->getOperand(0).getReg();
            if (isRegDeadAfter(MBB, MI.getIterator(), ConstReg, &RI))
              LXI->eraseFromParent();
            MI.eraseFromParent();
            return true;
          }
        }
      }
    }

    // Default: emit DAD.
    BuildMI(MBB, MI, DL, get(V6CLANG::DAD)).addReg(RpReg);
    MI.eraseFromParent();
    return true;
  }
```

**Savings per instance**:
- `ptr + 1`: 16cc saved, 3 bytes saved (LXI+DAD 24cc/4B → INX 8cc/1B)
- `ptr + 2`: 8cc saved, 2 bytes saved (24cc/4B → 2×INX 16cc/2B)
- `ptr + 3`: 0cc saved, 1 byte saved (24cc/4B → 3×INX 24cc/3B)

> **Design Note**: `isFlagsDefDead(MI)` is essential — DAD sets CY, but
> INX sets no flags. If the carry flag is live after DAD, the substitution
> is invalid. All pointer arithmetic cases have FLAGS dead afterward.

> **Implementation Notes**: Added INX/DCX chain before DAD emission in V6CLANG_DAD case. Uses `findDefiningLXI` to find the constant, `isFlagsDefDead` guard (INX sets no flags, DAD sets CY), and `isCheaperOrEqual` cost comparison. Erases dead LXI when constant reg is not used afterward.

### Step 3.3 — Wire cost model into V6CLANG_ADD16 expansion [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

Replace the hardcoded `ImmVal >= 1 && ImmVal <= 3` / `-3 .. -1` check
in the `V6CLANG_ADD16` case with a cost comparison:

```cpp
if (ImmVal != 0) {
  unsigned AbsVal = static_cast<unsigned>(ImmVal > 0 ? ImmVal : -ImmVal);
  unsigned InxOpc = ImmVal > 0 ? V6CLANG::INX : V6CLANG::DCX;
  V6ClangOptMode Mode = getV6ClangOptMode(*MBB.getParent());
  V6ClangInstrCost InxCost = V6ClangCost::INX * AbsVal;
  V6ClangInstrCost DadCost = V6ClangCost::LXI + V6ClangCost::DAD;
  if (InxCost.isCheaperThan(DadCost, Mode)) {
    Opc = InxOpc;
    Count = AbsVal;
  }
}
```

This naturally derives the threshold: for `AbsVal = 3`, INX wins;
for `AbsVal = 4`, DAD wins. Same result as the hardcoded `±3` but
derived from instruction costs.

> **Implementation Notes**: Replaced hardcoded `ImmVal >= 1 && ImmVal <= 3` with `V6ClangCost::INX * AbsVal` vs `V6ClangCost::LXI + V6ClangCost::DAD` comparison. The cost model naturally derives the same threshold (3) but is extensible and mode-aware.

### Step 3.4 — Wire cost model into V6CLANG_SUB16 expansion [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

Same change for the subtraction path (DCX/INX chain for constants).

> **Implementation Notes**: Same cost model pattern as ADD16. Note `InxOpc` is swapped: positive constant → DCX (sub), negative → INX.

### Step 3.5 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Clean build on first attempt. Only V6ClangInstrInfo.cpp recompiled + relink.

### Step 3.6 — Lit test: cost-model-inx-threshold.ll [x]

**File**: `tests/lit/CodeGen/V6Clang/cost-model-inx-threshold.ll`

Test that:
1. `ptr + 2` → 2×INX (wins under all modes)
2. `ptr + 3` → 3×INX (wins under all modes: tied cycles, fewer bytes)
3. `ptr + 4` → LXI+DAD (cheaper in all modes: faster, same bytes)

Verify under `-O2` (default) and `-Oz` (minsize attribute).

> **Implementation Notes**: 8 test cases: load_offset1..4, load_minus1, load_minus3, load_offset3_os (optsize), load_offset4_os. All pass. Tests the V6CLANG_DAD path (pointer GEP → DAD → INX chain).

### Step 3.7 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: 79/79 lit tests pass (including new cost-model-inx-threshold.ll), 15/15 golden tests pass. Zero regressions.

### Step 3.8 — Verification assembly steps from `tests\features\README.md` [x]

Compile the feature test case, verify cost-aware decisions produce
correct and efficient assembly.

> **Implementation Notes**: Verified improvement: read_offset1 saves 16cc+4B, read_offset2 saves 8cc+3B, read_offset3 saves 2B (tied cc), read_offset4 unchanged (correct: DAD wins). Feature test folder complete with c8080.asm, v6clang.asm, v6clang_old.asm, v6clang_new01.asm.

### Step 3.9 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: *empty — filled after completion*

---

## 4. Expected Results

### V6CLANG_DAD → INX optimization (immediate benefit)

Pointer offsets `+1`..`+3` currently emit `LXI rp, N; DAD rp` (24cc, 4B).
With the cost model, small constants are replaced by INX chains:

| Expression | Before | After | Cycle savings | Byte savings |
|-----------|--------|-------|---------------|-------------|
| `ptr + 1` | LXI+DAD (24cc, 4B) | INX (8cc, 1B) | 16cc | 3B |
| `ptr + 2` | LXI+DAD (24cc, 4B) | 2×INX (16cc, 2B) | 8cc | 2B |
| `ptr + 3` | LXI+DAD (24cc, 4B) | 3×INX (24cc, 3B) | 0cc | 1B |
| `ptr + 4` | LXI+DAD (24cc, 4B) | LXI+DAD (24cc, 4B) | 0cc | 0B |

### Cost-aware INX/DCX threshold

The hardcoded `±1..±3` range is replaced by a cost comparison
that naturally derives the same threshold. The code becomes self-documenting:

```
3×INX costs {3B, 24cc}, LXI+DAD costs {4B, 24cc}
  → INX wins (cheaper or tied under all modes)

4×INX costs {4B, 32cc}, LXI+DAD costs {4B, 24cc}
  → DAD wins (8cc cheaper, same bytes)
```

### Foundation for future passes

O12 (Global Copy Optimization) and O13 (Load-Immediate Combining) can
query `V6ClangInstrCost` to decide whether a transformation is profitable.
No new pass needs to reinvent cost heuristics.

### `-Os`/`-Oz` support ready

When a function has `optsize` or `minsize` attributes, the cost model
automatically favors byte savings over cycle savings. Currently this
doesn't change the INX threshold (since INX wins on both axes for ≤3),
but future passes will see different decisions.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Cost model disagrees with hardcoded threshold | Verified mathematically: same threshold (3) derived from cost comparison |
| Header-only bloat | Struct is 8 bytes, all methods are `constexpr` or 1-line |
| Future passes ignore cost model | Document in docs/V6ClangOptimization.md as canonical cost query |
| Wrong optimization mode detection | Test with explicit `-Oz` attribute in lit test |

---

## 6. Relationship to Other Improvements

- **O12 (Global Copy Optimization)**: will use `V6ClangInstrCost` for copy cost
  decisions instead of ad-hoc register-pair-specific heuristics
- **O13 (Load-Immediate Combining)**: will compare MVI cost vs MOV/INR/DCR
  cost using the model
- **O15 (Conditional Call)**: branch-over-call cost comparison
- **All future peephole patterns**: can use `isCheaperThan()` for profitability

---

## 7. Future Enhancements

- Add `copyCost(MCRegister Src, MCRegister Dst)` method for register-pair
  specific copy cost estimation
- Add `getInstrCost(const MachineInstr &MI)` to compute cost from any MI
  instead of requiring manual constant selection
- Integrate with the LLVM scheduling model (map SchedWrite → V6ClangInstrCost)

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [V6CLANG Instruction Timings](docs\V6ClangInstructionTimings.md)
* [Future Improvements](design\future_plans\README.md)
* [llvm-mos Analysis §S8](design\future_plans\llvm_mos_analysis.md)
* [O11 Feature Description](design\future_plans\O11_dual_cost_model.md)
