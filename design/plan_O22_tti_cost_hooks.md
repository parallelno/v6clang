# Plan: O22 — TTI Cost Hooks Expansion

*Source: [design/future_plans/O22_tti_cost_hooks.md](future_plans/O22_tti_cost_hooks.md)*

## 1. Problem

### Current behavior

The V6CLANG `TargetTransformInfo` (TTI) implementation
([V6ClangTargetTransformInfo.cpp](../llvm/lib/Target/V6CLANG/V6ClangTargetTransformInfo.cpp))
only customizes a small set of hooks needed by O7 (Loop Strength
Reduction):

* `getNumberOfRegisters`, `getRegisterBitWidth`
* `isLegalAddressingMode`, `getAddressComputationCost`
* `isNumRegsMajorCostOfLSR`, `isLSRCostLess`

Every other IR-level pass that queries TTI — most importantly the
**LoopUnroll** pass (and to a lesser extent the inliner, SLP vectorizer,
and IR-level CSE/LICM trade-offs) — receives the `BasicTTI` defaults.

`BasicTTI` was tuned for modern RISC-style cost ratios:

* Arithmetic on legal types costs **1** regardless of width.
* Memory ops on legal types cost **1** regardless of width.
* Compare/select on legal types cost **1** regardless of width.
* `getScalingFactorCost` returns 0 for any addressing mode that
  `isLegalAddressingMode` accepts.

On the i8080 these defaults are dramatically wrong:

| Operation | i8080 reality | BasicTTI default |
|-----------|---------------|------------------|
| 8-bit ALU op (`ADD r`, `XRA r`) | ~4cc, 1 instr | 1 |
| 16-bit ALU op (`ADD16` lowering) | ~24-48cc, 5–10 instrs | 1 |
| 8-bit load via `[HL]` | LXI+MOV ~20cc, 2 instrs | 1 |
| 16-bit load via `[HL]+INX+[HL]` | ~30cc, 4 instrs | 1 |
| 8-bit `CMP r` | 4cc, 1 instr | 1 |
| 16-bit cmp (BR_CC16 expansion) | ~40cc, 5+ instrs | 1 |
| Indexed addressing (`base+i*N`) | not supported | invalid |

The test built today
([temp/o22_unroll.asm](../temp/o22_unroll.asm) — generated from
[temp/o22_unroll.c](../temp/o22_unroll.c)) shows the consequences: a tiny
i16 accumulate loop already drips O61 immediate-spills (`SHLD .Lxx+1`)
in every iteration. Any IR-level pass that thinks an i16 op costs the
same as an i8 op risks unrolling or inlining bodies that the register
file cannot hold.

### Desired behavior

LLVM IR-level passes see V6CLANG-specific costs that reflect:

* i16 arithmetic ≈ 6× i8 arithmetic.
* i32 arithmetic ≈ 20× i8 (libcall via `__mulsi3`/etc.).
* i16 load/store ≈ 4 (`LXI` + `MOV r,M` + `INX` + `MOV r,M`).
* i16 cmp ≈ 4 (multi-instruction BR_CC16 lowering).
* Addressing modes with non-unit `Scale` are invalid.

This is enough information for `LoopUnroll` to back off from doubling
small i16 loop bodies, and for the inliner to avoid pulling in callees
that would blow the 3-pair register file.

The new costs must be **opt-out gated** — see Risks. A hidden cl::opt
`-v6clang-tti-cost-hooks` (default on) toggles all four hooks. Per-hook
flags allow narrowing regressions to the offending hook.

### Root cause

V6CLANG's TTI was built incrementally for LSR (O7). The other hooks were
never added because LSR didn't need them. As more passes (loop
unroller, inliner) start to matter for V6CLANG performance, the cost-model
gap becomes visible.

---

## 2. Strategy

### Approach: add four targeted overrides in `V6ClangTTIImpl`

Override exactly the four hooks identified in the design doc. Each
override:

1. Consults a top-level `cl::opt` flag (per-hook; all default to on).
   When the flag is off, fall through to `BaseT::...` (the BasicTTI
   default).
2. Inspects the type. For unsupported / unmodeled types, fall through
   to `BaseT::...` so we never produce *worse* numbers than BasicTTI
   for cases we don't understand.
3. Returns a small integer cost that reflects the i8080 expansion size.

The hooks are **cost hints only** — they cannot change correctness.
They can, however, perturb every downstream codegen decision (unroller,
inliner, SLP, …), so the opt-out flag is mandatory.

### Why this works

* **Non-vector target.** No vector-related code paths fire on V6CLANG, so
  we only need to handle scalar integer types.
* **Type-legalization-aware.** We use `getTypeLegalizationCost(Ty)` to
  detect types that legalize via splitting (`i32` → 2× `i16`) and
  multiply costs accordingly. This avoids hard-coding every odd type.
* **No new pass, no new IR mutation.** The cost numbers ride entirely
  through existing LLVM machinery.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| 3.1 | Declare four hooks + cl::opts | `V6ClangTargetTransformInfo.h` |
| 3.2 | Define `getArithmeticInstrCost` | `V6ClangTargetTransformInfo.cpp` |
| 3.3 | Define `getMemoryOpCost` | `V6ClangTargetTransformInfo.cpp` |
| 3.4 | Define `getCmpSelInstrCost` | `V6ClangTargetTransformInfo.cpp` |
| 3.5 | Define `getScalingFactorCost` | `V6ClangTargetTransformInfo.cpp` |
| 3.6 | Build & sync mirror | — |
| 3.7 | Lit test (negative/positive, opt-out) | `llvm-project/llvm/test/CodeGen/V6CLANG/` |
| 3.8 | Run regression tests | `tests\run_all.py` |
| 3.9 | Verification assembly | `tests\features\51\` |
| 3.10 | result.txt + future_plans README | — |
| 3.11 | Sync mirror | — |

---

## 3. Implementation Steps

### Step 3.1 — Declare hooks and cl::opts in `V6ClangTargetTransformInfo.h` [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangTargetTransformInfo.h`

Add the four method declarations to `class V6ClangTTIImpl`, matching the
BasicTTI signatures verbatim:

```cpp
  // --- O22: V6CLANG-tuned cost hooks (gated by -v6clang-tti-cost-hooks) ---
  InstructionCost getArithmeticInstrCost(
      unsigned Opcode, Type *Ty, TTI::TargetCostKind CostKind,
      TTI::OperandValueInfo Opd1Info = {TTI::OK_AnyValue, TTI::OP_None},
      TTI::OperandValueInfo Opd2Info = {TTI::OK_AnyValue, TTI::OP_None},
      ArrayRef<const Value *> Args = {},
      const Instruction *CxtI = nullptr);

  InstructionCost getMemoryOpCost(
      unsigned Opcode, Type *Src, MaybeAlign Alignment,
      unsigned AddressSpace, TTI::TargetCostKind CostKind,
      TTI::OperandValueInfo OpInfo = {TTI::OK_AnyValue, TTI::OP_None},
      const Instruction *I = nullptr);

  InstructionCost getCmpSelInstrCost(
      unsigned Opcode, Type *ValTy, Type *CondTy,
      CmpInst::Predicate VecPred, TTI::TargetCostKind CostKind,
      const Instruction *I = nullptr);

  InstructionCost getScalingFactorCost(
      Type *Ty, GlobalValue *BaseGV, int64_t BaseOffset, bool HasBaseReg,
      int64_t Scale, unsigned AddrSpace);
```

Include `llvm/IR/InstrTypes.h` if `CmpInst` is not already visible.

> **Design Note**: signatures must match `BasicTTIImplBase` exactly so
> that CRTP dispatch in `BasicTTIImpl.h` picks up our overrides via
> `thisT()->...`. We do **not** mark them `override`/`virtual` — TTI is
> CRTP-based.
>
> **Implementation Notes**: Done. `CmpInst` is already visible via
> `llvm/Analysis/TargetTransformInfo.h` → `llvm/IR/InstrTypes.h`,
> no extra include needed.

### Step 3.2 — Define `getArithmeticInstrCost` [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangTargetTransformInfo.cpp`

Add a top-level cl::opt and the override:

```cpp
static cl::opt<bool> EnableArithCost(
    "v6clang-tti-cost-arith",
    cl::desc("Enable V6CLANG-specific TTI arithmetic cost (O22)."),
    cl::init(true), cl::Hidden);

InstructionCost V6ClangTTIImpl::getArithmeticInstrCost(
    unsigned Opcode, Type *Ty, TTI::TargetCostKind CostKind,
    TTI::OperandValueInfo Opd1Info, TTI::OperandValueInfo Opd2Info,
    ArrayRef<const Value *> Args, const Instruction *CxtI) {
  if (!EnableArithCost || !EnableTTICostHooks)
    return BaseT::getArithmeticInstrCost(Opcode, Ty, CostKind,
                                         Opd1Info, Opd2Info, Args, CxtI);

  // Scalar integer only — vectors do not exist on V6CLANG.
  if (Ty->isVectorTy() || !Ty->isIntegerTy())
    return BaseT::getArithmeticInstrCost(Opcode, Ty, CostKind,
                                         Opd1Info, Opd2Info, Args, CxtI);

  unsigned BW = Ty->getIntegerBitWidth();
  // 8-bit native ALU op.
  if (BW <= 8)  return 1;
  // 16-bit ALU expands to multi-instruction sequences (DAD, ADC, …).
  if (BW <= 16) return 6;
  // 32-bit goes through a libcall.
  if (BW <= 32) return 20;
  return BaseT::getArithmeticInstrCost(Opcode, Ty, CostKind,
                                       Opd1Info, Opd2Info, Args, CxtI);
}
```

> **Design Note**: numbers are abstract relative weights, not cycles.
> They preserve the ratio i16 ≈ 6× i8, i32 ≈ 20× i8 documented in the
> O22 design doc. `EnableTTICostHooks` is the master flag declared in
> Step 3.1's cpp section (see Step 3.5 — single declaration shared).
>
> **Implementation Notes**: Done.

### Step 3.3 — Define `getMemoryOpCost` [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangTargetTransformInfo.cpp`

```cpp
static cl::opt<bool> EnableMemCost(
    "v6clang-tti-cost-mem",
    cl::desc("Enable V6CLANG-specific TTI memory cost (O22)."),
    cl::init(true), cl::Hidden);

InstructionCost V6ClangTTIImpl::getMemoryOpCost(
    unsigned Opcode, Type *Src, MaybeAlign Alignment, unsigned AddressSpace,
    TTI::TargetCostKind CostKind, TTI::OperandValueInfo OpInfo,
    const Instruction *I) {
  if (!EnableMemCost || !EnableTTICostHooks)
    return BaseT::getMemoryOpCost(Opcode, Src, Alignment, AddressSpace,
                                  CostKind, OpInfo, I);

  if (Src->isVectorTy() || !Src->isIntegerTy())
    return BaseT::getMemoryOpCost(Opcode, Src, Alignment, AddressSpace,
                                  CostKind, OpInfo, I);

  unsigned BW = Src->getIntegerBitWidth();
  // Every memory access requires HL setup (LXI HL, addr) on V6CLANG.
  if (BW <= 8)  return 2;   // LXI + MOV M / MOV r,M
  if (BW <= 16) return 4;   // LXI + MOV + INX + MOV
  if (BW <= 32) return 8;   // 2× i16 access pattern
  return BaseT::getMemoryOpCost(Opcode, Src, Alignment, AddressSpace,
                                CostKind, OpInfo, I);
}
```

> **Design Note**: There are no free indexed addressing modes on i8080,
> so the access cost is dominated by the HL setup. The 2/4/8 ratio
> matches the actual instruction count seen in
> [temp/o22_unroll.asm](../temp/o22_unroll.asm).
>
> **Implementation Notes**: Done.

### Step 3.4 — Define `getCmpSelInstrCost` [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangTargetTransformInfo.cpp`

```cpp
static cl::opt<bool> EnableCmpCost(
    "v6clang-tti-cost-cmp",
    cl::desc("Enable V6CLANG-specific TTI cmp/select cost (O22)."),
    cl::init(true), cl::Hidden);

InstructionCost V6ClangTTIImpl::getCmpSelInstrCost(
    unsigned Opcode, Type *ValTy, Type *CondTy, CmpInst::Predicate VecPred,
    TTI::TargetCostKind CostKind, const Instruction *I) {
  if (!EnableCmpCost || !EnableTTICostHooks)
    return BaseT::getCmpSelInstrCost(Opcode, ValTy, CondTy, VecPred,
                                     CostKind, I);

  if (!ValTy || ValTy->isVectorTy() || !ValTy->isIntegerTy())
    return BaseT::getCmpSelInstrCost(Opcode, ValTy, CondTy, VecPred,
                                     CostKind, I);

  unsigned BW = ValTy->getIntegerBitWidth();
  // i1 / i8: single CMP r (4cc).
  if (BW <= 8)  return 1;
  // i16: BR_CC16 expansion is multi-instruction (CMP/CMP/Jcc/...).
  if (BW <= 16) return 4;
  if (BW <= 32) return 10;
  return BaseT::getCmpSelInstrCost(Opcode, ValTy, CondTy, VecPred,
                                   CostKind, I);
}
```

> **Implementation Notes**: Done.

### Step 3.5 — Define `getScalingFactorCost` and master flag [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangTargetTransformInfo.cpp`

Place the **master** opt-out flag near the top of the file (next to the
existing `LSRStrategyOpt`):

```cpp
static cl::opt<bool> EnableTTICostHooks(
    "v6clang-tti-cost-hooks",
    cl::desc("Master switch for V6CLANG-specific TTI cost hooks (O22). "
             "Disable to fall back to BasicTTI defaults."),
    cl::init(true), cl::Hidden);
```

Then add the scaling-factor override:

```cpp
static cl::opt<bool> EnableScalingCost(
    "v6clang-tti-cost-scaling",
    cl::desc("Enable V6CLANG-specific TTI scaling-factor cost (O22)."),
    cl::init(true), cl::Hidden);

InstructionCost V6ClangTTIImpl::getScalingFactorCost(
    Type *Ty, GlobalValue *BaseGV, int64_t BaseOffset, bool HasBaseReg,
    int64_t Scale, unsigned AddrSpace) {
  if (!EnableScalingCost || !EnableTTICostHooks)
    return BaseT::getScalingFactorCost(Ty, BaseGV, BaseOffset, HasBaseReg,
                                       Scale, AddrSpace);

  // V6CLANG only supports a single base register (HL) with no offset and no
  // scaled index. Anything else is invalid.
  if (BaseGV || BaseOffset != 0 || (Scale != 0 && Scale != 1))
    return InstructionCost::getInvalid();
  if (!HasBaseReg && Scale == 0)
    return InstructionCost::getInvalid();
  return 0;
}
```

> **Design Note**: this mirrors `isLegalAddressingMode` exactly. We
> return `getInvalid()` (not a large positive cost) to communicate that
> the addressing mode is *illegal*, not merely expensive — clients that
> support invalid costs (LSR) treat this as "do not generate".
>
> **Implementation Notes**: Done. Master + 4 per-hook flags landed in
> `V6ClangTargetTransformInfo.cpp` near the top of the file.

### Step 3.6 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

Then sync the mirror:

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

Iterate on Steps 3.1–3.5 if the build fails.

> **Implementation Notes**: Clean build first try (V6ClangTargetTransformInfo.cpp + V6ClangTargetMachine.cpp + LLVMV6ClangCodeGen.lib + clang.exe + llc.exe). Also rebuilt `opt` for the lit test.

### Step 3.7 — Lit test: cost hooks observable via `print<cost-model>` [x]

**File**: `llvm-project/llvm/test/CodeGen/V6CLANG/tti-cost-hooks.ll`

A minimal lit test that compiles a small loop with `-debug-only=...`
or via the `print<cost-model>` analysis pass, asserting:

* i8 add cost == 1
* i16 add cost == 6
* i16 load cost == 4
* i16 icmp cost == 4
* `-v6clang-tti-cost-hooks=0` switches all of the above back to BasicTTI
  defaults (RUN line with FileCheck `--check-prefix=OFF`).

Run:

```
llvm-build\bin\llvm-lit -v llvm-project\llvm\test\CodeGen\V6CLANG\tti-cost-hooks.ll
```

After authoring, sync the mirror and confirm `tests/lit/llvm/.../V6CLANG/`
has the new file.

> **Design Note**: we use `opt -passes='print<cost-model>'` rather than
> backend-side debug output because `print<cost-model>` is the canonical
> way to observe TTI numbers (see existing `llvm/test/Analysis/CostModel/`
> tests for prior art).
>
> **Implementation Notes**: Done.
> [tti-cost-hooks.ll](../llvm-project/llvm/test/CodeGen/V6CLANG/tti-cost-hooks.ll)
> verifies all four hooks ON (default) and OFF (`-v6clang-tti-cost-hooks=0`).
> PASS on first run.

### Step 3.8 — Run regression tests [x]

```
python tests\run_all.py
```

Investigate any regression. Per the design doc, *any* test that
regresses by more than ~2 bytes per function should be analyzed: in
each case the choice is (a) tweak the cost numbers, (b) restrict the
hook to the type sizes where it actually helps, or (c) leave the new
behavior because the test asserted code that was incidentally lucky.

> **Implementation Notes**: 126/126 tests pass (was 125 before adding
> the new lit test). Zero regressions across golden + lit suites.

### Step 3.9 — Verification assembly steps from `tests\features\README.md` [x]

Folder: `tests\features\51\`. Files prepared in Phase 1 (preparation):
`c8080.c`, `v6clang.c`, `c8080.asm`, `v6clang_old.asm`.

Workflow:

1. Compile `v6clang.c` → `v6clang_new01.asm` with the new hooks on.
2. Compile `v6clang.c` → `v6clang_new01_off.asm` with
   `-mllvm -v6clang-tti-cost-hooks=0` (BasicTTI baseline).
3. Diff against `v6clang_old.asm`. Expected outcomes:
   * Loops with i16 work no longer over-unrolled.
   * In particular, no extra `__mulhi3` calls or O61 immediate-spill
     pseudos appearing per duplicated body.
4. If the assembly does not show the expected improvement, iterate
   (`v6clang_new02.asm`, `v6clang_new03.asm`, …) and tune the cost
   numbers in Steps 3.2–3.5.

> **Implementation Notes**: Done with `v6clang_new01.asm` on first try.
> File shrank from 147 → 128 lines (−13%). Two visible IR-level effects:
> (a) loop counter narrowed i16 → i8 (DCR A vs DCX B/MOV/ORA), and
> (b) per-iter spill set dropped from 4×SHLD + PUSH/POP to 2×SHLD + 1×STA.

### Step 3.10 — Make sure result.txt is created [x]

Per `tests\features\README.md`: include the C source, the c8080 main
body in i8080 mnemonics, c8080 stats (cycles + bytes per function),
the v6clang asm, and v6clang stats.

> **Implementation Notes**: [tests/features/51/result.txt](../tests/features/51/result.txt) created.

### Step 3.11 — Update README and sync mirror [x]

* Mark O22 as `[x]` in `design/future_plans/README.md`.
* Update the design doc itself with a backlink to this plan.
* Sync the mirror one final time:
  ```
  powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
  ```

> **Implementation Notes**: README marked `[x]`, mirror synced.

---

## 4. Expected Results

### Example 1 — small i16 accumulate loop

`temp/o22_unroll.c::sum_array` currently compiles into a body with
4 `SHLD .Lxx+1` immediate-spills per iteration plus `__mulhi3`. With
the i16 arithmetic cost bumped to 6, the IR-level loop unroller will
not duplicate the body — saving register pressure and avoiding extra
spills if it had decided to unroll under default costs.

### Example 2 — pointer-walk loop with constant stride

LSR currently uses `getAddressComputationCost = 2` (already biased
toward strength-reduced pointers). Adding the proper
`getScalingFactorCost` ensures any non-unit stride is *invalid*, not
just "cost 2", so LSR will never emit a `base + i*N` form for V6CLANG —
it will always strength-reduce to a `p++` IV.

### Example 3 — bisecting a regression

If a future workload regresses, the developer can isolate the cause:

```
clang -mllvm -v6clang-tti-cost-hooks=0 ...      # Off entirely
clang -mllvm -v6clang-tti-cost-arith=0 ...      # Just arithmetic off
clang -mllvm -v6clang-tti-cost-mem=0 ...        # Just memory off
clang -mllvm -v6clang-tti-cost-cmp=0 ...
clang -mllvm -v6clang-tti-cost-scaling=0 ...
```

Each bisection step requires no rebuild — invaluable for triaging
corpus-wide regressions.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| **Corpus-wide regression**: TTI costs perturb every IR-level pass. A bad cost choice can shift the regression suite by hundreds of bytes. | Master `-v6clang-tti-cost-hooks` and per-hook `-v6clang-tti-cost-{arith,mem,cmp,scaling}` flags allow on/off bisection without a rebuild. |
| **Inliner over-suppression**: making i16 ops "expensive" might block beneficial inlining. | Inliner thresholds work in the same units, so a uniform 6× scaling on i16 is consistent. If problems show, narrow the override (e.g. only for `mul`/`udiv`). |
| **Vector code paths**: BasicTTI calls into our hooks for vector lowering of intrinsics. | All hooks fall through to `BaseT::...` for vector types — V6CLANG has no vector legalization anyway. |
| **CRTP signature drift**: BasicTTI signatures change across LLVM versions. | We pin to `llvmorg-18.1.0`. Signatures captured in Step 3.1 are copied verbatim from `llvm-project/llvm/include/llvm/CodeGen/BasicTTIImpl.h` lines 884, 1213, 1318, 398. |
| **`getInstructionCost` callers don't actually call `getMemoryOpCost`**: some IR passes use `getInstructionCost` which dispatches differently. | The override is reached for `LoadInst`/`StoreInst` cost queries (verified by `BasicTTI::getInstructionCost`'s switch). Lit test in Step 3.7 makes this observable. |

---

## 6. Relationship to Other Improvements

* **Builds on O7** — O7 added `isLegalAddressingMode`,
  `getAddressComputationCost`, and the LSR cost predicates. O22 fills
  the remaining gaps so non-LSR passes also see V6CLANG-specific numbers.
* **Synergy with O11** (Dual Cost Model) — once O11 lands, the integer
  constants here can be derived from the same Bytes/Cycles tables that
  drive the MachineInstr cost model. Until then, the constants are
  hand-tuned and gated.
* **Synergy with O39** (IPRA integration) — IPRA + accurate inlining
  costs together prevent the "inline + spill all callee-saves"
  pathology.

---

## 7. Future Enhancements

* Differentiate cost by opcode (e.g., i16 `mul` is much more expensive
  than i16 `add`). Currently we return the same 6 for both.
* Add `getCastInstrCost` (sext/zext from i8 → i16 is essentially free
  on V6CLANG — `MVI H, 0`).
* Add `getInterleavedMemoryOpCost` to discourage SLP from interleaving
  (V6CLANG has no scatter/gather).
* Once O11 lands, reuse its byte/cycle tables instead of magic numbers.
* **A-pressure-aware IV-narrowing veto (post-LSR / pre-RA).** The
  arithmetic hook gives a +45% win on `bsort` but a −6.7% loss on
  `sieve::count_set` (see [docs/V6ClangOptimization.md](../docs/V6ClangOptimization.md)).
  Bisection confirmed both come from `getArithmeticInstrCost` alone —
  there is no sub-flag toggle that recovers sieve without losing bsort,
  because they are two faces of the same IV-narrowing decision. A
  structural fix is a small MachineFunction pass that runs after LSR
  and before register allocation. It would detect the regression
  pattern:
    1. an i8 IV decremented via `DCR A` in the loop latch, AND
    2. another A-using instruction in the same loop body (`MOV A,M`,
       `ORA`, `ADD r`, `OUT`, `CMP r`, …),
  and rewrite the i8 down-counter as a pointer-end compare on an
  existing in-loop pointer (`CMP L; JNZ; CMP H; JNZ`). When no in-loop
  pointer exists, fall back to leaving the IV alone.

  **Status: not recommended yet.** Cross-layer heuristics like this are
  fragile — every change in ISel, peephole, or regalloc can invalidate
  the trigger. The opt-out flag (`-mllvm -v6clang-tti-cost-arith=0`) is
  sufficient as an escape hatch for the single known regression.
  Revisit if a second independent benchmark hits the same pattern, or
  if the corpus shows ≥3 regressions traceable to A-pressure on i8 IVs.

---

## 8. References

* [O22 design](future_plans/O22_tti_cost_hooks.md)
* [O7 plan](plan_loop_strength_reduction.md)
* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md)
* [Future Improvements](future_plans/README.md)
* [Feature Pipeline](pipeline_feature.md)
* [Plan Format Reference](plan_cmp_based_comparison.md)
