//===-- V6ClangXchgOpt.cpp - Replace MOV pairs with XCHG --------------------===//
//
// Part of the V6CLANG backend for LLVM.
//
// Post-RA peephole: Detect sequences of MOVs that transfer DE↔HL and replace
// them with the much cheaper XCHG (4cc vs 16cc for two MOVs).
//
// Patterns detected:
//   MOV D, H; MOV E, L  → XCHG  (HL → DE, but also swaps DE → HL)
//   MOV H, D; MOV L, E  → XCHG  (DE → HL, but also swaps HL → DE)
//   MOV D, H; MOV E, L; MOV H, X; MOV L, Y → Only first pair to XCHG
//     if DE was dead before the sequence.
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/Support/CommandLine.h"

using namespace llvm;

#define DEBUG_TYPE "v6clang-xchg-opt"

static cl::opt<bool> DisableXchgOpt(
    "v6clang-disable-xchg-opt",
    cl::desc("Disable V6CLANG DE<->HL XCHG optimization"),
    cl::init(false), cl::Hidden);

namespace {

class V6ClangXchgOpt : public MachineFunctionPass {
public:
  static char ID;
  V6ClangXchgOpt() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG XCHG Optimization";
  }

  bool runOnMachineFunction(MachineFunction &MF) override;

private:
  bool tryXchg(MachineBasicBlock &MBB, MachineBasicBlock::iterator I);
};

} // end anonymous namespace

char V6ClangXchgOpt::ID = 0;

/// Check if MI is MOV rd, rs where rd and rs are the specified registers.
static bool isMovReg(const MachineInstr &MI, unsigned Dst, unsigned Src) {
  return MI.getOpcode() == V6Clang::MOVrr &&
         MI.getOperand(0).getReg() == Dst &&
         MI.getOperand(1).getReg() == Src;
}

/// Check if a physical register (or any alias) has a verifier-visible defined
/// value at iterator I in the given MBB. Backward scan from I toward block
/// start: the most recent event wins. An explicit def makes Reg readable; a
/// killed use or regmask clobber makes a later read invalid unless annotated
/// undef. If no event is seen, fall back to live-in status.
///
/// This is about MIR legality of XCHG's implicit reads, not about whether the
/// old value is semantically observable after the optimized sequence.
static bool isRegLiveBefore(MachineBasicBlock &MBB,
                            MachineBasicBlock::iterator I,
                            unsigned Reg,
                            const TargetRegisterInfo *TRI) {
  while (I != MBB.begin()) {
    --I;
    bool FoundDef = false, FoundClobber = false, FoundKilledUse = false;
    for (const MachineOperand &MO : I->operands()) {
      if (MO.isReg() && MO.isDef() && MO.getReg().isPhysical() &&
          TRI->regsOverlap(MO.getReg(), Reg))
        FoundDef = true;
      else if (MO.isReg() && MO.isUse() && MO.isKill() &&
               MO.getReg().isPhysical() && TRI->regsOverlap(MO.getReg(), Reg))
        FoundKilledUse = true;
      else if (MO.isRegMask() && MO.clobbersPhysReg(Reg))
        FoundClobber = true;
    }
    // Explicit def wins over regmask clobber within the same instruction.
    if (FoundDef)
      return true;
    if (FoundKilledUse)
      return false;
    if (FoundClobber)
      return false;
  }
  for (MCRegAliasIterator AI(Reg, TRI, /*IncludeSelf=*/true); AI.isValid();
       ++AI) {
    if (MBB.isLiveIn(*AI))
      return true;
  }
  return false;
}

/// Mark the implicit-use operand of XCHG for `Reg` as `undef` when it
/// wasn't proven live before the swap. This is a static annotation only —
/// it tells the MIR verifier we knowingly read a possibly-undefined value
/// that goes into a register proved dead after the swap. Codegen output
/// is unchanged.
static void markUndefIfNotLive(MachineInstr *XchgMI, MachineBasicBlock &MBB,
                               unsigned Reg, const TargetRegisterInfo *TRI) {
  // Scan up to (but not including) XCHG itself — its own implicit-def of Reg
  // must not be counted as a live definition of Reg before the swap.
  if (isRegLiveBefore(MBB, XchgMI->getIterator(), Reg, TRI))
    return;
  if (MachineOperand *MO = XchgMI->findRegisterUseOperand(Reg, /*isKill=*/false))
    MO->setIsUndef(true);
}

/// Check if a physical register is dead (not read) after iterator I.
/// Returns true if no instruction between I (exclusive) and the end of the
/// block reads Reg before an overlapping redef, and no successor has Reg as a
/// live-in.
///
/// For pair registers this answers whether the old pair value is dead. It is
/// not a general proof that both halves can be clobbered independently.
static bool isRegDeadAfter(MachineBasicBlock &MBB,
                           MachineBasicBlock::iterator I,
                           unsigned Reg,
                           const TargetRegisterInfo *TRI) {
  for (auto MI = std::next(I); MI != MBB.end(); ++MI) {
    bool usesReg = false, defsReg = false;
    for (const MachineOperand &MO : MI->operands()) {
      if (!MO.isReg() || !TRI->regsOverlap(MO.getReg(), Reg))
        continue;
      if (MO.isUse() && !MO.isUndef())
        usesReg = true;
      if (MO.isDef())
        defsReg = true;
    }
    if (usesReg)
      return false; // Read before redefined → live
    if (defsReg)
      return true;  // Redefined before read → dead
  }
  // Reached end of block: check if any successor needs Reg.
  for (MachineBasicBlock *Succ : MBB.successors()) {
    for (MCRegAliasIterator AI(Reg, TRI, /*IncludeSelf=*/true); AI.isValid();
         ++AI) {
      if (Succ->isLiveIn(*AI))
        return false;
    }
  }
  return true;
}

bool V6ClangXchgOpt::tryXchg(MachineBasicBlock &MBB,
                           MachineBasicBlock::iterator I) {
  MachineInstr &First = *I;
  auto Next = std::next(I);
  if (Next == MBB.end())
    return false;
  MachineInstr &Second = *Next;

  const TargetInstrInfo &TII = *MBB.getParent()->getSubtarget().getInstrInfo();
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();

  // XCHG swaps DE↔HL. Both pairs must be live (defined) before the swap.
  // If the "other" pair isn't live, XCHG would read an undefined register.

  // O33: dropped isRegLiveBefore() — if HL/DE is dead after, the swap's
  // side-effect into the other pair is harmless even when undefined.
  // Pattern 1: MOV D, H; MOV E, L → XCHG  (copies HL→DE, but also DE→HL)
  if (isMovReg(First, V6Clang::D, V6Clang::H) && isMovReg(Second, V6Clang::E, V6Clang::L)) {
    if (!isRegDeadAfter(MBB, Next, V6Clang::HL, TRI))
      return false; // HL is live after → XCHG would corrupt it
    MachineInstr *XchgMI =
        BuildMI(MBB, First, First.getDebugLoc(), TII.get(V6Clang::XCHG));
    // DE is the "other" pair: its value is unobserved post-swap (HL is dead).
    // If DE wasn't defined before, annotate the implicit use as undef so
    // -verify-machineinstrs is satisfied.
    markUndefIfNotLive(XchgMI, MBB, V6Clang::DE, TRI);
    First.eraseFromParent();
    Second.eraseFromParent();
    return true;
  }

  // Pattern 2: MOV H, D; MOV L, E → XCHG  (copies DE→HL, but also HL→DE)
  if (isMovReg(First, V6Clang::H, V6Clang::D) && isMovReg(Second, V6Clang::L, V6Clang::E)) {
    if (!isRegDeadAfter(MBB, Next, V6Clang::DE, TRI))
      return false; // DE is live after → XCHG would corrupt it
    MachineInstr *XchgMI =
        BuildMI(MBB, First, First.getDebugLoc(), TII.get(V6Clang::XCHG));
    markUndefIfNotLive(XchgMI, MBB, V6Clang::HL, TRI);
    First.eraseFromParent();
    Second.eraseFromParent();
    return true;
  }

  // Pattern 3: MOV E, L; MOV D, H → XCHG (reversed order, same as pattern 1)
  if (isMovReg(First, V6Clang::E, V6Clang::L) && isMovReg(Second, V6Clang::D, V6Clang::H)) {
    if (!isRegDeadAfter(MBB, Next, V6Clang::HL, TRI))
      return false; // HL is live after → XCHG would corrupt it
    MachineInstr *XchgMI =
        BuildMI(MBB, First, First.getDebugLoc(), TII.get(V6Clang::XCHG));
    markUndefIfNotLive(XchgMI, MBB, V6Clang::DE, TRI);
    First.eraseFromParent();
    Second.eraseFromParent();
    return true;
  }

  // Pattern 4: MOV L, E; MOV H, D → XCHG (reversed order, same as pattern 2)
  if (isMovReg(First, V6Clang::L, V6Clang::E) && isMovReg(Second, V6Clang::H, V6Clang::D)) {
    if (!isRegDeadAfter(MBB, Next, V6Clang::DE, TRI))
      return false; // DE is live after → XCHG would corrupt it
    MachineInstr *XchgMI =
        BuildMI(MBB, First, First.getDebugLoc(), TII.get(V6Clang::XCHG));
    markUndefIfNotLive(XchgMI, MBB, V6Clang::HL, TRI);
    First.eraseFromParent();
    Second.eraseFromParent();
    return true;
  }

  return false;
}

bool V6ClangXchgOpt::runOnMachineFunction(MachineFunction &MF) {
  if (DisableXchgOpt)
    return false;

  bool Changed = false;

  for (MachineBasicBlock &MBB : MF) {
    for (auto I = MBB.begin(), E = MBB.end(); I != E; ) {
      if (tryXchg(MBB, I)) {
        // tryXchg erased two instructions and inserted XCHG before them.
        // Iterator I is now invalid. Restart from beginning of block
        // (safe since XCHG can't form another pattern).
        I = MBB.begin();
        Changed = true;
      } else {
        ++I;
      }
    }

    // Cancel adjacent XCHG pairs that tryXchg may have created by placing
    // a new XCHG next to an existing one.  XCHG; XCHG = no-op (O44).
    for (auto I = MBB.begin(), E = MBB.end(); I != E; ) {
      if (I->getOpcode() != V6Clang::XCHG) {
        ++I;
        continue;
      }
      auto J = std::next(I);
      while (J != E && J->isDebugInstr())
        ++J;
      if (J != E && J->getOpcode() == V6Clang::XCHG) {
        MBB.erase(J);
        I = MBB.erase(I);
        Changed = true;
        continue;
      }
      ++I;
    }
  }

  return Changed;
}

FunctionPass *llvm::createV6ClangXchgOptPass() {
  return new V6ClangXchgOpt();
}
