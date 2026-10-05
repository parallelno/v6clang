//===-- V6ClangConstantSinking.cpp - Pre-RA Constant Sinking -----------------===//
//
// Part of the V6CLANG backend for LLVM.
//
// Pre-RA pass: Sink constant materializations (LXI rp, imm / MVI r, imm)
// past conditional branches when the constant is used only in successor
// blocks.  This prevents register pressure from premature constant
// hoisting — RA sees shorter live ranges and avoids eviction cascades.
//
// After RA, O36 (branch-implied value propagation) eliminates the cloned
// constant on the branch-proven path (e.g., LXI HL,0 after a zero-test).
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "llvm/ADT/PostOrderIterator.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/Support/CommandLine.h"

using namespace llvm;

#define DEBUG_TYPE "v6clang-constant-sinking"

static cl::opt<bool> DisableConstantSinking(
    "v6clang-disable-constant-sinking",
    cl::desc("Disable V6CLANG pre-RA constant sinking"),
    cl::init(false), cl::Hidden);

namespace {

class V6ClangConstantSinking : public MachineFunctionPass {
public:
  static char ID;
  V6ClangConstantSinking() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Pre-RA Constant Sinking";
  }

  bool runOnMachineFunction(MachineFunction &MF) override;
};

} // anonymous namespace

char V6ClangConstantSinking::ID = 0;

/// Return true if Opc is a constant materialization we want to sink.
static bool isConstantMat(unsigned Opc) {
  return Opc == V6Clang::LXI || Opc == V6Clang::MVIr;
}

bool V6ClangConstantSinking::runOnMachineFunction(MachineFunction &MF) {
  if (DisableConstantSinking)
    return false;

  MachineRegisterInfo &MRI = MF.getRegInfo();
  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();
  bool Changed = false;

  // RPO iteration: dominators before successors.
  ReversePostOrderTraversal<MachineFunction *> RPOT(&MF);

  for (MachineBasicBlock *MBB : RPOT) {
    // Only interesting if the block has a conditional branch (≥2 successors).
    if (MBB->succ_size() < 2)
      continue;

    // Build successor set for fast lookup.
    SmallPtrSet<MachineBasicBlock *, 4> Succs(MBB->succ_begin(),
                                               MBB->succ_end());

    // Collect sinkable instructions (iterate forward, decide, then mutate).
    SmallVector<MachineInstr *, 4> ToSink;

    for (MachineInstr &MI : *MBB) {
      if (!isConstantMat(MI.getOpcode()))
        continue;

      Register DstReg = MI.getOperand(0).getReg();
      if (!DstReg.isVirtual())
        continue;

      // Check: ALL uses must be in direct successor blocks, either as
      // non-PHI instructions or PHI inputs with incoming edge from MBB.
      bool CanSink = true;
      bool HasUse = false;
      for (MachineInstr &UseMI : MRI.use_nodbg_instructions(DstReg)) {
        HasUse = true;
        MachineBasicBlock *UseBB = UseMI.getParent();

        if (UseBB == MBB || !Succs.count(UseBB)) {
          CanSink = false;
          break;
        }
        // For PHI uses, verify the operand comes from MBB and that the
        // same PHI does not also use DstReg from a different predecessor.
        // Sinking past a critical-edge split only places the def on the
        // MBB->SuccMBB path; any PHI input of DstReg from another
        // predecessor would lose its definition (PR/find_idx miscompile:
        // MachineCSE can legally merge two MVIr -1 defs into one whose
        // value reaches a PHI from multiple preds via dominance, and we
        // must not sink such a def).
        if (UseMI.isPHI()) {
          bool FromMBB = false;
          bool FromOtherPred = false;
          for (unsigned i = 1, e = UseMI.getNumOperands(); i < e; i += 2) {
            if (UseMI.getOperand(i).getReg() != DstReg)
              continue;
            MachineBasicBlock *Pred = UseMI.getOperand(i + 1).getMBB();
            if (Pred == MBB)
              FromMBB = true;
            else
              FromOtherPred = true;
          }
          if (!FromMBB || FromOtherPred) {
            CanSink = false;
            break;
          }
        }
      }

      if (CanSink && HasUse)
        ToSink.push_back(&MI);
    }

    // Cache of split blocks created for a given successor edge MBB->Succ.
    // Multiple constants defined in MBB may all feed PHIs in the same
    // successor via the same edge; they must share a single split block.
    // Splitting the edge more than once is wrong: after the first split
    // MBB no longer lists Succ as a successor, so a second
    // replaceSuccessor(Succ, ...) walks off the end of the successor list.
    DenseMap<MachineBasicBlock *, MachineBasicBlock *> SplitBlocks;

    // Sink each collected instruction.
    for (MachineInstr *MI : ToSink) {
      Register DstReg = MI->getOperand(0).getReg();
      const TargetRegisterClass *RC = MRI.getRegClass(DstReg);
      unsigned Opc = MI->getOpcode();
      const MachineOperand &ImmOp = MI->getOperand(1);

      // Classify uses by successor block, distinguishing PHI vs non-PHI.
      struct SuccUses {
        SmallVector<MachineOperand *, 4> Ops;
        bool HasPhi = false;
        bool HasNonPhi = false;
      };
      DenseMap<MachineBasicBlock *, SuccUses> UsesByBlock;

      for (MachineOperand &MO : MRI.use_nodbg_operands(DstReg)) {
        MachineInstr *UseMI = MO.getParent();
        MachineBasicBlock *UseBB = UseMI->getParent();
        auto &SU = UsesByBlock[UseBB];
        SU.Ops.push_back(&MO);
        if (UseMI->isPHI())
          SU.HasPhi = true;
        else
          SU.HasNonPhi = true;
      }

      // Helper: add the immediate operand to a BuildMI.
      auto addImmOperand = [&](MachineInstrBuilder &MIB) {
        if (ImmOp.isImm())
          MIB.addImm(ImmOp.getImm());
        else if (ImmOp.isGlobal())
          MIB.addGlobalAddress(ImmOp.getGlobal(), ImmOp.getOffset(),
                               ImmOp.getTargetFlags());
        else if (ImmOp.isCImm())
          MIB.addCImm(ImmOp.getCImm());
      };

      for (auto &[SuccMBB, SU] : UsesByBlock) {
        if (SU.HasPhi && !SU.HasNonPhi) {
          // PHI-only uses: manually split MBB→SuccMBB edge, reusing an
          // already-split block if a previous constant from this MBB
          // already split the same edge.
          MachineBasicBlock *NewMBB = SplitBlocks.lookup(SuccMBB);
          if (!NewMBB) {
            // Create a new block between MBB and SuccMBB.
            NewMBB = MF.CreateMachineBasicBlock();
            MF.insert(SuccMBB->getIterator(), NewMBB);

            // CFG: replace MBB→SuccMBB with MBB→NewMBB→SuccMBB.
            MBB->replaceSuccessor(SuccMBB, NewMBB);
            NewMBB->addSuccessor(SuccMBB);

            // Update terminator MBB references in MBB.
            for (MachineInstr &Term : MBB->terminators()) {
              for (MachineOperand &MO : Term.operands()) {
                if (MO.isMBB() && MO.getMBB() == SuccMBB)
                  MO.setMBB(NewMBB);
              }
            }

            // Fix PHIs in SuccMBB: incoming MBB → NewMBB.
            SuccMBB->replacePhiUsesWith(MBB, NewMBB);

            SplitBlocks[SuccMBB] = NewMBB;
          }

          // Place the constant materialization in NewMBB.
          Register NewReg = MRI.createVirtualRegister(RC);
          auto MIB = BuildMI(*NewMBB, NewMBB->end(), MI->getDebugLoc(),
                             TII.get(Opc), NewReg);
          addImmOperand(MIB);

          for (MachineOperand *MO : SU.Ops)
            MO->setReg(NewReg);

        } else if (!SU.HasPhi) {
          // Non-PHI uses only: clone into successor after PHIs.
          Register NewReg = MRI.createVirtualRegister(RC);
          auto InsertPt = SuccMBB->getFirstNonPHI();
          auto MIB = BuildMI(*SuccMBB, InsertPt, MI->getDebugLoc(),
                             TII.get(Opc), NewReg);
          addImmOperand(MIB);

          for (MachineOperand *MO : SU.Ops)
            MO->setReg(NewReg);
        }
        // Mixed PHI + non-PHI in same successor: skip (unlikely for constants).
      }

      // Erase the original if all uses were rewritten.
      if (MRI.use_nodbg_empty(DstReg)) {
        MI->eraseFromParent();
        Changed = true;
      }
    }
  }

  return Changed;
}

namespace llvm {

FunctionPass *createV6ClangConstantSinkingPass() {
  return new V6ClangConstantSinking();
}

} // namespace llvm
