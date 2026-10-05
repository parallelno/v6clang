//===-- V6ClangTargetTransformInfo.h - V6CLANG specific TTI -------------*- C++ -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

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
  // Captured so isLSRCostLess() can derive the optimization mode
  // (Speed vs Size) from IR-level attributes (hasMinSize/hasOptSize).
  const Function *Func;

  const V6ClangSubtarget *getST() const { return ST; }
  const V6ClangTargetLowering *getTLI() const { return TLI; }

public:
  explicit V6ClangTTIImpl(const V6ClangTargetMachine *TM, const Function &F)
      : BaseT(TM, F.getParent()->getDataLayout()),
        ST(TM->getSubtargetImpl(F)),
        TLI(ST->getTargetLowering()),
        Func(&F) {}

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

  InstructionCost getIntrinsicInstrCost(const IntrinsicCostAttributes &ICA,
                                        TTI::TargetCostKind CostKind);

  InstructionCost getScalingFactorCost(Type *Ty, GlobalValue *BaseGV,
                                       int64_t BaseOffset, bool HasBaseReg,
                                       int64_t Scale, unsigned AddrSpace);

  // --- Loop unrolling preferences ---
  // V6CLANG has only 3 register pairs (HL/DE/BC). Default LLVM unrolling
  // multiplies live ranges by the unroll factor and routinely exhausts
  // the register file, causing "ran out of registers during register
  // allocation". Override to keep the unroller conservative.
  void getUnrollingPreferences(Loop *L, ScalarEvolution &SE,
                               TTI::UnrollingPreferences &UP,
                               OptimizationRemarkEmitter *ORE);
};

} // namespace llvm

#endif
