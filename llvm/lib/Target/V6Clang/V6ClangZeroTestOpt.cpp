//===-- V6ClangZeroTestOpt.cpp - Replace CPI 0 with ORA A --------------------===//
//
// Part of the V6CLANG backend for LLVM.
//
// Post-RA peephole: Replace CPI 0 (8cc) with ORA A (4cc) when testing the
// accumulator against zero. Both set Z and S flags identically for zero-test.
// CPI also sets CY=0, while ORA A sets CY=0, so flags are compatible.
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/Support/CommandLine.h"

using namespace llvm;

#define DEBUG_TYPE "v6clang-zero-test-opt"

static cl::opt<bool> DisableZeroTestOpt(
    "v6clang-disable-zero-test-opt",
    cl::desc("Disable V6CLANG CPI 0 -> ORA A optimization"),
    cl::init(false), cl::Hidden);

namespace {

class V6ClangZeroTestOpt : public MachineFunctionPass {
public:
  static char ID;
  V6ClangZeroTestOpt() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Zero Test Optimization";
  }

  bool runOnMachineFunction(MachineFunction &MF) override;
};

} // end anonymous namespace

char V6ClangZeroTestOpt::ID = 0;

bool V6ClangZeroTestOpt::runOnMachineFunction(MachineFunction &MF) {
  if (DisableZeroTestOpt)
    return false;

  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();
  bool Changed = false;

  for (MachineBasicBlock &MBB : MF) {
    for (MachineInstr &MI : llvm::make_early_inc_range(MBB)) {
      // Look for CPI with immediate operand == 0.
      if (MI.getOpcode() != V6Clang::CPI)
        continue;

      // CPI has operands: (Acc:$lhs, imm8:$imm)
      // Operand 0 is $lhs (Acc register), operand 1 is the immediate.
      const MachineOperand &ImmOp = MI.getOperand(1);
      if (!ImmOp.isImm() || ImmOp.getImm() != 0)
        continue;
      // Skip O61-patched immediates: their imm byte is rewritten at
      // runtime via `STA Sym+1`, which requires the 2-byte CPI form
      // (opcode + imm). Folding to single-byte ORA A would orphan the
      // pre-instr-symbol that the spill site references.
      if (ImmOp.getTargetFlags() != 0)
        continue;
      if (MI.getPreInstrSymbol())
        continue;

      // Replace CPI 0 with ORA A (which is: A = A | A, sets Z/S flags).
      DebugLoc DL = MI.getDebugLoc();
      BuildMI(MBB, MI, DL, TII.get(V6Clang::ORAr), V6Clang::A)
          .addReg(V6Clang::A)
          .addReg(V6Clang::A);
      MI.eraseFromParent();
      Changed = true;
    }
  }

  return Changed;
}

FunctionPass *llvm::createV6ClangZeroTestOptPass() {
  return new V6ClangZeroTestOpt();
}
