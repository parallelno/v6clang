//===-- V6ClangDebugFrameIndex.cpp - Final debug frame locations -------------===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "V6ClangInstrInfo.h"
#include "V6ClangMachineFunctionInfo.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineModuleInfo.h"

using namespace llvm;

namespace {

class V6ClangDebugFrameIndex : public MachineFunctionPass {
public:
  static char ID;
  V6ClangDebugFrameIndex() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Debug Frame-Index Locations";
  }

  bool runOnMachineFunction(MachineFunction &MF) override;
};

} // namespace

char V6ClangDebugFrameIndex::ID = 0;

bool V6ClangDebugFrameIndex::runOnMachineFunction(MachineFunction &MF) {
  if (!MF.getMMI().hasDebugInfo())
    return false;

  const auto *MFI = MF.getInfo<V6ClangMachineFunctionInfo>();
  bool Changed = false;
  for (MachineBasicBlock &MBB : MF) {
    for (MachineInstr &MI : MBB) {
      if (!MI.isDebugValue())
        continue;
      for (MachineOperand &MO : MI.operands()) {
        if (!MO.isFI())
          continue;
        const int FI = MO.getIndex();
        if (MCSymbol *Patch = MFI->getO61PatchSymbol(FI)) {
          MO.ChangeToMCSymbol(Patch, V6ClangII::MO_PATCH_IMM);
          Changed = true;
        } else if (MFI->hasStaticStack() && MFI->hasStaticSlot(FI)) {
          MO.ChangeToGA(MFI->getStaticStackGV(), MFI->getStaticOffset(FI));
          Changed = true;
        }
      }
    }
  }
  return Changed;
}

FunctionPass *llvm::createV6ClangDebugFrameIndexPass() {
  return new V6ClangDebugFrameIndex();
}