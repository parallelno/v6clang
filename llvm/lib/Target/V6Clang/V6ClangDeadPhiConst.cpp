//===-- V6ClangDeadPhiConst.cpp - Dead PHI-Constant Elimination ---------------===//
//
// Part of the V6CLANG backend for LLVM.
//
// Pre-RA pass: When a V6CLANG_BR_CC16_IMM tests `reg == imm` and a PHI on the
// proven-equal edge receives the same constant `imm` (via LXI), replace the
// PHI operand with `reg` (which is proven to hold `imm` on that edge).
// The now-dead LXI is removed by DeadMachineInstrElim.
//
// This eliminates register pressure from unnecessary constant
// materialization, preventing register shuffles and spills.
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "V6ClangISelLowering.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/Support/CommandLine.h"

using namespace llvm;

#define DEBUG_TYPE "v6clang-dead-phi-const"

static cl::opt<bool> DisableDeadPhiConst(
    "v6clang-disable-dead-phi-const",
    cl::desc("Disable V6CLANG dead PHI-constant elimination"),
    cl::init(false), cl::Hidden);

namespace {

class V6ClangDeadPhiConst : public MachineFunctionPass {
public:
  static char ID;
  V6ClangDeadPhiConst() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Dead PHI-Constant Elimination";
  }

  bool runOnMachineFunction(MachineFunction &MF) override;

private:
  /// Check if two MachineOperands represent the same immediate value.
  static bool isSameImmediate(const MachineOperand &A,
                              const MachineOperand &B);
};

} // anonymous namespace

char V6ClangDeadPhiConst::ID = 0;

bool V6ClangDeadPhiConst::isSameImmediate(const MachineOperand &A,
                                       const MachineOperand &B) {
  if (A.isImm() && B.isImm())
    return A.getImm() == B.getImm();
  if (A.isGlobal() && B.isGlobal())
    return A.getGlobal() == B.getGlobal() && A.getOffset() == B.getOffset();
  return false;
}

bool V6ClangDeadPhiConst::runOnMachineFunction(MachineFunction &MF) {
  if (DisableDeadPhiConst)
    return false;

  MachineRegisterInfo &MRI = MF.getRegInfo();
  bool Changed = false;

  for (MachineBasicBlock &MBB : MF) {
    // Need at least 2 successors for a meaningful conditional branch.
    if (MBB.succ_size() < 2)
      continue;

    // Scan terminators for V6CLANG_BR_CC16_IMM.
    for (MachineInstr &MI : MBB.terminators()) {
      if (MI.getOpcode() != V6CLANG::V6CLANG_BR_CC16_IMM)
        continue;

      // Operand layout: 0=$lhs(GR16), 1=$rhs(imm16), 2=$cc, 3=$dst
      Register LhsReg = MI.getOperand(0).getReg();
      const MachineOperand &RhsOp = MI.getOperand(1);
      int64_t CC = MI.getOperand(2).getImm();
      MachineBasicBlock *Target = MI.getOperand(3).getMBB();

      // Only handle EQ/NE.
      if (CC != V6ClangCC::COND_Z && CC != V6ClangCC::COND_NZ)
        continue;

      // Determine the "proven equal" successor.
      // COND_Z:  branch taken   → reg == imm on Target edge.
      // COND_NZ: branch not taken → reg == imm on fallthrough edge.
      MachineBasicBlock *ProvenEqMBB = nullptr;
      if (CC == V6ClangCC::COND_Z) {
        ProvenEqMBB = Target;
      } else {
        // COND_NZ: fallthrough is the non-Target successor.
        for (MachineBasicBlock *Succ : MBB.successors()) {
          if (Succ != Target) {
            ProvenEqMBB = Succ;
            break;
          }
        }
      }

      if (!ProvenEqMBB)
        continue;

      // Scan PHI nodes in ProvenEqMBB.
      for (MachineInstr &Phi : ProvenEqMBB->phis()) {
        // PHI operands: [def], [val1, mbb1], [val2, mbb2], ...
        for (unsigned i = 1, e = Phi.getNumOperands(); i < e; i += 2) {
          MachineBasicBlock *PredMBB = Phi.getOperand(i + 1).getMBB();
          if (PredMBB != &MBB)
            continue;

          Register ValReg = Phi.getOperand(i).getReg();
          if (!ValReg.isVirtual())
            continue;

          MachineInstr *DefMI = MRI.getVRegDef(ValReg);
          if (!DefMI || DefMI->getOpcode() != V6CLANG::LXI)
            continue;

          // Check if LXI's immediate matches the branch RHS.
          const MachineOperand &LxiImm = DefMI->getOperand(1);
          if (!isSameImmediate(RhsOp, LxiImm))
            continue;

          // Replace PHI operand: use LhsReg instead of the constant.
          Phi.getOperand(i).setReg(LhsReg);
          Changed = true;

          // If LXI now has no uses, erase it directly.
          // (DeadMachineInstrElim runs before addPreRegAlloc.)
          if (MRI.use_nodbg_empty(ValReg))
            DefMI->eraseFromParent();
        }
      }
    }
  }

  return Changed;
}

namespace llvm {

FunctionPass *createV6ClangDeadPhiConstPass() {
  return new V6ClangDeadPhiConst();
}

} // namespace llvm
