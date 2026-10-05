//===-- V6ClangTargetTransformInfo.cpp - V6CLANG specific TTI ---------------------===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#include "V6ClangTargetTransformInfo.h"
#include "llvm/Analysis/TargetTransformInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Intrinsics.h"
#include "llvm/Support/CommandLine.h"

using namespace llvm;

namespace {
/// Selects how V6CLANG orders LSR formula cost vectors.
enum class LSRStrategy { Auto, InsnsFirst, RegsFirst };
} // namespace

// O22: master / per-hook switches for the V6CLANG-specific TTI cost model.
// All default to ON. Use `-mllvm -v6clang-tti-cost-hooks=0` to fall back to
// BasicTTI defaults wholesale, or any of the per-hook flags to bisect a
// regression to a single hook without rebuilding.
static cl::opt<bool> EnableTTICostHooks(
    "v6clang-tti-cost-hooks",
    cl::desc("Master switch for V6CLANG-specific TTI cost hooks (O22). "
             "Disable to fall back to BasicTTI defaults."),
    cl::init(true), cl::Hidden);

static cl::opt<bool> EnableArithCost(
    "v6clang-tti-cost-arith",
    cl::desc("Enable V6CLANG-specific TTI arithmetic cost (O22)."),
    cl::init(true), cl::Hidden);

static cl::opt<bool> EnableMemCost(
    "v6clang-tti-cost-mem",
    cl::desc("Enable V6CLANG-specific TTI memory cost (O22)."),
    cl::init(true), cl::Hidden);

static cl::opt<bool> EnableCmpCost(
    "v6clang-tti-cost-cmp",
    cl::desc("Enable V6CLANG-specific TTI cmp/select cost (O22)."),
    cl::init(true), cl::Hidden);

static cl::opt<bool> EnableScalingCost(
    "v6clang-tti-cost-scaling",
    cl::desc("Enable V6CLANG-specific TTI scaling-factor cost (O22)."),
    cl::init(true), cl::Hidden);

static cl::opt<LSRStrategy> LSRStrategyOpt(
    "v6clang-lsr-strategy",
    cl::desc("LSR formula tie-breaker ordering on V6CLANG."),
    cl::init(LSRStrategy::Auto),
    cl::values(
        clEnumValN(LSRStrategy::Auto, "auto",
                   "derive from optimization mode (default)"),
        clEnumValN(LSRStrategy::InsnsFirst, "insns-first",
                   "Z80-style: instruction count first"),
        clEnumValN(LSRStrategy::RegsFirst, "regs-first",
                   "V6CLANG historical: register count first")),
    cl::Hidden);

// Z80-style: prioritize total in-loop instructions. Each in-loop reload on
// i8080 is ~30cc (LXI+LHLD+DAD+STAX), so trading +1 GP-pair pressure for
// fewer in-loop instructions is the right call when there's any pressure.
static bool insnsFirstLess(const TargetTransformInfo::LSRCost &C1,
                           const TargetTransformInfo::LSRCost &C2) {
  return std::tie(C1.Insns, C1.NumRegs, C1.AddRecCost, C1.NumIVMuls,
                  C1.NumBaseAdds, C1.ScaleCost, C1.ImmCost, C1.SetupCost) <
         std::tie(C2.Insns, C2.NumRegs, C2.AddRecCost, C2.NumIVMuls,
                  C2.NumBaseAdds, C2.ScaleCost, C2.ImmCost, C2.SetupCost);
}

// V6CLANG historical: prioritize register count. Each spill is also bytes in
// the prologue / per access, so register count is the better proxy for
// code size on this target.
static bool regsFirstLess(const TargetTransformInfo::LSRCost &C1,
                          const TargetTransformInfo::LSRCost &C2) {
  return std::tie(C1.NumRegs, C1.Insns, C1.NumBaseAdds, C1.NumIVMuls,
                  C1.AddRecCost, C1.ImmCost, C1.SetupCost, C1.ScaleCost) <
         std::tie(C2.NumRegs, C2.Insns, C2.NumBaseAdds, C2.NumIVMuls,
                  C2.AddRecCost, C2.ImmCost, C2.SetupCost, C2.ScaleCost);
}

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

// Address computation on 8080 is expensive: LXI (12cc) + DAD (12cc) = 24cc
// for base+index, vs INX (8cc) for pointer increment.
// Returning non-zero makes LSR prefer strength-reduced pointer forms.
// The value is an abstract relative weight, not clock cycles.
InstructionCost V6ClangTTIImpl::getAddressComputationCost(Type *Ty,
                                                       ScalarEvolution *SE,
                                                       const SCEV *Ptr) const {
  return 2;
}

bool V6ClangTTIImpl::isLSRCostLess(const TTI::LSRCost &C1,
                                const TTI::LSRCost &C2) const {
  // V6CLANG ranks LSR formulas via one of two lexicographic orderings over the
  // generic LSRCost fields:
  //
  //   regs-first  : NumRegs > Insns > NumBaseAdds > NumIVMuls > AddRecCost
  //                 > ImmCost > SetupCost > ScaleCost
  //   insns-first : Insns   > NumRegs > AddRecCost > NumIVMuls > NumBaseAdds
  //                 > ScaleCost > ImmCost > SetupCost  (Z80-style)
  //
  // Selection (per function):
  //   1. If `-v6clang-lsr-strategy={insns-first,regs-first}` is given, honor it.
  //   2. Otherwise (auto), use Regs-first regardless of optimization mode.
  //      Empirically (O51 Step 3.7) Insns-first does not win on the V6CLANG
  //      regression corpus — LSR's Insns estimate does not see the heavy
  //      reload sequences that result on the i8080 when an extra IV is
  //      kept "live" but the register file is too small to hold it. Insns-
  //      first remains available as opt-in for future targeted use.

  switch (LSRStrategyOpt) {
  case LSRStrategy::InsnsFirst:
    return insnsFirstLess(C1, C2);
  case LSRStrategy::RegsFirst:
    return regsFirstLess(C1, C2);
  case LSRStrategy::Auto:
    break;
  }

  return regsFirstLess(C1, C2);
}

// === O22: V6CLANG-tuned TTI cost hooks ============================================
//
// Numbers below are abstract relative weights (not clock cycles) tuned to
// the i8080 cost ratios documented in design/future_plans/O22_tti_cost_hooks.md
// and reflect the multi-instruction expansions visible in the regression
// corpus (e.g. tests/features/51).
//
// Every hook:
//   1. Falls back to BaseT if its per-hook flag (or the master flag) is off.
//   2. Falls back to BaseT for any type it does not understand (vectors, FP,
//      pointer types, oversize integers) so we never produce *worse* numbers
//      than BasicTTI for cases we don't model explicitly.
// ============================================================================

InstructionCost V6ClangTTIImpl::getArithmeticInstrCost(
    unsigned Opcode, Type *Ty, TTI::TargetCostKind CostKind,
    TTI::OperandValueInfo Opd1Info, TTI::OperandValueInfo Opd2Info,
    ArrayRef<const Value *> Args, const Instruction *CxtI) {
  if (!EnableTTICostHooks || !EnableArithCost)
    return BaseT::getArithmeticInstrCost(Opcode, Ty, CostKind, Opd1Info,
                                         Opd2Info, Args, CxtI);

  if (!Ty || Ty->isVectorTy() || !Ty->isIntegerTy())
    return BaseT::getArithmeticInstrCost(Opcode, Ty, CostKind, Opd1Info,
                                         Opd2Info, Args, CxtI);

  unsigned BW = Ty->getIntegerBitWidth();
  // 8-bit native ALU op (ADD/SUB/AND/OR/XOR r): 4cc, 1 instruction.
  if (BW <= 8)
    return 1;
  // 16-bit ALU expands to multi-instruction sequences (DAD, ADC, manual
  // borrow, …) — ~24-48cc, 5-10 instructions.
  if (BW <= 16)
    return 6;
  // 32-bit goes through a libcall (__mulsi3, __addsi3, etc.).
  if (BW <= 32)
    return 20;
  return BaseT::getArithmeticInstrCost(Opcode, Ty, CostKind, Opd1Info,
                                       Opd2Info, Args, CxtI);
}

InstructionCost V6ClangTTIImpl::getMemoryOpCost(
    unsigned Opcode, Type *Src, MaybeAlign Alignment, unsigned AddressSpace,
    TTI::TargetCostKind CostKind, TTI::OperandValueInfo OpInfo,
    const Instruction *I) {
  if (!EnableTTICostHooks || !EnableMemCost)
    return BaseT::getMemoryOpCost(Opcode, Src, Alignment, AddressSpace,
                                  CostKind, OpInfo, I);

  if (!Src || Src->isVectorTy() || !Src->isIntegerTy())
    return BaseT::getMemoryOpCost(Opcode, Src, Alignment, AddressSpace,
                                  CostKind, OpInfo, I);

  unsigned BW = Src->getIntegerBitWidth();
  // Every memory access requires HL setup (LXI HL, addr) — there are no
  // free indexed addressing modes on i8080.
  if (BW <= 8)
    return 2; // LXI + MOV M / MOV r,M
  if (BW <= 16)
    return 4; // LXI + MOV + INX + MOV
  if (BW <= 32)
    return 8; // 2× i16 access pattern
  return BaseT::getMemoryOpCost(Opcode, Src, Alignment, AddressSpace,
                                CostKind, OpInfo, I);
}

InstructionCost V6ClangTTIImpl::getCmpSelInstrCost(
    unsigned Opcode, Type *ValTy, Type *CondTy, CmpInst::Predicate VecPred,
    TTI::TargetCostKind CostKind, const Instruction *I) {
  if (!EnableTTICostHooks || !EnableCmpCost)
    return BaseT::getCmpSelInstrCost(Opcode, ValTy, CondTy, VecPred,
                                     CostKind, I);

  if (!ValTy || ValTy->isVectorTy() || !ValTy->isIntegerTy())
    return BaseT::getCmpSelInstrCost(Opcode, ValTy, CondTy, VecPred,
                                     CostKind, I);

  unsigned BW = ValTy->getIntegerBitWidth();
  // i1 / i8: single CMP r (4cc).
  if (BW <= 8)
    return 1;
  // i16: byte-pair compare (~CMP/Jcc/CMP/Jcc, ~2-3 i8 cmps worth). Keeping
  // this close to the i8 cost prevents LSR from rewriting cheap i16 pointer
  // /end-bound compares into i8 down-counters that round-trip through A
  // (sieve count_set regression, see plan_O22_tti_cost_hooks.md).
  if (BW <= 16)
    return 2;
  if (BW <= 32)
    return 8;
  return BaseT::getCmpSelInstrCost(Opcode, ValTy, CondTy, VecPred,
                                   CostKind, I);
}

InstructionCost V6ClangTTIImpl::getIntrinsicInstrCost(
    const IntrinsicCostAttributes &ICA, TTI::TargetCostKind CostKind) {
  if (EnableTTICostHooks) {
    // CTLZ / CTTZ / CTPOP have no hardware support and the generic Expand
    // produces a SWAR popcount sequence that needs more 16-bit live ranges
    // than the i8080 register file can sustain (HL/BC/DE only, with HL
    // typically pinned by the live caller-side pointer). Reporting these
    // intrinsics as unconditionally expensive here keeps middle-end passes
    // (notably LoopIdiomRecognize::recognizeAndInsertFFS, which would
    // rewrite `while (c <<= 1) cnt++;` into `8 - cttz(c<<1)`) from creating
    // them in the first place. The straight loop is both smaller and
    // RA-safe on V6CLANG.
    switch (ICA.getID()) {
    case Intrinsic::ctlz:
    case Intrinsic::cttz:
    case Intrinsic::ctpop:
      return TTI::TCC_Expensive;
    default:
      break;
    }
  }
  return BaseT::getIntrinsicInstrCost(ICA, CostKind);
}

InstructionCost V6ClangTTIImpl::getScalingFactorCost(Type *Ty, GlobalValue *BaseGV,
                                                  int64_t BaseOffset,
                                                  bool HasBaseReg,
                                                  int64_t Scale,
                                                  unsigned AddrSpace) {
  if (!EnableTTICostHooks || !EnableScalingCost)
    return BaseT::getScalingFactorCost(Ty, BaseGV, BaseOffset, HasBaseReg,
                                       Scale, AddrSpace);

  // V6CLANG only supports a single base register (HL) with no offset and no
  // scaled index. Anything else is invalid (mirrors isLegalAddressingMode).
  if (BaseGV || BaseOffset != 0 || (Scale != 0 && Scale != 1))
    return InstructionCost::getInvalid();
  if (!HasBaseReg && Scale == 0)
    return InstructionCost::getInvalid();
  return 0;
}

// Loop unrolling on V6CLANG must stay conservative: the target has only 3
// 16-bit register pairs (HL/DE/BC) and HL is frequently pinned by the
// live pointer of any load/store. The generic LLVM unroller, fed by
// BasicTTI's default preferences, happily fully-unrolls small constant-
// trip-count loops (e.g. an 8-iter byte copy). Each unrolled iteration
// produces an independent gr16ptr live range; with two live pointers
// (src/dst) and 8 unrolls there is no allocation that fits in 3 pairs,
// so register allocation deterministically fails with "ran out of
// registers". Killing full unroll and clamping the partial threshold
// keeps the code in loop form, which the rest of the V6CLANG pipeline
// handles efficiently (INX HL, MOV M,r, etc.).
void V6ClangTTIImpl::getUnrollingPreferences(Loop *L, ScalarEvolution &SE,
                                         TTI::UnrollingPreferences &UP,
                                         OptimizationRemarkEmitter *ORE) {
  BaseT::getUnrollingPreferences(L, SE, UP, ORE);

  // Disable full and runtime unrolling outright. Both forms multiply
  // pointer/loop-carried live ranges by the unroll factor and overflow
  // the 3-pair register file.
  UP.Force = false;
  UP.Partial = false;
  UP.Runtime = false;
  UP.UpperBound = false;
  UP.AllowRemainder = false;
  UP.AllowExpensiveTripCount = false;
  UP.UnrollAndJam = false;
  UP.UnrollRemainder = false;

  // Keep at most a 2x peel/partial unroll for very small bodies; anything
  // larger has historically tripped RA on i8080.
  UP.Threshold = 0;
  UP.PartialThreshold = 0;
  UP.OptSizeThreshold = 0;
  UP.PartialOptSizeThreshold = 0;
  UP.MaxCount = 1;
  UP.FullUnrollMaxCount = 1;
  UP.Count = 1;
}
