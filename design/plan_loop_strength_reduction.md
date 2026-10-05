# Plan: Loop Strength Reduction for V6CLANG Target

**Reference**: [design_improve_spilling.md](design_improve_spilling.md), [design.md](design.md) §8

---

## 1. Problem

The V6CLANG backend generates `base + i` address recomputation on every loop
iteration instead of maintaining and incrementing a pointer. For a simple
array copy:

```c
for (uint8_t i = 0; i < 100; i++) {
    array2[i] = array1[i];
}
```

The current codegen per iteration does:

```asm
LXI  HL, array1     ; 12 cc  — reload base every iteration
; ... extend i to 16-bit ...
DAD  HL              ; 12 cc  — add index
MOV  A, M            ;  8 cc  — load
; ... spill, reload, recompute for array2 ...
```

Each `base + i` costs at minimum 24 cc (LXI + DAD). With two arrays, the
loop body pays ~48 cc just for address computation — plus spills to manage
the intermediate values, adding another ~100+ cc of overhead.

The ideal output maintains running pointers:

```asm
; preheader: LXI HL, array1 ; LXI DE, array2
.loop:
  MOV  A, M          ;  8 cc  — load via HL
  XCHG                ;  4 cc
  MOV  M, A          ;  8 cc  — store via HL (was DE)
  XCHG                ;  4 cc
  INX  HL            ;  8 cc  — advance ptr1
  INX  DE            ;  8 cc  — advance ptr2
  ; ... compare & branch ...
```

Savings: ~120+ cc per iteration (~3× faster loop body).

### Root Cause

LLVM has a built-in Loop Strength Reduction pass (`-loop-reduce`), but it
makes cost decisions through `TargetTransformInfo` (TTI) hooks. V6CLANG has
**no TTI implementation** — it falls back to `TargetTransformInfoImplBase`
defaults, which assume reg+reg addressing is free (cost 0) and that the
target has 32-bit registers with plentiful register files. These defaults
mean LSR either doesn't run meaningful transformations, or makes wrong
choices for the 8080's extremely constrained register set.

---

## 2. Strategy

Implement a V6CLANG-specific TTI class that teaches LLVM's existing LSR pass
about the 8080's addressing model and register constraints. This avoids
writing a custom LSR pass — the built-in one is mature and correct; it
just needs accurate cost information.

Key TTI hooks to implement:

| Hook | Purpose | V6CLANG Value | Tunable? |
|------|---------|-----------|----------|
| `isLegalAddressingMode()` | Only reg indirect (no offset) | `true` only for `Scale==0, BaseOffset==0, HasBaseReg, !BaseGV` | No — architectural fact |
| `getAddressComputationCost()` | Cost of GEP in a loop | Non-zero (initial: 2) | Yes — see Step 3.9 |
| `getNumberOfRegisters()` | Available GPRs | 3 (register pairs) | No — architectural fact |
| `getRegisterBitWidth()` | Pointer width | 16 bits | No — architectural fact |
| `isNumRegsMajorCostOfLSR()` | Register pressure matters | `true` | No — always true for 8080 |
| `isLSRCostLess()` | Custom cost ranking | Prioritize fewer regs over fewer instructions | Yes — field ordering |

---

## 3. Implementation Steps

### Step 3.1 — Create V6ClangTargetTransformInfo.h [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangTargetTransformInfo.h`

```cpp
#ifndef LLVM_LIB_TARGET_V6CLANG_V6ClangTARGETTRANSFORMINFO_H
#define LLVM_LIB_TARGET_V6CLANG_V6ClangTARGETTRANSFORMINFO_H

#include "V6ClangTargetMachine.h"
#include "llvm/Analysis/TargetTransformInfo.h"
#include "llvm/CodeGen/BasicTTIImpl.h"

namespace llvm {

class V6ClangTTIImpl : public BasicTTIImplBase<V6ClangTTIImpl> {
  using BaseT = BasicTTIImplBase<V6ClangTTIImpl>;
  using TTI = TargetTransformInfo;
  friend BaseT;

  const V6ClangSubtarget *ST;
  const V6ClangTargetLowering *TLI;

  const V6ClangSubtarget *getST() const { return ST; }
  const V6ClangTargetLowering *getTLI() const { return TLI; }

public:
  explicit V6ClangTTIImpl(const V6ClangTargetMachine *TM, const Function &F)
      : BaseT(TM, F.getParent()->getDataLayout()),
        ST(TM->getSubtargetImpl(F)),
        TLI(ST->getTargetLowering()) {}

  // --- Register model ---
  unsigned getNumberOfRegisters(unsigned ClassID) const;
  TypeSize getRegisterBitWidth(TTI::RegisterKind K) const;

  // --- Addressing & LSR ---
  bool isLegalAddressingMode(Type *Ty, GlobalValue *BaseGV,
                             int64_t BaseOffset, bool HasBaseReg,
                             int64_t Scale, unsigned AddrSpace,
                             Instruction *I = nullptr) const;

  InstructionCost getAddressComputationCost(Type *Ty, ScalarEvolution *SE,
                                            const SCEV *Ptr) const;

  bool isNumRegsMajorCostOfLSR() const { return true; }

  bool isLSRCostLess(const TTI::LSRCost &C1, const TTI::LSRCost &C2) const;
};

} // namespace llvm

#endif
```

### Step 3.2 — Create V6ClangTargetTransformInfo.cpp [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangTargetTransformInfo.cpp`

```cpp
#include "V6ClangTargetTransformInfo.h"
#include "llvm/Analysis/TargetTransformInfo.h"

using namespace llvm;

unsigned V6ClangTTIImpl::getNumberOfRegisters(unsigned ClassID) const {
  // ClassID 0 = scalar (general purpose register pairs: BC, DE, HL)
  // ClassID 1 = vector (none)
  return ClassID == 0 ? 3 : 0;
}

TypeSize V6ClangTTIImpl::getRegisterBitWidth(TTI::RegisterKind K) const {
  return TypeSize::getFixed(16);
}

bool V6ClangTTIImpl::isLegalAddressingMode(Type *Ty, GlobalValue *BaseGV,
                                        int64_t BaseOffset, bool HasBaseReg,
                                        int64_t Scale, unsigned AddrSpace,
                                        Instruction *I) const {
  // 8080 only supports [HL] indirect — no base+offset, no scaled index.
  // Legal: a single base register with zero offset, zero scale.
  if (BaseGV)
    return false;
  if (BaseOffset != 0)
    return false;
  if (Scale != 0 && Scale != 1)
    return false;
  // Must have at least a base register.
  if (!HasBaseReg && Scale == 0)
    return false;
  return true;
}

InstructionCost V6ClangTTIImpl::getAddressComputationCost(Type *Ty,
                                                       ScalarEvolution *SE,
                                                       const SCEV *Ptr) const {
  // Address computation on 8080 is expensive: LXI (12cc) + DAD (12cc) = 24cc
  // for base+index, vs INX (8cc) for pointer increment.
  // Returning non-zero makes LSR prefer strength-reduced pointer forms.
  return 2;
}

bool V6ClangTTIImpl::isLSRCostLess(const TTI::LSRCost &C1,
                                const TTI::LSRCost &C2) const {
  // On the 8080, register pressure is the dominant constraint.
  // Prefer fewer registers first, then fewer instructions.
  return std::tie(C1.NumRegs, C1.Insns, C1.AddRecCost, C1.NumIVMuls,
                  C1.NumBaseAdds, C1.ImmCost, C1.SetupCost, C1.ScaleCost) <
         std::tie(C2.NumRegs, C2.Insns, C2.AddRecCost, C2.NumIVMuls,
                  C2.NumBaseAdds, C2.ImmCost, C2.SetupCost, C2.ScaleCost);
}
```

#### Design Notes

- **`isLegalAddressingMode`**: The 8080 supports `[HL]`, `[BC]`, and `[DE]`
  for memory access (via MOV r,M / LDAX / STAX) — but none of them support
  base+offset or scaled index modes. By telling LSR that only bare register
  indirect is legal, it is forced to maintain separate induction variables
  as running pointers (the profitable form). LSR doesn't need to distinguish
  HL vs BC vs DE — that's the register allocator's job. The backend already
  optimizes LDAX/STAX selection in `V6ClangInstrInfo.cpp` (V6CLANG_LOAD8_P /
  V6CLANG_STORE8_P expansion): when RA assigns a pointer to BC or DE with value
  in A, the expansion emits LDAX/STAX (8cc) instead of copying to HL (24cc).

- **`getAddressComputationCost`**: Returning non-zero (initial value: 2)
  tells LSR that computing addresses is expensive and worth strength-
  reducing. The exact value is a tuning parameter — start with 2 and
  adjust based on LSR's debug output (see Step 3.9). The value doesn't
  map to clock cycles; it's an abstract relative weight.

- **`getNumberOfRegisters`**: Returning 3 (BC, DE, HL pairs) tells LSR the
  extreme register pressure, discouraging solutions that need many IVs.

- **`isLSRCostLess`**: Re-orders the default lexicographic comparison to
  put `NumRegs` first (same as default) but adds `Insns` second, giving
  instruction count more weight than in the base implementation.

### Step 3.3 — Register TTI in V6ClangTargetMachine [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangTargetMachine.h`

Add override declaration:

```cpp
  TargetTransformInfo getTargetTransformInfo(const Function &F) const override;
```

**File**: `llvm/lib/Target/V6CLANG/V6ClangTargetMachine.cpp`

Add include and implementation:

```cpp
#include "V6ClangTargetTransformInfo.h"

// ... after existing code, before LLVMInitializeV6ClangTarget ...

TargetTransformInfo
V6ClangTargetMachine::getTargetTransformInfo(const Function &F) const {
  return TargetTransformInfo(V6ClangTTIImpl(this, F));
}
```

### Step 3.4 — Add to CMakeLists.txt [x]

**File**: `llvm/lib/Target/V6CLANG/CMakeLists.txt`

Add `V6ClangTargetTransformInfo.cpp` to the source list in `V6ClangCodeGen`:

```cmake
add_llvm_target(V6ClangCodeGen
  V6ClangAccumulatorPlanning.cpp
  ...
  V6ClangTargetTransformInfo.cpp   # ← add
  ...
)
```

### Step 3.5 — Build [x]

```bash
ninja -C llvm-build clang llc
```

Fix any compilation errors. The TTI header uses CRTP
(`BasicTTIImplBase<V6ClangTTIImpl>`), so method signatures must match exactly.

### Step 3.6 — Verify IR: LSR transforms the loop [x]

Compile the array copy test and inspect the IR before/after LSR:

```bash
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S -emit-llvm ^
    temp\compare\03\v6clang2.c -o temp\compare\03\v6clang2_lsr.ll
```

Expected: the loop body should use `getelementptr ... %ptr` with
`%ptr = phi [%start, %preheader], [%next, %loop]` and
`%next = getelementptr %ptr, 1` — **not** `getelementptr %base, %i`.

Optional: use `-mllvm -debug-only=loop-reduce` to see LSR's decision log.

### Step 3.7 — Verify assembly: pointer increment pattern [x]

```bash
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S ^
    temp\compare\03\v6clang2.c -o temp\compare\03\v6clang2_lsr.asm
```

Expected in the loop body:
- `MOV A, M` / `MOV M, A` (HL-indirect load/store)
- `INX HL` / `INX DE` (pointer increment)
- `XCHG` (swap HL↔DE for second array access)
- No `LXI` + `DAD` inside the loop (address recomputation eliminated)
- No spill/reload inside the loop (3 pairs sufficient: HL=ptr1, DE=ptr2,
  BC=counter)

### Step 3.8 — Lit test for LSR behavior [x]

**File**: `tests/lit/CodeGen/V6CLANG/loop-strength-reduce.ll`

```llvm
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

@src = global [100 x i8] zeroinitializer
@dst = global [100 x i8] zeroinitializer

define void @array_copy() {
entry:
  br label %loop

loop:
  %i = phi i8 [ 0, %entry ], [ %next, %loop ]
  %idx = zext i8 %i to i16
  %p1 = getelementptr [100 x i8], ptr @src, i16 0, i16 %idx
  %val = load i8, ptr %p1
  %p2 = getelementptr [100 x i8], ptr @dst, i16 0, i16 %idx
  store i8 %val, ptr %p2
  %next = add i8 %i, 1
  %cmp = icmp ult i8 %next, 100
  br i1 %cmp, label %loop, label %exit

exit:
  ret void
}

; CHECK-LABEL: array_copy:
; Loop body should use pointer increments, not base+offset recomputation.
; CHECK: .L{{.*}}:
; CHECK-NOT: DAD
; CHECK: INX
```

### Step 3.9 — Tune cost parameters [x]

The initial cost values (`getAddressComputationCost` = 2, `isLSRCostLess`
ranking order) are educated guesses. They must be validated empirically.

**Diagnostic command**:
```bash
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S -emit-llvm ^
    -mllvm -debug-only=loop-reduce ^
    temp\compare\03\v6clang2.c -o temp\compare\03\v6clang2_lsr.ll 2>&1 ^
    | findstr /i "formula cost"
```

This shows the LSR candidates and their costs. Verify that:
- The chosen formula uses a single IV per array pointer (not `base + i`)
- `NumRegs` in the winning cost is ≤ 3
- No formula with fewer regs was rejected in favor of one with more

**What to tune if results are wrong**:

| Symptom | Adjustment |
|---------|------------|
| LSR still picks `base + i` | Increase `getAddressComputationCost` (try 4, 8) |
| LSR creates too many IVs (>3) | Verify `getNumberOfRegisters` is queried; adjust `isLSRCostLess` to penalize `NumRegs` even more |
| LSR eliminates the loop counter IV | Check if `isLSRCostLess` `Insns` weight is too low |
| No LSR activity at all | Verify pass runs: `-mllvm -debug-only=loop-reduce` should show output |

**Test cases for tuning** (compile each, inspect ASM):
- `temp/compare/03/v6clang2.c` — two-array copy (primary)
- Single-array traversal (memset-like)
- Nested loop with one array
- Loop with non-unit stride (`i += 2`)

Iterate until the array copy produces the INX-based pointer pattern.
Document final chosen values in a comment in `V6ClangTargetTransformInfo.cpp`.

### Step 3.10 — Regression tests [x]

```bash
python tests/run_all.py
```

All existing tests must pass. LSR should only affect loops with array/pointer
access patterns — straight-line code and non-loop functions are unaffected.

### Step 3.11 — Sync mirror [x]

```powershell
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

---

## 4. Expected Results

### Array copy loop (temp\compare\03\v6clang2.c)

Before (no TTI, base+i recomputation):
- ~55 instructions per iteration
- 3 spills + 3 reloads (~100+ cc spill overhead)
- ~48 cc address computation (two LXI+DAD)
- Total: ~300+ cc per iteration

After (TTI + LSR, pointer increment):
- ~10-15 instructions per iteration
- 0 spills (3 pairs sufficient: HL, DE, BC)
- 0 address recomputation in loop body
- ~40 cc per iteration (MOV+XCHG+MOV+XCHG+INX+INX+DCR+JNZ)
- **~7× faster loop body**

### General impact

- All loops with array indexing patterns benefit
- Straight-line code and non-loop functions are unaffected
- Register pressure modeling prevents LSR from creating too many IVs
- The TTI hooks also benefit other LLVM passes that query cost info
  (vectorizer, unroller, etc.), though these are less relevant for 8-bit

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| LSR creates too many IVs, exceeding 3 register pairs | `getNumberOfRegisters()` returns 3, `isNumRegsMajorCostOfLSR()` returns true — LSR accounts for register pressure |
| `isLegalAddressingMode` too restrictive, breaks other patterns | Only affects LSR/cost queries, not instruction selection; ISel already handles whatever IR it receives |
| LLVM's LSR doesn't run at all at -O2 | LSR is part of the standard -O2 pipeline; verify with `-mllvm -debug-only=loop-reduce` |
| Post-LSR IR still generates spills due to RA choices | A separate concern — address with spill optimization ([design_improve_spilling.md](design_improve_spilling.md)) if needed |

---

## 6. Relationship to LDAX/STAX Optimization

The 8080 has three indirect addressing paths:
- `[HL]` — MOV r,M / MOV M,r (any register, 8cc)
- `[BC]` — LDAX BC / STAX BC (A register only, 8cc)
- `[DE]` — LDAX DE / STAX DE (A register only, 8cc)

LSR operates at the IR level where there are no physical registers.
It transforms `base + i` into a running pointer — a purely structural
change. The choice of which register pair holds that pointer is made
later by the register allocator. The backend already has LDAX/STAX
selection logic in `V6ClangInstrInfo.cpp` that fires when RA happens to
assign the pointer to BC/DE with the value in A.

LSR + TTI makes LDAX/STAX **more likely** to fire, because:
1. With running pointers, the loop has 2-3 live pointer values
2. RA must place them across BC, DE, HL
3. At least one array pointer will land in BC or DE
4. The load/store expansion then emits LDAX/STAX for that pair

Further improvements to LDAX/STAX utilization (e.g. ensuring RA
prefers BC/DE for pointers when A is the loaded/stored value) are
orthogonal peephole/RA-hinting work, not part of this plan.

---

## 7. Future Enhancements

Once the TTI infrastructure exists, additional hooks can be added
incrementally:

- **`getArithmeticInstrCost()`** — inform the unroller that 16-bit ops
  cost significantly more than 8-bit ops on the 8080
- **`getMemoryOpCost()`** — model the HL-dependency for load/store
- **`getCmpSelInstrCost()`** — model the expensive multi-instruction
  compare sequences for i16
- **`getScalingFactorCost()`** — return -1 (illegal) for all scaled
  modes, reinforcing `isLegalAddressingMode`
