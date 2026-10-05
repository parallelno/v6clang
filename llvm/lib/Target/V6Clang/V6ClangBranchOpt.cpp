//===-- V6ClangBranchOpt.cpp - V6CLANG Branch Optimizations ----------------------===//
//
// Part of the V6CLANG backend for LLVM.
//
// Post-RA pass for branch optimizations:
//
// 1. Branch threading: if a branch (Jcc or JMP) targets a block whose
//    only instruction is JMP target, redirect the branch directly to
//    target.
//
// 2. Redundant JMP elimination: JMP to the immediately following block
//    (layout successor) is removed — the fall-through is free.
//
// 3. Conditional branch inversion: if a Jcc jumps over a JMP, invert the
//    condition and remove the JMP.
//    Example:  JZ .Ltmp1 / JMP .Ltmp2 / .Ltmp1:
//           →  JNZ .Ltmp2 / .Ltmp1:
//
// 4. Dead block removal: blocks with no predecessors (after other opts)
//    are removed.
//
// 5. Conditional return folding: Jcc to a block containing only RET is
//    replaced with the corresponding Rcc instruction (e.g. JZ→RZ).
//
// 6. Conditional return over RET: if a Jcc jumps over a fallthrough RET
//    to its layout successor, replace Jcc+RET with the inverted Rcc.
//    Example:  JZ .Lskip / RET / .Lskip:
//           →  RNZ / .Lskip:
//
// 7. Zero-select return folding: a triangle CFG from select_cc where the
//    fallthrough arm materializes the same value already in A is replaced
//    with a conditional return.
//    Example:  CPI 0 / JNZ .Lskip / MVI E,0 / .Lskip: MOV A,E / RET
//           →  CPI 0 / RZ / MOV A,E / RET
//
// 8. Conditional call folding (O15): Jcc skip / CALL fn / skip: is
//    replaced with the inverted conditional call (e.g. JZ→CNZ).
//    Example:  JZ .Lskip / CALL foo / .Lskip:
//           →  CNZ foo / .Lskip:
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "V6ClangISelLowering.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/Support/CommandLine.h"

using namespace llvm;

#define DEBUG_TYPE "v6clang-branch-opt"

static cl::opt<bool> DisableBranchOpt(
    "v6clang-disable-branch-opt",
    cl::desc("Disable V6CLANG branch optimizations"),
    cl::init(false), cl::Hidden);

namespace {

class V6ClangBranchOpt : public MachineFunctionPass {
public:
  static char ID;
  V6ClangBranchOpt() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Branch Optimization";
  }

  bool runOnMachineFunction(MachineFunction &MF) override;

private:
  bool invertConditionalOverRET(MachineFunction &MF);
  bool foldZeroSelectReturn(MachineFunction &MF);
  bool threadJMPOnlyBlocks(MachineFunction &MF);
  bool removeRedundantJMP(MachineFunction &MF);
  bool invertConditionalBranch(MachineFunction &MF);
  bool foldConditionalCalls(MachineFunction &MF);
  bool foldConditionalReturns(MachineFunction &MF);
  bool removeDeadBlocks(MachineFunction &MF);

  /// Get the inverted opcode for a conditional jump, or 0 if not invertible.
  static unsigned getInvertedJcc(unsigned Opc);
};

} // end anonymous namespace

char V6ClangBranchOpt::ID = 0;

unsigned V6ClangBranchOpt::getInvertedJcc(unsigned Opc) {
  switch (Opc) {
  case V6CLANG::JNZ: return V6CLANG::JZ;
  case V6CLANG::JZ:  return V6CLANG::JNZ;
  case V6CLANG::JNC: return V6CLANG::JC;
  case V6CLANG::JC:  return V6CLANG::JNC;
  case V6CLANG::JPO: return V6CLANG::JPE;
  case V6CLANG::JPE: return V6CLANG::JPO;
  case V6CLANG::JP:  return V6CLANG::JM;
  case V6CLANG::JM:  return V6CLANG::JP;
  default: return 0;
  }
}

/// Thread branches through JMP-only successor blocks.
/// If a branch (Jcc or JMP) targets a block whose only non-debug
/// instruction is JMP/V6CLANG_TAILJMP target, redirect the branch to
/// target directly.
bool V6ClangBranchOpt::threadJMPOnlyBlocks(MachineFunction &MF) {
  bool Changed = false;

  for (MachineBasicBlock &MBB : MF) {
    for (MachineInstr &MI : MBB.terminators()) {
      // Must be a branch to an MBB (Jcc or JMP).
      if (MI.getOpcode() != V6CLANG::JMP && !getInvertedJcc(MI.getOpcode()))
        continue;
      if (!MI.getOperand(0).isMBB())
        continue;

      MachineBasicBlock *Target = MI.getOperand(0).getMBB();

      // Check if Target is a JMP-only block.
      auto FirstNonDbg = Target->getFirstNonDebugInstr();
      if (FirstNonDbg == Target->end())
        continue;
      if (FirstNonDbg->getOpcode() != V6CLANG::JMP &&
          FirstNonDbg->getOpcode() != V6CLANG::V6CLANG_TAILJMP)
        continue;
      // Verify it's the only non-debug instruction.
      auto Next = std::next(FirstNonDbg);
      while (Next != Target->end() && Next->isDebugInstr())
        ++Next;
      if (Next != Target->end())
        continue;

      // Redirect our branch to the JMP's final target.
      MachineOperand &FinalTargetOp = FirstNonDbg->getOperand(0);

      if (FinalTargetOp.isMBB()) {
        // Internal branch: redirect to the final MBB.
        MI.getOperand(0).setMBB(FinalTargetOp.getMBB());
        MBB.replaceSuccessor(Target, FinalTargetOp.getMBB());
      } else if (FinalTargetOp.isGlobal()) {
        // External tail call (global address): redirect Jcc to symbol.
        MI.getOperand(0).ChangeToGA(FinalTargetOp.getGlobal(),
                                     FinalTargetOp.getOffset(),
                                     FinalTargetOp.getTargetFlags());
        MBB.removeSuccessor(Target);
      } else if (FinalTargetOp.isSymbol()) {
        MI.getOperand(0).ChangeToES(FinalTargetOp.getSymbolName(),
                                     FinalTargetOp.getTargetFlags());
        MBB.removeSuccessor(Target);
      } else if (FinalTargetOp.isMCSymbol()) {
        MI.getOperand(0).ChangeToMCSymbol(FinalTargetOp.getMCSymbol(),
                                           FinalTargetOp.getTargetFlags());
        MBB.removeSuccessor(Target);
      } else {
        continue; // Unknown operand type — skip.
      }
      Changed = true;
    }
  }

  return Changed;
}

/// Remove unconditional JMP instructions that jump to the next block
/// in layout order (fall-through).
bool V6ClangBranchOpt::removeRedundantJMP(MachineFunction &MF) {
  bool Changed = false;

  for (MachineBasicBlock &MBB : MF) {
    // Find the last instruction in the block.
    if (MBB.empty())
      continue;

    MachineInstr &Last = MBB.back();
    if (Last.getOpcode() != V6CLANG::JMP)
      continue;
    if (!Last.getOperand(0).isMBB())
      continue;

    // Check if the JMP target is the layout successor.
    MachineBasicBlock *Target = Last.getOperand(0).getMBB();
    MachineFunction::iterator NextBB = std::next(MBB.getIterator());
    if (NextBB != MF.end() && &*NextBB == Target) {
      Last.eraseFromParent();
      Changed = true;
    }
  }

  return Changed;
}

/// Look for patterns: Jcc .Lskip / JMP .Ltarget / .Lskip:
/// Transform to: Jcc_inv .Ltarget / .Lskip:
/// Also handles V6CLANG_TAILJMP (tail call) as the unconditional branch.
/// Saves 3 bytes and ~12cc.
bool V6ClangBranchOpt::invertConditionalBranch(MachineFunction &MF) {
  bool Changed = false;

  for (MachineBasicBlock &MBB : MF) {
    // Need at least 2 instructions.
    if (MBB.size() < 2)
      continue;

    auto LastI = MBB.end();
    --LastI; // Points to last instruction.
    MachineInstr &Last = *LastI;
    if (Last.getOpcode() != V6CLANG::JMP &&
        Last.getOpcode() != V6CLANG::V6CLANG_TAILJMP)
      continue;

    --LastI; // Points to second-to-last instruction.
    MachineInstr &Prev = *LastI;
    unsigned InvOpc = getInvertedJcc(Prev.getOpcode());
    if (!InvOpc)
      continue;

    // The Jcc target must be the layout successor (fall-through after the JMP).
    if (!Prev.getOperand(0).isMBB())
      continue;
    MachineBasicBlock *JccTarget = Prev.getOperand(0).getMBB();
    MachineFunction::iterator NextBB = std::next(MBB.getIterator());
    if (NextBB == MF.end() || &*NextBB != JccTarget)
      continue;

    // Transform: invert the Jcc to jump to the JMP/V6CLANG_TAILJMP's target,
    // remove the unconditional branch.
    const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();

    BuildMI(MBB, Prev, Prev.getDebugLoc(), TII.get(InvOpc))
        .add(Last.getOperand(0));

    // Update CFG: MBB now branches to JmpTarget and falls through to JccTarget.
    // The old successors are still correct since we flipped the condition.
    Last.eraseFromParent();
    Prev.eraseFromParent();
    Changed = true;
  }

  return Changed;
}

/// Map Jcc opcode to corresponding Rcc opcode, or 0 if not a Jcc.
static unsigned getConditionalReturn(unsigned JccOpc) {
  switch (JccOpc) {
  case V6CLANG::JZ:  return V6CLANG::RZ;
  case V6CLANG::JNZ: return V6CLANG::RNZ;
  case V6CLANG::JC:  return V6CLANG::RC;
  case V6CLANG::JNC: return V6CLANG::RNC;
  case V6CLANG::JPE: return V6CLANG::RPE;
  case V6CLANG::JPO: return V6CLANG::RPO;
  case V6CLANG::JP:  return V6CLANG::RP;
  case V6CLANG::JM:  return V6CLANG::RM;
  default: return 0;
  }
}

/// Return true if MBB contains only RET (ignoring debug instructions).
static bool isReturnOnlyBlock(const MachineBasicBlock &MBB) {
  for (const MachineInstr &MI : MBB) {
    if (MI.isDebugInstr())
      continue;
    return MI.getOpcode() == V6CLANG::RET;
  }
  return false; // empty block
}

/// Look for the pattern:
///   MBB: ... Jcc target [JMP retBB]
///   retBB: RET                          (layout successor of MBB, RET-only)
///   target: ...                         (layout successor of retBB)
///
/// Transform to:
///   MBB: ... Rcc_inv                    (inverted conditional return)
///   target: ...                         (falls through from MBB)
///
/// The retBB is removed (dead — no other predecessors).
bool V6ClangBranchOpt::invertConditionalOverRET(MachineFunction &MF) {
  bool Changed = false;
  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();
  SmallVector<MachineBasicBlock *, 4> DeadBlocks;

  for (MachineBasicBlock &MBB : MF) {
    if (MBB.empty())
      continue;

    // Find Jcc (and optional JMP to RET block).
    MachineInstr *JccMI = nullptr;
    MachineInstr *JmpMI = nullptr;

    MachineInstr &Last = MBB.back();
    if (getInvertedJcc(Last.getOpcode())) {
      // Pattern A: block ends with single Jcc.
      JccMI = &Last;
    } else if (Last.getOpcode() == V6CLANG::JMP && Last.getOperand(0).isMBB()) {
      // Pattern B: block ends with Jcc + JMP.
      auto It = Last.getIterator();
      if (It != MBB.begin()) {
        --It;
        if (getInvertedJcc(It->getOpcode())) {
          JccMI = &*It;
          JmpMI = &Last;
        }
      }
    }

    if (!JccMI || !JccMI->getOperand(0).isMBB())
      continue;

    MachineBasicBlock *JccTarget = JccMI->getOperand(0).getMBB();

    // Layout successor of MBB must be a RET-only block.
    MachineFunction::iterator NextIt = std::next(MBB.getIterator());
    if (NextIt == MF.end())
      continue;
    MachineBasicBlock &RetBB = *NextIt;
    if (!isReturnOnlyBlock(RetBB))
      continue;

    // If JMP present, it must target RetBB (the RET-only layout successor).
    if (JmpMI && JmpMI->getOperand(0).getMBB() != &RetBB)
      continue;

    // RetBB must have exactly one predecessor (MBB).
    if (RetBB.pred_size() != 1)
      continue;

    // JccTarget must be the layout successor of RetBB.
    MachineFunction::iterator AfterRet = std::next(NextIt);
    if (AfterRet == MF.end() || &*AfterRet != JccTarget)
      continue;

    // Don't fire if JccTarget is a JMP-only block — threading handles
    // that case better (redirects Jcc to the final target directly).
    {
      auto FirstNonDbg = JccTarget->getFirstNonDebugInstr();
      if (FirstNonDbg != JccTarget->end() &&
          (FirstNonDbg->getOpcode() == V6CLANG::JMP ||
           FirstNonDbg->getOpcode() == V6CLANG::V6CLANG_TAILJMP)) {
        auto NextInst = std::next(FirstNonDbg);
        while (NextInst != JccTarget->end() && NextInst->isDebugInstr())
          ++NextInst;
        if (NextInst == JccTarget->end())
          continue; // JMP-only block — let threading handle it
      }
    }

    // Map inverted Jcc → Rcc.
    unsigned InvOpc = getInvertedJcc(JccMI->getOpcode());
    unsigned RccOpc = getConditionalReturn(InvOpc);
    if (!RccOpc)
      continue;

    // Replace with Rcc_inv.
    BuildMI(MBB, *JccMI, JccMI->getDebugLoc(), TII.get(RccOpc));

    // Remove old instructions.
    if (JmpMI)
      JmpMI->eraseFromParent();
    JccMI->eraseFromParent();

    // Remove successor edge to RetBB.
    MBB.removeSuccessor(&RetBB);

    // RetBB is now dead.
    DeadBlocks.push_back(&RetBB);
    Changed = true;
  }

  // Remove dead RET blocks.
  for (MachineBasicBlock *Dead : DeadBlocks) {
    while (!Dead->succ_empty())
      Dead->removeSuccessor(Dead->succ_begin());
    Dead->eraseFromParent();
  }

  return Changed;
}

/// Fold zero-select triangle into conditional return.
///
/// Pattern:
///   bb.0: CPI $a, Imm; JNZ SkipBB    (compare A with Imm, skip if not equal)
///   FallthroughBB: MOV Rx, A          (exactly one non-debug instruction,
///                  or MVI Rx, Imm      copies value already in A to Rx)
///   SkipBB: MOV A, Rx; RET            (exactly two non-debug instructions)
///
/// On JNZ fallthrough (Z set, A == Imm), FallthroughBB sets Rx = A(=Imm),
/// then SkipBB copies Rx back to A and returns. Since A already holds Imm,
/// the entire fallthrough path is a no-op for the return value.
///
/// Transform to:
///   bb.0: CPI $a, Imm; RZ             (return if A == Imm)
///   SkipBB: MOV A, Rx; RET            (A != Imm path, unchanged)
///
/// FallthroughBB is removed as dead code.
bool V6ClangBranchOpt::foldZeroSelectReturn(MachineFunction &MF) {
  bool Changed = false;
  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();
  SmallVector<MachineBasicBlock *, 4> DeadBlocks;

  for (MachineBasicBlock &MBB : MF) {
    if (MBB.empty())
      continue;

    // 1. Last instruction must be JNZ targeting a local MBB.
    MachineInstr &Jcc = MBB.back();
    if (Jcc.getOpcode() != V6CLANG::JNZ || !Jcc.getOperand(0).isMBB())
      continue;
    MachineBasicBlock *SkipBB = Jcc.getOperand(0).getMBB();

    // 2. Previous non-debug instruction must be CPI $a, Imm.
    auto PrevIt = Jcc.getIterator();
    if (PrevIt == MBB.begin())
      continue;
    --PrevIt;
    while (PrevIt != MBB.begin() && PrevIt->isDebugInstr())
      --PrevIt;
    if (PrevIt->isDebugInstr() || PrevIt->getOpcode() != V6CLANG::CPI)
      continue;
    if (!PrevIt->getOperand(1).isImm())
      continue;
    int64_t CpiImm = PrevIt->getOperand(1).getImm() & 0xFF;

    // 3. FallthroughBB = layout successor of MBB.
    MachineFunction::iterator NextIt = std::next(MBB.getIterator());
    if (NextIt == MF.end())
      continue;
    MachineBasicBlock &FallthroughBB = *NextIt;
    if (!MBB.isSuccessor(&FallthroughBB))
      continue;

    // FallthroughBB must have exactly one non-debug instruction that
    // assigns CpiImm to some register Rx. Two forms:
    //   (a) MVI Rx, CpiImm   (before LoadImmCombine)
    //   (b) MOV Rx, A         (after LoadImmCombine when CpiImm == value in A)
    auto FTI = FallthroughBB.getFirstNonDebugInstr();
    if (FTI == FallthroughBB.end())
      continue;
    Register Rx;
    if (FTI->getOpcode() == V6CLANG::MVIr) {
      if (!FTI->getOperand(1).isImm() ||
          (FTI->getOperand(1).getImm() & 0xFF) != CpiImm)
        continue;
      Rx = FTI->getOperand(0).getReg();
    } else if (FTI->getOpcode() == V6CLANG::MOVrr) {
      // MOV Rx, A — on Z fallthrough, A holds CpiImm.
      if (FTI->getOperand(1).getReg() != V6CLANG::A)
        continue;
      Rx = FTI->getOperand(0).getReg();
    } else {
      continue;
    }
    {
      auto FTNext = std::next(FTI);
      while (FTNext != FallthroughBB.end() && FTNext->isDebugInstr())
        ++FTNext;
      if (FTNext != FallthroughBB.end())
        continue; // More than one non-debug instruction.
    }

    // 4. SkipBB must be the layout successor of FallthroughBB.
    MachineFunction::iterator AfterFT = std::next(NextIt);
    if (AfterFT == MF.end() || &*AfterFT != SkipBB)
      continue;

    // 5. SkipBB must have exactly: MOV A, Rx; RET.
    auto SI = SkipBB->getFirstNonDebugInstr();
    if (SI == SkipBB->end() || SI->getOpcode() != V6CLANG::MOVrr)
      continue;
    if (SI->getOperand(0).getReg() != V6CLANG::A ||
        SI->getOperand(1).getReg() != Rx)
      continue;
    {
      auto SI2 = std::next(SI);
      while (SI2 != SkipBB->end() && SI2->isDebugInstr())
        ++SI2;
      if (SI2 == SkipBB->end() || SI2->getOpcode() != V6CLANG::RET)
        continue;
      auto SI3 = std::next(SI2);
      while (SI3 != SkipBB->end() && SI3->isDebugInstr())
        ++SI3;
      if (SI3 != SkipBB->end())
        continue; // More than two non-debug instructions.
    }

    // 6. FallthroughBB must fall through to SkipBB (single successor)
    //    and have only MBB as predecessor (so we can safely delete it).
    if (FallthroughBB.succ_size() != 1 ||
        *FallthroughBB.succ_begin() != SkipBB)
      continue;
    if (FallthroughBB.pred_size() != 1)
      continue;

    // Transform: replace JNZ with RZ.
    BuildMI(MBB, Jcc, Jcc.getDebugLoc(), TII.get(V6CLANG::RZ));
    Jcc.eraseFromParent();

    // Update CFG: remove fallthrough edge to FallthroughBB,
    // keep SkipBB as successor (NZ fallthrough after RZ).
    MBB.removeSuccessor(&FallthroughBB);

    // FallthroughBB is now dead (only predecessor was MBB).
    FallthroughBB.removeSuccessor(SkipBB);
    DeadBlocks.push_back(&FallthroughBB);

    Changed = true;
  }

  for (MachineBasicBlock *Dead : DeadBlocks)
    Dead->eraseFromParent();

  return Changed;
}

/// Map Jcc opcode to the corresponding inverted-condition Cxx call
/// opcode. The inversion is intentional: in the pattern
///     Jcc skip / CALL fn / skip:
/// the CALL fires iff the Jcc condition is FALSE, so the equivalent
/// fused opcode tests the inverse predicate (e.g. JZ → CNZ).
static unsigned getConditionalCall(unsigned JccOpc) {
  switch (JccOpc) {
  case V6CLANG::JZ:  return V6CLANG::CNZ;
  case V6CLANG::JNZ: return V6CLANG::CZ;
  case V6CLANG::JC:  return V6CLANG::CNC;
  case V6CLANG::JNC: return V6CLANG::CC;
  case V6CLANG::JPE: return V6CLANG::CPO;
  case V6CLANG::JPO: return V6CLANG::CPE;
  case V6CLANG::JP:  return V6CLANG::CM;
  case V6CLANG::JM:  return V6CLANG::CP;
  default: return 0;
  }
}

/// Fold Jcc-over-CALL into a single conditional CALL instruction.
///
/// Pattern:
///   bb.MBB:    ... ; Jcc bb.skip                (last terminator)
///   bb.call:   CALL fn                          (only non-debug instr,
///                                                single pred = MBB,
///                                                single succ = bb.skip)
///   bb.skip:   ...                              (layout successor of bb.call)
///
/// Transform:
///   bb.MBB:    ... ; Cxx_inv fn                 (forwards all operands of
///                                                the original CALL,
///                                                including the RegMask)
///   bb.skip:   ...                              (falls through from MBB)
///
/// bb.call becomes dead and is removed.
///
/// IPRA correctness: the original CALL carries a RegMask operand added
/// by LowerCall (see O39). All operands are forwarded verbatim onto the
/// new Cxx so the per-callee narrowed clobber set is preserved.
bool V6ClangBranchOpt::foldConditionalCalls(MachineFunction &MF) {
  bool Changed = false;
  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();
  SmallVector<MachineBasicBlock *, 4> DeadBlocks;

  for (MachineBasicBlock &MBB : MF) {
    if (MBB.empty())
      continue;

    // Last instruction must be a Jcc to a local MBB.
    MachineInstr &Jcc = MBB.back();
    unsigned CxxOpc = getConditionalCall(Jcc.getOpcode());
    if (!CxxOpc)
      continue;
    if (!Jcc.getOperand(0).isMBB())
      continue;
    MachineBasicBlock *SkipBB = Jcc.getOperand(0).getMBB();

    // Layout successor of MBB is the call block.
    MachineFunction::iterator NextIt = std::next(MBB.getIterator());
    if (NextIt == MF.end())
      continue;
    MachineBasicBlock &CallBB = *NextIt;
    if (&CallBB == SkipBB)
      continue;
    if (!MBB.isSuccessor(&CallBB))
      continue;

    // CallBB: single predecessor (so we can delete it safely),
    // single successor (must be SkipBB).
    if (CallBB.pred_size() != 1)
      continue;
    if (CallBB.succ_size() != 1 || *CallBB.succ_begin() != SkipBB)
      continue;

    // SkipBB must be the layout successor of CallBB (so the fused Cxx
    // in MBB falls through to SkipBB just as the original Jcc did).
    MachineFunction::iterator AfterCall = std::next(NextIt);
    if (AfterCall == MF.end() || &*AfterCall != SkipBB)
      continue;

    // CallBB must contain exactly one non-debug instruction: a CALL
    // (not a tail call, not anything else — e.g. a result COPY would
    // disqualify the fold because the COPY belongs to that block only).
    auto FirstNonDbg = CallBB.getFirstNonDebugInstr();
    if (FirstNonDbg == CallBB.end())
      continue;
    if (FirstNonDbg->getOpcode() != V6CLANG::CALL)
      continue;
    auto NextInst = std::next(FirstNonDbg);
    while (NextInst != CallBB.end() && NextInst->isDebugInstr())
      ++NextInst;
    if (NextInst != CallBB.end())
      continue; // More than one non-debug instruction.

    MachineInstr &CallMI = *FirstNonDbg;

    // Build the conditional CALL. Forward the brtarget operand and
    // every remaining operand of the original CALL (implicit reg uses
    // for arguments, implicit defs for return values, and — critical —
    // the RegMask operand for IPRA).
    auto MIB = BuildMI(MBB, Jcc, Jcc.getDebugLoc(), TII.get(CxxOpc));
    for (const MachineOperand &MO : CallMI.operands())
      MIB.add(MO);

    // Tear down the original instructions and the dead CallBB edge.
    Jcc.eraseFromParent();
    CallMI.eraseFromParent();

    MBB.removeSuccessor(&CallBB);
    // CallBB is now dead (single-pred was MBB).
    DeadBlocks.push_back(&CallBB);
    Changed = true;
  }

  for (MachineBasicBlock *Dead : DeadBlocks) {
    while (!Dead->succ_empty())
      Dead->removeSuccessor(Dead->succ_begin());
    Dead->eraseFromParent();
  }

  return Changed;
}

/// Replace Jcc .Lret with Rcc when .Lret contains only RET.
bool V6ClangBranchOpt::foldConditionalReturns(MachineFunction &MF) {
  bool Changed = false;
  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();

  for (MachineBasicBlock &MBB : MF) {
    for (auto I = MBB.terminators().begin(), E = MBB.terminators().end();
         I != E; ++I) {
      unsigned RccOpc = getConditionalReturn(I->getOpcode());
      if (!RccOpc)
        continue;
      if (!I->getOperand(0).isMBB())
        continue;

      MachineBasicBlock *Target = I->getOperand(0).getMBB();
      if (!isReturnOnlyBlock(*Target))
        continue;

      // Replace Jcc with Rcc.
      BuildMI(MBB, *I, I->getDebugLoc(), TII.get(RccOpc));

      // Update CFG: remove the edge to the RET block.
      MBB.removeSuccessor(Target);

      I->eraseFromParent();
      Changed = true;
      break; // terminators changed, move to next MBB
    }
  }
  return Changed;
}

/// Remove basic blocks that have no predecessors (dead code).
/// Skip the entry block.
bool V6ClangBranchOpt::removeDeadBlocks(MachineFunction &MF) {
  bool Changed = false;
  SmallVector<MachineBasicBlock *, 4> DeadBlocks;

  for (MachineBasicBlock &MBB : MF) {
    if (&MBB == &MF.front())
      continue; // Never remove entry block.
    if (MBB.pred_empty()) {
      DeadBlocks.push_back(&MBB);
    }
  }

  for (MachineBasicBlock *MBB : DeadBlocks) {
    // Remove successors to update CFG.
    while (!MBB->succ_empty())
      MBB->removeSuccessor(MBB->succ_begin());
    MBB->eraseFromParent();
    Changed = true;
  }

  return Changed;
}

bool V6ClangBranchOpt::runOnMachineFunction(MachineFunction &MF) {
  if (DisableBranchOpt)
    return false;

  bool Changed = false;
  Changed |= invertConditionalOverRET(MF);
  Changed |= foldZeroSelectReturn(MF);
  Changed |= threadJMPOnlyBlocks(MF);
  Changed |= invertConditionalBranch(MF);
  Changed |= foldConditionalCalls(MF);
  Changed |= removeRedundantJMP(MF);
  Changed |= foldConditionalReturns(MF);
  Changed |= removeDeadBlocks(MF);
  return Changed;
}

FunctionPass *llvm::createV6ClangBranchOptPass() {
  return new V6ClangBranchOpt();
}
