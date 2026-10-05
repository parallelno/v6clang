//===-- V6ClangStaticDebugValues.cpp - Salvage static local locations -*- C++ -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/DebugInfoMetadata.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/Operator.h"

using namespace llvm;

#define DEBUG_TYPE "v6clang-static-debug-values"

namespace {

struct StaticLocation {
  const GlobalVariable *GV;
  int64_t Offset;
  const DILocalVariable *Variable;
  const DIExpression *Expression;
  DebugLoc DL;
};

class V6ClangStaticDebugValues : public MachineFunctionPass {
public:
  static char ID;
  V6ClangStaticDebugValues() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Static Debug Value Salvage";
  }

  bool runOnMachineFunction(MachineFunction &MF) override;

  void getAnalysisUsage(AnalysisUsage &AU) const override {
    AU.setPreservesCFG();
    MachineFunctionPass::getAnalysisUsage(AU);
  }
};

} // namespace

char V6ClangStaticDebugValues::ID = 0;

static bool isWithinLexicalScope(const DIScope *Scope,
                                 const DIScope *Ancestor) {
  while (Scope) {
    if (Scope == Ancestor)
      return true;
    const auto *LexicalBlock = dyn_cast<DILexicalBlockBase>(Scope);
    if (!LexicalBlock)
      return false;
    Scope = LexicalBlock->getScope();
  }
  return false;
}

bool V6ClangStaticDebugValues::runOnMachineFunction(MachineFunction &MF) {
  if (!MF.getMMI().hasDebugInfo())
    return false;

  const Function &F = MF.getFunction();
  const DataLayout &DL = F.getParent()->getDataLayout();
  SmallVector<StaticLocation, 4> Locations;

  for (const BasicBlock &BB : F) {
    for (const Instruction &I : BB) {
      const auto *DDI = dyn_cast<DbgDeclareInst>(&I);
      if (!DDI)
        continue;

      const Value *Address = DDI->getAddress();
      if (!Address)
        continue;

      int64_t Offset = 0;
      const GlobalVariable *GV = dyn_cast<GlobalVariable>(Address);
      if (!GV) {
        const auto *GEP = dyn_cast<GEPOperator>(Address);
        if (!GEP)
          continue;
        APInt APOffset(DL.getIndexSizeInBits(GEP->getPointerAddressSpace()), 0,
                       /*isSigned=*/true);
        if (!GEP->accumulateConstantOffset(DL, APOffset))
          continue;
        GV = dyn_cast<GlobalVariable>(GEP->getPointerOperand()->stripPointerCasts());
        if (!GV)
          continue;
        Offset = APOffset.getSExtValue();
      }

      Locations.push_back({GV, Offset, DDI->getVariable(),
                           DDI->getExpression(), DDI->getDebugLoc()});
    }
  }

  if (Locations.empty())
    return false;

  SmallPtrSet<const DILocalVariable *, 4> Salvaged;
  for (const StaticLocation &Loc : Locations)
    Salvaged.insert(Loc.Variable);

  for (MachineBasicBlock &MBB : MF) {
    for (MachineInstr &MI : llvm::make_early_inc_range(MBB)) {
      if (!MI.isDebugValue())
        continue;
      if (const auto *Variable = MI.getDebugVariable())
        if (Salvaged.contains(Variable))
          MI.eraseFromParent();
    }
  }

  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();
  for (const StaticLocation &Loc : Locations) {
    const auto *VariableScope = dyn_cast<DIScope>(Loc.Variable->getScope());
    if (!VariableScope)
      continue;

    for (MachineBasicBlock &MBB : MF) {
      for (auto It = MBB.begin(), End = MBB.end(); It != End; ++It) {
        const DebugLoc InstrDL = It->getDebugLoc();
        const auto *InstructionScope =
            InstrDL ? dyn_cast<DIScope>(InstrDL.getScope()) : nullptr;
        if (It->isDebugInstr() || !InstructionScope ||
            !isWithinLexicalScope(InstructionScope, VariableScope))
          continue;

        BuildMI(MBB, It, Loc.DL, TII.get(TargetOpcode::DBG_VALUE))
            .addGlobalAddress(Loc.GV, Loc.Offset)
            .addImm(0)
            .addMetadata(Loc.Variable)
            .addMetadata(Loc.Expression);
        break;
      }
    }
  }

  return true;
}

FunctionPass *llvm::createV6ClangStaticDebugValuesPass() {
  return new V6ClangStaticDebugValues();
}
