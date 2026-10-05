//===-- V6ClangPeephole.cpp - V6CLANG Peephole Optimizations ---------------------===//
//
// Part of the V6CLANG backend for LLVM.
//
// Post-RA peephole pass with pattern-based local optimizations:
//
// 1. Redundant MOV elimination: MOV A, X; MOV A, X → remove second.
//    Also MOV A, X; <no flags/A write>; MOV X, A → remove second MOV X, A
//    if X was not modified.
//
// 2. Redundant self-MOV elimination: MOV X, X → remove.
//
// 3. Strength reduction: SHL i8 by 1 expanded to ADD A, A (4cc vs shift
//    sequence). This pattern should already be handled by ISel, but catch
//    any post-RA instances.
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "llvm/CodeGen/LivePhysRegs.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/Support/CommandLine.h"

using namespace llvm;

#define DEBUG_TYPE "v6clang-peephole"

static cl::opt<bool> DisablePeephole(
    "v6clang-disable-peephole",
    cl::desc("Disable V6CLANG peephole optimizations"),
    cl::init(false), cl::Hidden);

static cl::opt<bool> DisableShldLhldFold(
    "v6clang-disable-shld-lhld-fold",
    cl::desc("Disable SHLD/LHLD to PUSH/POP folding (O43)"),
    cl::init(false), cl::Hidden);

static cl::opt<bool> DisableMviAluFold(
    "v6clang-disable-mvi-alu-fold",
    cl::desc("Disable MVI R,NN + ALU R -> ALU-immediate fold (O79)"),
    cl::init(false), cl::Hidden);

static cl::opt<bool> DisablePopPushElim(
    "v6clang-disable-pop-push-elim",
    cl::desc("Disable POP/PUSH pair elimination (O83)"),
    cl::init(false), cl::Hidden);

static cl::opt<bool> DisableInxDcxSpillFold(
    "v6clang-disable-inx-dcx-spill-fold",
    cl::desc("Disable INX/DCX-through-spill round-trip fold (O84)"),
    cl::init(false), cl::Hidden);

static cl::opt<bool> DisablePairCopyRoundTrip(
    "v6clang-disable-pair-copy-roundtrip",
    cl::desc("Disable pair-copy round-trip elimination (O86)"),
    cl::init(false), cl::Hidden);

/// True if MI is an O61 patched-immediate site: it carries a
/// pre-instr `.LLo61_N:` label (referenced by SHLD/STA spills) and/or
/// its imm operand is flagged MO_PATCH_IMM.  Erasing such an MI loses
/// the label and orphans every spill that points at `Sym+1`, so
/// peepholes that rewrite or remove MI must skip these.
static bool isO61PatchedImm(const MachineInstr &MI) {
  if (MI.getPreInstrSymbol())
    return true;
  for (const MachineOperand &MO : MI.operands())
    if (MO.getTargetFlags() != 0)
      return true;
  return false;
}

static bool isDebugAllocaHome(const MachineInstr &MI) {
  if (!MI.getParent()->getParent()->getMMI().hasDebugInfo())
    return false;
  for (const MachineOperand &MO : MI.operands())
    if (MO.isGlobal() && MO.getGlobal()->getName().starts_with("__v6clang_a."))
      return true;
  return false;
}

namespace {

class V6ClangPeephole : public MachineFunctionPass {
public:
  static char ID;
  V6ClangPeephole() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Peephole Optimizations";
  }

  bool runOnMachineFunction(MachineFunction &MF) override;

private:
  bool eliminateSelfMov(MachineBasicBlock &MBB);
  bool eliminateTailCall(MachineBasicBlock &MBB);
  bool foldCounterBranch(MachineBasicBlock &MBB);
  bool foldXraCmpZeroTest(MachineBasicBlock &MBB);
  bool cancelAdjacentXchg(MachineBasicBlock &MBB);
  bool foldXchgDad(MachineBasicBlock &MBB);
  bool foldXchgSwapRedundancy(MachineBasicBlock &MBB);
  bool foldShldLhldToPushPop(MachineBasicBlock &MBB);
  bool foldMovAluM(MachineBasicBlock &MBB);
  bool foldIncDecMviM(MachineBasicBlock &MBB);
  bool foldMviZeroToXraA(MachineBasicBlock &MBB);
  bool foldMviAluImm(MachineBasicBlock &MBB);
  bool eliminateDeadMVI(MachineBasicBlock &MBB);
  bool eliminateDeadMov(MachineBasicBlock &MBB);
  bool collapseMovChain(MachineBasicBlock &MBB);
  bool eliminateDeadPopPush(MachineBasicBlock &MBB);
  bool foldInxDcxSpillRoundTrip(MachineBasicBlock &MBB);
  bool foldPairCopyRoundTrip(MachineBasicBlock &MBB);
};

} // end anonymous namespace

char V6ClangPeephole::ID = 0;

/// Remove MOV X, X instructions (no-op copies to self).
bool V6ClangPeephole::eliminateSelfMov(MachineBasicBlock &MBB) {
  bool Changed = false;
  for (MachineInstr &MI : llvm::make_early_inc_range(MBB)) {
    if (MI.getOpcode() != V6Clang::MOVrr)
      continue;
    if (MI.getOperand(0).getReg() == MI.getOperand(1).getReg()) {
      MI.eraseFromParent();
      Changed = true;
    }
  }
  return Changed;
}

/// Return true if MBB contains only a single RET (plus optional debug instrs).
static bool isRetOnlyBlock(const MachineBasicBlock &MBB) {
  for (const MachineInstr &MI : MBB) {
    if (MI.isDebugInstr())
      continue;
    if (MI.getOpcode() == V6Clang::RET)
      return true; // RET found — any debug instrs after it are fine.
    return false;  // Non-debug, non-RET instruction → not RET-only.
  }
  return false; // Empty block.
}

/// Replace CALL target; RET → V6CLANG_TAILJMP target (tail call elimination).
///
/// Pattern 1 (O14): CALL and RET in the same block.
/// Pattern 2 (O23): CALL is last instruction, sole successor is RET-only.
bool V6ClangPeephole::eliminateTailCall(MachineBasicBlock &MBB) {
  if (MBB.empty())
    return false;

  // Find the last non-debug instruction.
  auto LastIt = MBB.getLastNonDebugInstr();
  if (LastIt == MBB.end())
    return false;

  // --- Pattern 1: CALL; RET in the same block (O14) ---
  if (MBB.size() >= 2 && LastIt->getOpcode() == V6Clang::RET) {
    auto CallIt = std::prev(LastIt);
    while (CallIt != MBB.begin() && CallIt->isDebugInstr())
      CallIt = std::prev(CallIt);

    if (CallIt->getOpcode() == V6Clang::CALL) {
      const TargetInstrInfo &TII =
          *MBB.getParent()->getSubtarget().getInstrInfo();
      BuildMI(MBB, CallIt, CallIt->getDebugLoc(),
              TII.get(V6Clang::V6CLANG_TAILJMP))
          .add(CallIt->getOperand(0));

      LastIt->eraseFromParent();
      CallIt->eraseFromParent();
      return true;
    }
  }

  // --- Pattern 2: CALL at end of block, sole successor is RET-only (O23) ---
  if (LastIt->getOpcode() == V6Clang::CALL && MBB.succ_size() == 1) {
    MachineBasicBlock *Succ = *MBB.succ_begin();
    if (isRetOnlyBlock(*Succ)) {
      const TargetInstrInfo &TII =
          *MBB.getParent()->getSubtarget().getInstrInfo();
      BuildMI(MBB, LastIt, LastIt->getDebugLoc(),
              TII.get(V6Clang::V6CLANG_TAILJMP))
          .add(LastIt->getOperand(0));

      LastIt->eraseFromParent();
      MBB.removeSuccessor(Succ);
      return true;
    }
  }

  return false;
}

/// Check if a physical register is dead (not read) after iterator I.
/// Returns true if no instruction between I (exclusive) and the end of the
/// block reads Reg before an overlapping redef, and no successor has Reg as a
/// live-in.
///
/// Pair-register caveat: a def of one half kills the old pair value, but does
/// not prove the other half is safe to clobber. Whole-pair preservation checks
/// need explicit half-wise reasoning.
static bool isRegDeadAfter(MachineBasicBlock &MBB,
                           MachineBasicBlock::iterator I,
                           unsigned Reg,
                           const TargetRegisterInfo *TRI) {
  for (auto MI = std::next(I); MI != MBB.end(); ++MI) {
    bool usesReg = false, defsReg = false;
    for (const MachineOperand &MO : MI->operands()) {
      if (!MO.isReg() || !TRI->regsOverlap(MO.getReg(), Reg))
        continue;
      if (MO.isUse() && !MO.isUndef()) {
        // "implicit killed $pairReg" can appear when a sibling sub-register
        // is explicitly last-used in the same instruction (e.g. "MOV A, L"
        // gets "implicit killed $hl" because L dies, taking HL with it).
        // That is a liveness bookkeeping artifact — H is not being read.
        // Detect: if MO is an implicit kill of a strict super-register of Reg,
        // AND there exists an explicit USE of a sub-register of that pair that
        // does NOT overlap Reg, then MO is not a genuine read of Reg.
        bool IsArtifact = false;
        if (MO.isImplicit() && MO.isKill() &&
            TRI->isSubRegister(MO.getReg(), Reg)) {
          for (const MachineOperand &Sub : MI->operands()) {
            if (!Sub.isReg() || Sub.isImplicit() || !Sub.isUse())
              continue;
            if (TRI->isSubRegister(MO.getReg(), Sub.getReg()) &&
                !TRI->regsOverlap(Sub.getReg(), Reg)) {
              IsArtifact = true;
              break;
            }
          }
        }
        if (!IsArtifact)
          usesReg = true;
      }
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

/// Return true if MI is a redundant zero-test: ORA A or CPI 0.
static bool isRedundantZeroTest(const MachineInstr &MI) {
  // ORA A: ORAr with all three operands (dst, lhs, src) = A.
  if (MI.getOpcode() == V6Clang::ORAr &&
      MI.getOperand(0).getReg() == V6Clang::A &&
      MI.getOperand(1).getReg() == V6Clang::A &&
      MI.getOperand(2).getReg() == V6Clang::A)
    return true;
  // CPI 0: compare A with immediate 0.
  if (MI.getOpcode() == V6Clang::CPI &&
      MI.getOperand(1).isImm() && MI.getOperand(1).getImm() == 0)
    return true;
  return false;
}

/// Return true when Reg can be read at I without an undef annotation. This is
/// used before replacing MVI A,0 or MOV A,r with XRA A; XRA A's old A input is
/// irrelevant, but the MIR verifier still needs the uses marked undef if A is
/// not live here.
static bool isRegLiveBefore(MachineBasicBlock &MBB,
                            MachineBasicBlock::iterator I, Register Reg,
                            const TargetRegisterInfo *TRI) {
  while (I != MBB.begin()) {
    --I;
    bool FoundDef = false;
    bool FoundClobber = false;
    bool FoundKilledUse = false;
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

static void markRegUsesUndef(MachineInstr *MI, Register Reg) {
  for (MachineOperand &MO : MI->operands()) {
    if (MO.isReg() && MO.isUse() && MO.getReg() == Reg)
      MO.setIsUndef(true);
  }
}

static bool readsNonCarryFlags(const MachineInstr &MI) {
  switch (MI.getOpcode()) {
  case V6Clang::JZ:
  case V6Clang::JNZ:
  case V6Clang::JP:
  case V6Clang::JM:
  case V6Clang::JPE:
  case V6Clang::JPO:
    return true;
  default:
    return false;
  }
}

static bool definesFlags(const MachineInstr &MI,
                         const TargetRegisterInfo *TRI) {
  for (const MachineOperand &MO : MI.operands()) {
    if (MO.isReg() && MO.isDef() && MO.getReg().isPhysical() &&
        TRI->regsOverlap(MO.getReg(), V6Clang::FLAGS))
      return true;
  }
  return false;
}

static bool definesOnlyCarryFlag(const MachineInstr &MI) {
  switch (MI.getOpcode()) {
  case V6Clang::DAD:
  case V6Clang::V6CLANG_DAD:
  case V6Clang::V6CLANG_LEA_FI:
  case V6Clang::V6CLANG_LOAD8_FI:
  case V6Clang::V6CLANG_LOAD16_FI:
  case V6Clang::V6CLANG_STORE8_FI:
  case V6Clang::V6CLANG_STORE16_FI:
  case V6Clang::V6CLANG_SPILL8:
  case V6Clang::V6CLANG_RELOAD8:
  case V6Clang::V6CLANG_SPILL16:
  case V6Clang::V6CLANG_RELOAD16:
    return true;
  default:
    return false;
  }
}

static bool hasNonCarryFlagUseBeforeFullFlagDef(
    MachineBasicBlock &MBB, MachineBasicBlock::iterator I,
    const TargetRegisterInfo *TRI) {
  for (auto MI = std::next(I); MI != MBB.end(); ++MI) {
    if (readsNonCarryFlags(*MI))
      return true;
    if (definesFlags(*MI, TRI) && !definesOnlyCarryFlag(*MI))
      return false;
  }
  for (MachineBasicBlock *Succ : MBB.successors())
    if (Succ->isLiveIn(V6Clang::FLAGS))
      return true;
  return false;
}

/// Return true if MI is a DCR r or INR r instruction.
static bool isDcrOrInr(const MachineInstr &MI) {
  return MI.getOpcode() == V6Clang::DCRr || MI.getOpcode() == V6Clang::INRr;
}

/// Fold DCR/INR + redundant flag test + JNZ/JZ into DCR/INR + JNZ/JZ.
///
/// Pattern A: DCR A; ORA A; Jcc → DCR A; Jcc (remove ORA A)
/// Pattern B: DCR r; MOV A,r; ORA A; Jcc → DCR r; Jcc (remove MOV+ORA, A dead)
/// Pattern C: MOV A,r; DCR A; MOV r,A; ORA A; Jcc → DCR r; Jcc (A dead)
bool V6ClangPeephole::foldCounterBranch(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();
  const TargetInstrInfo &TII = *MBB.getParent()->getSubtarget().getInstrInfo();

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ++I) {
    MachineInstr &BrMI = *I;
    // Match JNZ or JZ.
    if (BrMI.getOpcode() != V6Clang::JNZ && BrMI.getOpcode() != V6Clang::JZ)
      continue;

    // We need at least 2 instructions before the branch for Pattern A.
    if (I == MBB.begin())
      continue;
    auto OraIt = std::prev(I);
    if (OraIt == MBB.begin())
      continue;

    // The instruction before the branch must be ORA A or CPI 0.
    if (!isRedundantZeroTest(*OraIt))
      continue;

    auto PreOraIt = std::prev(OraIt);

    // --- Try Pattern C first (5 instructions → 2) ---
    // MOV A,r; DCR/INR A; MOV r,A; ORA A; Jcc
    if (PreOraIt != MBB.begin()) {
      auto MovRaIt = PreOraIt;  // MOV r, A
      auto DcrAIt = std::prev(MovRaIt);
      if (DcrAIt != MBB.begin()) {
        auto MovArIt = std::prev(DcrAIt);  // MOV A, r

        if (MovRaIt->getOpcode() == V6Clang::MOVrr &&
            MovRaIt->getOperand(1).getReg() == V6Clang::A &&
            isDcrOrInr(*DcrAIt) &&
            DcrAIt->getOperand(0).getReg() == V6Clang::A &&
            MovArIt->getOpcode() == V6Clang::MOVrr &&
            MovArIt->getOperand(0).getReg() == V6Clang::A) {
          Register CounterReg = MovArIt->getOperand(1).getReg();
          Register StoreReg = MovRaIt->getOperand(0).getReg();
          // MOV A,r and MOV r,A must refer to the same register r.
          if (CounterReg == StoreReg && CounterReg != V6Clang::A &&
              isRegDeadAfter(MBB, I, V6Clang::A, TRI)) {
            // Replace 5 instructions with DCR/INR r + Jcc.
            unsigned NewOpc = (DcrAIt->getOpcode() == V6Clang::DCRr)
                                  ? V6Clang::DCRr : V6Clang::INRr;
            BuildMI(MBB, *MovArIt, MovArIt->getDebugLoc(),
                    TII.get(NewOpc), CounterReg)
                .addReg(CounterReg);
            // Remove MOV A,r; DCR A; MOV r,A; ORA A (keep Jcc).
            OraIt->eraseFromParent();
            MovRaIt->eraseFromParent();
            DcrAIt->eraseFromParent();
            MovArIt->eraseFromParent();
            Changed = true;
            continue;
          }
        }
      }
    }

    // --- Try Pattern B (4 instructions → 2) ---
    // DCR r; MOV A,r; ORA A; Jcc
    if (PreOraIt->getOpcode() == V6Clang::MOVrr &&
        PreOraIt->getOperand(0).getReg() == V6Clang::A) {
      Register SrcReg = PreOraIt->getOperand(1).getReg();
      if (SrcReg != V6Clang::A && PreOraIt != MBB.begin()) {
        auto DcrIt = std::prev(PreOraIt);
        if (isDcrOrInr(*DcrIt) &&
            DcrIt->getOperand(0).getReg() == SrcReg &&
            isRegDeadAfter(MBB, I, V6Clang::A, TRI)) {
          // Remove MOV A,r and ORA A — keep DCR r and Jcc.
          OraIt->eraseFromParent();
          PreOraIt->eraseFromParent();
          Changed = true;
          continue;
        }
      }
    }

    // --- Try Pattern A (3 instructions → 2) ---
    // DCR A; ORA A; Jcc
    if (isDcrOrInr(*PreOraIt) &&
        PreOraIt->getOperand(0).getReg() == V6Clang::A) {
      // Remove ORA A — DCR A already set Z.
      OraIt->eraseFromParent();
      Changed = true;
      continue;
    }
  }
  return Changed;
}

/// Replace MOV A,r; ORA A; Jcc with XRA A; CMP r; Jcc (O38).
///
/// The transform saves 4cc (8cc vs 12cc) and leaves A = 0, which enables
/// O13 (LoadImmCombine) to cascade-eliminate downstream MVI A, 0.
///
/// Safety: A changes from r to 0. Valid when:
///  - Condition 1: A is dead on the fallthrough path, OR
///  - Condition 2: the next instruction on fallthrough is MVI A, 0
///    (so A = 0 is already the expected value).
bool V6ClangPeephole::foldXraCmpZeroTest(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();
  const TargetInstrInfo &TII = *MBB.getParent()->getSubtarget().getInstrInfo();

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ++I) {
    MachineInstr &MovMI = *I;
    // Match MOV A, r (r != A).
    if (MovMI.getOpcode() != V6Clang::MOVrr ||
        MovMI.getOperand(0).getReg() != V6Clang::A)
      continue;
    Register SrcReg = MovMI.getOperand(1).getReg();
    if (SrcReg == V6Clang::A)
      continue;

    // Next must be ORA A or CPI 0.
    auto OraIt = std::next(I);
    if (OraIt == E)
      continue;
    if (!isRedundantZeroTest(*OraIt))
      continue;

    // Next must be JZ or JNZ.
    auto BrIt = std::next(OraIt);
    if (BrIt == E)
      continue;
    if (BrIt->getOpcode() != V6Clang::JZ && BrIt->getOpcode() != V6Clang::JNZ)
      continue;

    // Check safety: A must be dead or A=0 acceptable on fallthrough.
    bool Safe = isRegDeadAfter(MBB, BrIt, V6Clang::A, TRI);
    if (!Safe) {
      // Condition 2: first non-debug instruction in the fallthrough successor
      // is MVI A, 0. Since XRA A sets A=0, the value change is benign.
      MachineBasicBlock *FallThrough = nullptr;
      for (MachineBasicBlock *Succ : MBB.successors()) {
        if (MBB.isLayoutSuccessor(Succ)) {
          FallThrough = Succ;
          break;
        }
      }
      if (FallThrough) {
        auto FTIt = FallThrough->begin();
        while (FTIt != FallThrough->end() && FTIt->isDebugInstr())
          ++FTIt;
        if (FTIt != FallThrough->end() &&
            FTIt->getOpcode() == V6Clang::MVIr &&
            FTIt->getOperand(0).getReg() == V6Clang::A &&
            FTIt->getOperand(1).isImm() &&
            FTIt->getOperand(1).getImm() == 0)
          Safe = true;
      }
    }
    if (!Safe)
      continue;

    // Replace MOV A, r with XRA A.
    MachineInstr *XraMI =
        BuildMI(MBB, MovMI, MovMI.getDebugLoc(), TII.get(V6Clang::XRAr), V6Clang::A)
            .addReg(V6Clang::A)
            .addReg(V6Clang::A)
            .getInstr();
    if (!isRegLiveBefore(MBB, XraMI->getIterator(), V6Clang::A, TRI))
      markRegUsesUndef(XraMI, V6Clang::A);
    // Replace ORA A with CMP r.
    BuildMI(MBB, *OraIt, OraIt->getDebugLoc(), TII.get(V6Clang::CMPr))
        .addReg(V6Clang::A)
        .addReg(SrcReg);

    // Advance iterator past the branch before erasing MOV and ORA.
    I = BrIt;
    MovMI.eraseFromParent();
    OraIt->eraseFromParent();
    Changed = true;
  }
  return Changed;
}

/// Return true if MI reads or writes DE, HL, or any sub-register (D,E,H,L).
static bool touchesDEorHL(const MachineInstr &MI,
                          const TargetRegisterInfo *TRI) {
  for (const MachineOperand &MO : MI.operands()) {
    if (!MO.isReg())
      continue;
    Register Reg = MO.getReg();
    if (TRI->regsOverlap(Reg, V6Clang::DE) || TRI->regsOverlap(Reg, V6Clang::HL))
      return true;
  }
  return false;
}

/// Cancel XCHG pairs: XCHG; ...; XCHG → ... (remove both XCHGs).
/// Two XCHG instructions swap HL↔DE twice, which is a no-op.
/// Safe when all intervening instructions are DE/HL-agnostic (don't
/// read or write D, E, H, L, DE, or HL). Also handles the simple
/// adjacent case (no intervening instructions). Skips debug instrs.
bool V6ClangPeephole::cancelAdjacentXchg(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ) {
    if (I->getOpcode() != V6Clang::XCHG) {
      ++I;
      continue;
    }
    // Scan forward looking for a matching XCHG.
    auto J = std::next(I);
    bool CanCancel = true;
    while (J != E) {
      if (J->isDebugInstr()) {
        ++J;
        continue;
      }
      if (J->getOpcode() == V6Clang::XCHG)
        break; // Found matching XCHG.
      if (touchesDEorHL(*J, TRI)) {
        CanCancel = false;
        break; // Intervening instr uses DE/HL — can't cancel.
      }
      ++J;
    }
    if (CanCancel && J != E && J->getOpcode() == V6Clang::XCHG) {
      // XCHG pair found — delete both.
      MBB.erase(J);        // erase second XCHG
      I = MBB.erase(I);    // erase first XCHG, I now points to next
      Changed = true;
      continue;             // re-check from new I (may be another XCHG)
    }
    ++I;
  }
  return Changed;
}

/// Fold XCHG; DAD DE → DAD DE.
///
/// XCHG swaps HL↔DE, then DAD DE computes (old-DE) + (old-HL) → HL.
/// Without XCHG, DAD DE computes (old-HL) + (old-DE) → HL — same result
/// because addition is commutative.  However DE differs: with XCHG it
/// holds old-HL; without, old-DE.  Safe only when DE is dead after DAD.
bool V6ClangPeephole::foldXchgDad(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ++I) {
    if (I->getOpcode() != V6Clang::XCHG)
      continue;

    auto Next = std::next(I);
    if (Next == E || Next->getOpcode() != V6Clang::DAD)
      continue;

    // DAD operand must be DE.
    if (Next->getOperand(0).getReg() != V6Clang::DE)
      continue;

    // DE must be dead after DAD (DE value differs with/without XCHG).
    if (!isRegDeadAfter(MBB, Next, V6Clang::DE, TRI))
      continue;

    // Safe to remove the XCHG.
    I = MBB.erase(I);
    // I now points at DAD — continue loop from there.
    Changed = true;
  }
  return Changed;
}

/// Fold away redundant register saves around XCHG emitted when the register
/// allocator breaks a HL↔DE circular dependency:
///
///   (1) MOV r1, H        ; save H to scratch register r1
///   (2) MOV r2, L        ; save L to scratch register r2
///   (3) XCHG             ; HL ↔ DE  (now D=old_H, E=old_L)
///   (4) MOV D,  r1       ; D = r1 = old_H  ← redundant: XCHG already did this
///   (5) MOV E,  r2       ; E = r2 = old_L  ← redundant: XCHG already did this
///
/// → simplify to: XCHG
///
/// r1 and r2 must not be H, L, D, or E (they must survive XCHG unchanged).
/// The transformation is safe only when r1 and r2 are dead after instruction (5).
bool V6ClangPeephole::foldXchgSwapRedundancy(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ) {
    // (1) MOV r1, H
    if (I->getOpcode() != V6Clang::MOVrr ||
        I->getOperand(1).getReg() != V6Clang::H) {
      ++I;
      continue;
    }
    Register R1 = I->getOperand(0).getReg();
    // r1 must not be one of the registers touched by XCHG.
    if (R1 == V6Clang::H || R1 == V6Clang::L || R1 == V6Clang::D || R1 == V6Clang::E) {
      ++I;
      continue;
    }

    // (2) MOV r2, L
    auto I2 = std::next(I);
    if (I2 == E || I2->getOpcode() != V6Clang::MOVrr ||
        I2->getOperand(1).getReg() != V6Clang::L) {
      ++I;
      continue;
    }
    Register R2 = I2->getOperand(0).getReg();
    if (R2 == V6Clang::H || R2 == V6Clang::L || R2 == V6Clang::D || R2 == V6Clang::E ||
        R2 == R1) {
      ++I;
      continue;
    }

    // (3) XCHG
    auto I3 = std::next(I2);
    if (I3 == E || I3->getOpcode() != V6Clang::XCHG) {
      ++I;
      continue;
    }

    // (4) MOV D, r1
    auto I4 = std::next(I3);
    if (I4 == E || I4->getOpcode() != V6Clang::MOVrr ||
        I4->getOperand(0).getReg() != V6Clang::D ||
        I4->getOperand(1).getReg() != R1) {
      ++I;
      continue;
    }

    // (5) MOV E, r2
    auto I5 = std::next(I4);
    if (I5 == E || I5->getOpcode() != V6Clang::MOVrr ||
        I5->getOperand(0).getReg() != V6Clang::E ||
        I5->getOperand(1).getReg() != R2) {
      ++I;
      continue;
    }

    // r1 and r2 must be dead after instruction (5): if they're read later the
    // definitions in (1)/(2) would be needed by that later code.
    if (!isRegDeadAfter(MBB, I5, R1, TRI) ||
        !isRegDeadAfter(MBB, I5, R2, TRI)) {
      ++I;
      continue;
    }

    // Pattern matched. Erase (1), (2), (4), (5); keep (3) XCHG.
    I5->eraseFromParent();
    I4->eraseFromParent();
    I2->eraseFromParent();
    I = MBB.erase(I); // erase (1) MOV r1,H; I now points at (3) XCHG
    Changed = true;
    // Do NOT advance I here: leave it at XCHG so cancelAdjacentXchg can
    // fold it if another XCHG immediately follows.
  }
  return Changed;
}

/// Return true if two MachineOperands represent the same address
/// (both GlobalAddress with same GV and offset, or both identical immediates).
static bool isSameAddress(const MachineOperand &A, const MachineOperand &B) {
  if (A.getType() != B.getType())
    return false;
  if (A.isGlobal())
    return A.getGlobal() == B.getGlobal() && A.getOffset() == B.getOffset();
  if (A.isImm())
    return A.getImm() == B.getImm();
  return false;
}

/// Check if any LHLD of the same address is reachable from AfterD
/// without passing through a covering SHLD.  ShldC is the SHLD being
/// folded — it doesn't count as a covering store (it will be removed).
static bool isUncoveredLhldReachable(
    MachineBasicBlock &MBB,
    MachineBasicBlock::iterator AfterD,
    MachineBasicBlock::iterator ShldC,
    const MachineOperand &Addr) {

  // 1. Scan remainder of current BB after the folded LHLD.
  for (auto I = AfterD, E = MBB.end(); I != E; ++I) {
    if (I->getOpcode() == V6Clang::SHLD && isSameAddress(Addr, I->getOperand(1)))
      return false;  // another SHLD covers all forward paths
    if (I->getOpcode() == V6Clang::LHLD && isSameAddress(Addr, I->getOperand(1)))
      return true;   // uncovered reader in same BB
  }

  // 2. BFS through successor BBs (including self-loops via back-edges).
  //    Do NOT pre-insert MBB — it must be revisited when reached via a
  //    back-edge so the self-loop scan (begin → ShldC) runs.
  SmallPtrSet<MachineBasicBlock *, 8> Visited;
  SmallVector<MachineBasicBlock *, 8> Worklist;

  for (auto *Succ : MBB.successors())
    if (Visited.insert(Succ).second)
      Worklist.push_back(Succ);

  while (!Worklist.empty()) {
    MachineBasicBlock *Cur = Worklist.pop_back_val();
    bool IsSelf = (Cur == &MBB);

    // Self-loop: scan from BB top to ShldC (C is being folded, not a cover).
    auto ScanEnd = IsSelf ? MachineBasicBlock::iterator(ShldC) : Cur->end();

    for (auto I = Cur->begin(); I != ScanEnd; ++I) {
      if (I->getOpcode() == V6Clang::SHLD && isSameAddress(Addr, I->getOperand(1)))
        goto next_bb;  // covered — don't follow successors
      if (I->getOpcode() == V6Clang::LHLD && isSameAddress(Addr, I->getOperand(1)))
        return true;   // uncovered reader
    }

    // No kill found — propagate to successors.
    for (auto *Succ : Cur->successors())
      if (Visited.insert(Succ).second)
        Worklist.push_back(Succ);
    next_bb:;
  }

  return false;  // no uncovered reader reachable
}

/// Replace SHLD addr / LHLD addr pairs with PUSH HL / POP HL (O43).
///
/// When a static-stack spill (SHLD) and its matching reload (LHLD) are in
/// the same basic block with SP delta == 0 at the LHLD, PUSH HL + POP HL
/// is cheaper: 28cc/2B vs 40cc/6B.
///
/// SP delta tracking: PUSH decrements by 2, POP increments by 2.
/// CALL/Ccc/RST are net-zero (callee restores SP via RET).
/// Any other SP modifier (SPHL, LXI SP, INX SP, DCX SP) causes abort.
bool V6ClangPeephole::foldShldLhldToPushPop(MachineBasicBlock &MBB) {
  if (DisableShldLhldFold)
    return false;
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();
  const TargetInstrInfo &TII = *MBB.getParent()->getSubtarget().getInstrInfo();

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ++I) {
    if (I->getOpcode() != V6Clang::SHLD)
      continue;
    if (isDebugAllocaHome(*I))
      continue;

    const MachineOperand &ShldAddr = I->getOperand(1);
    int SPDelta = 0;
    bool Abort = false;
    MachineBasicBlock::iterator MatchIt;
    bool Found = false;

    for (auto J = std::next(I); J != E; ++J) {
      if (J->isDebugInstr())
        continue;

      // Check for matching LHLD.
      if (J->getOpcode() == V6Clang::LHLD &&
          isSameAddress(ShldAddr, J->getOperand(1))) {
        if (isDebugAllocaHome(*J)) {
          Abort = true;
          break;
        }
        if (SPDelta == 0) {
          MatchIt = J;
          Found = true;
        } else {
          Abort = true;
        }
        break;
      }

      // Abort on re-spill to same address.
      if (J->getOpcode() == V6Clang::SHLD &&
          isSameAddress(ShldAddr, J->getOperand(1))) {
        Abort = true;
        break;
      }

      // SP delta tracking.
      if (J->modifiesRegister(V6Clang::SP, TRI)) {
        unsigned Opc = J->getOpcode();
        if (Opc == V6Clang::PUSH) {
          SPDelta -= 2;
        } else if (Opc == V6Clang::POP) {
          SPDelta += 2;
          if (SPDelta > 0) { Abort = true; break; }
        } else if (J->isCall()) {
          // CALL/Ccc/RST: net-zero SP effect, skip.
        } else {
          // Unknown SP modifier (SPHL, LXI SP, INX SP, DCX SP, etc.)
          Abort = true;
          break;
        }
      }
    }

    if (Abort || !Found)
      continue;

    // Safety: check that no uncovered LHLD reads this address via any
    // forward path (including loop back-edges and cross-BB paths).
    if (isUncoveredLhldReachable(MBB, std::next(MatchIt), I, ShldAddr))
      continue;

    // Replace SHLD with PUSH HL.
    BuildMI(MBB, *I, I->getDebugLoc(), TII.get(V6Clang::PUSH))
        .addReg(V6Clang::HL);
    // Replace LHLD with POP HL.
    BuildMI(MBB, *MatchIt, MatchIt->getDebugLoc(), TII.get(V6Clang::POP), V6Clang::HL);

    MatchIt->eraseFromParent();
    I = MBB.erase(I);
    Changed = true;
    --I; // compensate for ++I in loop header
  }
  return Changed;
}

/// Map a register-form ALU opcode (V6Clang::ADDr/.../CMPr) to its memory-form
/// counterpart (V6Clang::ADDM/.../CMPM). Returns 0 if Opc is not foldable.
static unsigned aluRegToMemOpcode(unsigned Opc) {
  switch (Opc) {
  case V6Clang::ADDr: return V6Clang::ADDM;
  case V6Clang::ADCr: return V6Clang::ADCM;
  case V6Clang::SUBr: return V6Clang::SUBM;
  case V6Clang::SBBr: return V6Clang::SBBM;
  case V6Clang::ANAr: return V6Clang::ANAM;
  case V6Clang::XRAr: return V6Clang::XRAM;
  case V6Clang::ORAr: return V6Clang::ORAM;
  case V6Clang::CMPr: return V6Clang::CMPM;
  default:        return 0;
  }
}

/// Stage 2 helper for O65: walk MIs in [Begin, End) and report whether
/// every MI is safe to cross while preserving the value of `R` AND the
/// A / FLAGS / [HL] observer chain.
///
/// Each crossed MI must:
///   * not read or write R (or any aliasing reg),
///   * not read or write any reg overlapping HL,
///   * not write A (a write to A would clobber the eventual OP M's lhs),
///   * not write FLAGS (downstream Jcc must observe the OP M's flags),
///   * not be a call / branch / return / barrier,
///   * not be mayStore (a store could alias [HL]).
static bool scanBetweenSafe(MachineBasicBlock::iterator Begin,
                            MachineBasicBlock::iterator End, Register R,
                            const TargetRegisterInfo *TRI) {
  for (auto K = Begin; K != End; ++K) {
    if (K->isDebugInstr())
      continue;
    if (K->isCall() || K->isBranch() || K->isReturn() || K->isBarrier())
      return false;
    if (K->mayStore())
      return false;
    for (const MachineOperand &MO : K->operands()) {
      if (!MO.isReg() || !MO.getReg())
        continue;
      Register Reg = MO.getReg();
      bool TouchesR  = TRI->regsOverlap(Reg, R);
      bool TouchesHL = TRI->regsOverlap(Reg, V6Clang::HL);
      bool TouchesA  = TRI->regsOverlap(Reg, V6Clang::A);
      bool TouchesF  = TRI->regsOverlap(Reg, V6Clang::FLAGS);
      if (!TouchesR && !TouchesHL && !TouchesA && !TouchesF)
        continue;
      if (TouchesR || TouchesHL)
        return false; // any read or write of R or HL is unsafe
      if (MO.isDef() && (TouchesA || TouchesF))
        return false; // crossing a write to A or FLAGS is unsafe
      // Pure read of A or FLAGS is fine.
    }
  }
  return true;
}

/// Fold MOV r, M; ...; OP r -> ...; OP M when r is dead after OP (O65,
/// stages 1+2).
///
/// Stage 1 -- strict adjacency (debug MIs skipped).
/// Stage 2 -- arbitrary independent MIs between the MOV and the OP, as
///            long as scanBetweenSafe() approves every crossed MI. The
///            forward window is bounded by kMaxScanWindow to avoid
///            quadratic behavior in pathologically large blocks.
bool V6ClangPeephole::foldMovAluM(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();
  const TargetInstrInfo &TII =
      *MBB.getParent()->getSubtarget().getInstrInfo();

  static constexpr unsigned kMaxScanWindow = 16;

  for (auto I = MBB.begin(), E = MBB.end(); I != E;) {
    if (I->getOpcode() != V6Clang::MOVrM) {
      ++I;
      continue;
    }

    Register MovDst = I->getOperand(0).getReg();
    if (MovDst == V6Clang::A) {
      ++I;
      continue;
    }

    // Walk forward up to kMaxScanWindow non-debug MIs looking for the
    // matching OPr. Stop early on any unsafe MI.
    auto J = std::next(I);
    unsigned Steps = 0;
    bool Failed = false;
    while (J != E && Steps < kMaxScanWindow) {
      if (J->isDebugInstr()) {
        ++J;
        continue;
      }
      // Is this the candidate ALU op?
      unsigned MemOpc = aluRegToMemOpcode(J->getOpcode());
      if (MemOpc != 0) {
        bool IsCMP = (J->getOpcode() == V6Clang::CMPr);
        unsigned RhsIdx = IsCMP ? 1 : 2;
        if (J->getOperand(RhsIdx).getReg() == MovDst)
          break; // found
      }
      // Otherwise it must be safe to cross.
      if (!scanBetweenSafe(J, std::next(J), MovDst, TRI)) {
        Failed = true;
        break;
      }
      ++J;
      ++Steps;
    }

    if (Failed || J == E || Steps >= kMaxScanWindow) {
      ++I;
      continue;
    }

    unsigned MemOpc = aluRegToMemOpcode(J->getOpcode());
    if (MemOpc == 0) {
      ++I;
      continue;
    }

    bool IsCMP = (J->getOpcode() == V6Clang::CMPr);

    // r must be dead after the ALU op.
    if (!isRegDeadAfter(MBB, J, MovDst, TRI)) {
      ++I;
      continue;
    }

    // Build OP M before J. For non-CMP: outs Acc:$dst tied to ins Acc:$lhs.
    //                      For CMP:    no outs.
    MachineInstrBuilder MIB =
        BuildMI(MBB, *J, J->getDebugLoc(), TII.get(MemOpc));
    if (!IsCMP)
      MIB.addReg(V6Clang::A, RegState::Define);
    MIB.addReg(V6Clang::A);

    // Erase the ALU op and the original MOV.
    auto Next = std::next(J);
    J->eraseFromParent();
    auto INext = std::next(I);
    I->eraseFromParent();
    // Resume scanning from where the MOV used to be: any MI that was
    // between MOV and OP is now adjacent to the new OP M.
    I = (INext == Next) ? Next : INext;
    Changed = true;
  }
  return Changed;
}

/// Find the next non-debug iterator at or after K (does not advance past End).
static MachineBasicBlock::iterator
nextNonDebug(MachineBasicBlock::iterator K, MachineBasicBlock::iterator End) {
  while (K != End && K->isDebugInstr())
    ++K;
  return K;
}

/// Stage 3 fold for O65: collapse MOV A, M; INR/DCR A; MOV M, A into
/// INR M / DCR M, and MVI A, imm; MOV M, A into MVI M, imm. In both
/// cases A must be dead after the MOV M, A.
///
/// Adjacency: debug MIs are skipped between the head, middle, and tail
/// instructions of each shape.
bool V6ClangPeephole::foldIncDecMviM(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();
  const TargetInstrInfo &TII =
      *MBB.getParent()->getSubtarget().getInstrInfo();

  for (auto I = MBB.begin(), E = MBB.end(); I != E;) {
    unsigned Opc = I->getOpcode();

    // ---- Shape A: MOV A, M ; INR/DCR A ; MOV M, A -> INR/DCR M ----
    if (Opc == V6Clang::MOVrM && I->getOperand(0).getReg() == V6Clang::A) {
      auto Mid = nextNonDebug(std::next(I), E);
      if (Mid != E &&
          (Mid->getOpcode() == V6Clang::INRr || Mid->getOpcode() == V6Clang::DCRr) &&
          Mid->getOperand(0).getReg() == V6Clang::A) {
        auto Tail = nextNonDebug(std::next(Mid), E);
        if (Tail != E && Tail->getOpcode() == V6Clang::MOVMr &&
            Tail->getOperand(0).getReg() == V6Clang::A &&
            isRegDeadAfter(MBB, Tail, V6Clang::A, TRI)) {
          unsigned MemOpc =
              (Mid->getOpcode() == V6Clang::INRr) ? V6Clang::INRM : V6Clang::DCRM;
          BuildMI(MBB, *Tail, Tail->getDebugLoc(), TII.get(MemOpc));
          auto Next = std::next(Tail);
          Tail->eraseFromParent();
          Mid->eraseFromParent();
          I->eraseFromParent();
          I = Next;
          Changed = true;
          continue;
        }
      }
    }

    // ---- Shape B: MVI A, imm ; MOV M, A -> MVI M, imm ----
    // O61 patched MVIs are still foldable: MVI M, imm has its own
    // imm byte at the same `Sym+1` offset (both encodings are
    // [opcode, imm] with the imm at byte offset 1), so we forward
    // the pre-instr `.LLo61_N:` label and the operand's target flags
    // (e.g. MO_PATCH_IMM) onto the new MVI M.
    if (Opc == V6Clang::MVIr && I->getOperand(0).getReg() == V6Clang::A) {
      auto Tail = nextNonDebug(std::next(I), E);
      if (Tail != E && Tail->getOpcode() == V6Clang::MOVMr &&
          Tail->getOperand(0).getReg() == V6Clang::A &&
          isRegDeadAfter(MBB, Tail, V6Clang::A, TRI)) {
        const MachineOperand &ImmOp = I->getOperand(1);
        MachineFunction &MF = *MBB.getParent();
        MachineInstr *NewMI =
            BuildMI(MBB, *Tail, Tail->getDebugLoc(), TII.get(V6Clang::MVIM))
                .add(ImmOp)
                .getInstr();
        if (MCSymbol *PreSym = I->getPreInstrSymbol())
          NewMI->setPreInstrSymbol(MF, PreSym);
        auto Next = std::next(Tail);
        Tail->eraseFromParent();
        I->eraseFromParent();
        I = Next;
        Changed = true;
        continue;
      }
    }

    ++I;
  }
  return Changed;
}

/// O55 Pattern 2: replace `MVI A, 0` with `XRA A` when FLAGS is dead
/// after the instruction. Saves 1 byte and 4 cycles per instance.
///
/// `XRA A` zeroes A *and* clobbers FLAGS (Z=1, S=0, P=1, CY=0, AC=0),
/// while `MVI A, 0` leaves FLAGS untouched. The rewrite is therefore
/// only legal when no live FLAGS use follows.
bool V6ClangPeephole::foldMviZeroToXraA(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();
  const TargetInstrInfo &TII =
      *MBB.getParent()->getSubtarget().getInstrInfo();

  for (MachineInstr &MI : llvm::make_early_inc_range(MBB)) {
    if (MI.getOpcode() != V6Clang::MVIr)
      continue;
    if (MI.getOperand(0).getReg() != V6Clang::A)
      continue;
    if (!MI.getOperand(1).isImm() || MI.getOperand(1).getImm() != 0)
      continue;
    // Skip O61 patched MVIs: imm 0 is a placeholder, real value is
    // written to MI's imm byte at runtime by an STA spill, and
    // erasing the MI loses the .LLo61_N label.
    if (isO61PatchedImm(MI))
      continue;
    if (hasNonCarryFlagUseBeforeFullFlagDef(MBB, MI.getIterator(), TRI))
      continue;
    if (!isRegDeadAfter(MBB, MI.getIterator(), V6Clang::FLAGS, TRI))
      continue;

    MachineInstr *XraMI = BuildMI(MBB, MI, MI.getDebugLoc(), TII.get(V6Clang::XRAr),
                                  V6Clang::A)
                              .addReg(V6Clang::A)
                              .addReg(V6Clang::A)
                              .getInstr();
    if (!isRegLiveBefore(MBB, XraMI->getIterator(), V6Clang::A, TRI))
      markRegUsesUndef(XraMI, V6Clang::A);
    MI.eraseFromParent();
    Changed = true;
  }
  return Changed;
}

/// Map register-form ALU opcode -> immediate-form opcode.
/// Both forms set FLAGS identically (same ALU function bits in the
/// 8080 encoding).  CPI has no def of A; the others tie dst = lhs = A.
static unsigned aluRegToImmOpc(unsigned Opc) {
  switch (Opc) {
  case V6Clang::ADDr: return V6Clang::ADI;
  case V6Clang::ADCr: return V6Clang::ACI;
  case V6Clang::SUBr: return V6Clang::SUI;
  case V6Clang::SBBr: return V6Clang::SBI;
  case V6Clang::ANAr: return V6Clang::ANI;
  case V6Clang::XRAr: return V6Clang::XRI;
  case V6Clang::ORAr: return V6Clang::ORI;
  case V6Clang::CMPr: return V6Clang::CPI;
  default:        return 0;
  }
}

/// Return the GR8-source-operand index of a register-form ALU op.
/// For writers (ADDr/.../ORAr): operands are (dst=A, lhs=A, src=GR8).
/// For CMPr: operands are (lhs=A, src=GR8) with no def.
static unsigned aluRegSrcOpIdx(unsigned Opc) {
  return (Opc == V6Clang::CMPr) ? 1u : 2u;
}

/// O79: fold `MVI R, NN; ... ; ALU R` into `... ; ALU-immediate NN`
/// when no instruction strictly between the MVI and the ALU op
/// reads or writes R (or its 16-bit alias), and R is dead after the
/// ALU op.  Saves 1B / 4cc per fire and frees R for register
/// allocation across the gap.
///
/// The fold preserves O61 patched-immediate metadata: the
/// pre-instruction MCSymbol (`.LLo61_N` label, used by spill
/// `STA <Sym+1>`) and the imm operand's MO_PATCH_IMM target flag
/// are transferred to the new ALU-immediate instruction.  Both
/// `MVI r,imm8` and `ADI/SUI/.../CPI` are 2-byte instructions
/// with the imm at offset +1, so `<Sym+1>` keeps targeting the
/// correct byte.
bool V6ClangPeephole::foldMviAluImm(MachineBasicBlock &MBB) {
  if (DisableMviAluFold)
    return false;

  bool Changed = false;
  MachineFunction &MF = *MBB.getParent();
  const TargetRegisterInfo *TRI = MF.getSubtarget().getRegisterInfo();
  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ) {
    MachineInstr &MVI = *I;
    auto NextI = std::next(I);

    if (MVI.getOpcode() != V6Clang::MVIr) { I = NextI; continue; }
    Register R = MVI.getOperand(0).getReg();
    if (R == V6Clang::A) { I = NextI; continue; }
    // The fold copies the imm operand wholesale; it must be a real
    // immediate (target-flagged O61 placeholders are still .isImm()).
    if (!MVI.getOperand(1).isImm()) { I = NextI; continue; }

    // Forward-scan for the ALU consumer.
    MachineBasicBlock::iterator J = NextI;
    bool Blocked = false;
    for (; J != E; ++J) {
      MachineInstr &Cand = *J;
      if (Cand.isDebugInstr()) continue;
      // Hard barriers.
      if (Cand.isCall() || Cand.isInlineAsm() ||
          Cand.hasUnmodeledSideEffects()) {
        Blocked = true;
        break;
      }

      // Recognise the ALU-on-R consumer.
      unsigned ImmOpc = aluRegToImmOpc(Cand.getOpcode());
      if (ImmOpc) {
        unsigned SrcIdx = aluRegSrcOpIdx(Cand.getOpcode());
        const MachineOperand &SrcMO = Cand.getOperand(SrcIdx);
        if (SrcMO.isReg() && SrcMO.getReg() == R) {
          // Match — don't run the read/write barrier on this MI;
          // its read of R is the success case.
          break;
        }
      }

      // Any operand reading or writing R (or an aliasing 16-bit
      // pair) blocks; regmasks on calls handled above.
      for (const MachineOperand &MO : Cand.operands()) {
        if (MO.isRegMask() && MO.clobbersPhysReg(R)) {
          Blocked = true;
          break;
        }
        if (!MO.isReg() || !MO.getReg())
          continue;
        if (TRI->regsOverlap(MO.getReg(), R)) {
          Blocked = true;
          break;
        }
      }
      if (Blocked)
        break;
    }
    if (Blocked || J == E) { I = NextI; continue; }

    // R must be dead after the ALU consumer (its only purpose was
    // to deliver the materialized immediate).
    if (!isRegDeadAfter(MBB, J, R, TRI)) { I = NextI; continue; }

    MachineInstr &Cons = *J;
    unsigned ImmOpc = aluRegToImmOpc(Cons.getOpcode());

    // Build the immediate-form ALU op at the consumer's position.
    DebugLoc DL = Cons.getDebugLoc();
    MachineInstrBuilder MIB = BuildMI(MBB, Cons, DL, TII.get(ImmOpc));
    if (ImmOpc != V6Clang::CPI) {
      // ADI/ACI/.../ORI: (outs Acc:$dst)(ins Acc:$lhs, imm8:$imm)
      MIB.addReg(V6Clang::A, RegState::Define).addReg(V6Clang::A);
    } else {
      // CPI: (outs)(ins Acc:$lhs, imm8:$imm)
      MIB.addReg(V6Clang::A);
    }
    // Copy the imm operand wholesale to preserve target flags
    // (notably V6ClangII::MO_PATCH_IMM for O61 patched landing pads).
    MIB.add(MVI.getOperand(1));

    // Transfer pre-instruction symbol (e.g. O61 `.LLo61_N` label).
    if (MCSymbol *PreSym = MVI.getPreInstrSymbol())
      MIB.getInstr()->setPreInstrSymbol(MF, PreSym);

    // Erase the consumer first (frees J), then erase MVI.
    Cons.eraseFromParent();
    I = MBB.erase(MVI);
    Changed = true;
  }
  return Changed;
}

/// O82 Pattern A: erase MVI r, imm when r is provably dead after the
/// instruction.  MVI r, imm writes only r and does not set FLAGS, so
/// erasing it when r is dead is always safe.
/// Guards:
///   - MVI A is skipped: handled more precisely by foldMviZeroToXraA /
///     foldMviAluImm.
///   - O61 patched MVIs carry a pre-instruction label referenced by
///     runtime STA spills and must never be erased.
bool V6ClangPeephole::eliminateDeadMVI(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();

  for (MachineInstr &MI : llvm::make_early_inc_range(MBB)) {
    if (MI.getOpcode() != V6Clang::MVIr)
      continue;
    Register Dst = MI.getOperand(0).getReg();
    if (Dst == V6Clang::A) // handled by foldMviZeroToXraA / foldMviAluImm
      continue;
    if (isO61PatchedImm(MI))
      continue;
    if (!isRegDeadAfter(MBB, MI.getIterator(), Dst, TRI))
      continue;
    MI.eraseFromParent();
    Changed = true;
  }
  return Changed;
}

/// O82 follow-up: erase MOV dst, src when dst is provably dead after the
/// instruction. MOV writes only dst and does not set FLAGS, so erasing it is
/// safe when dst is dead. This catches leftover dead high-byte writes such as
/// `MOV H, A` on i8 return paths where only A is live into RET.
bool V6ClangPeephole::eliminateDeadMov(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();

  for (MachineInstr &MI : llvm::make_early_inc_range(MBB)) {
    if (MI.getOpcode() != V6Clang::MOVrr)
      continue;
    Register Dst = MI.getOperand(0).getReg();
    Register Src = MI.getOperand(1).getReg();
    if (Dst == Src)
      continue;
    if (!isRegDeadAfter(MBB, MI.getIterator(), Dst, TRI))
      continue;
    MI.eraseFromParent();
    Changed = true;
  }
  return Changed;
}

/// O82 Pattern B: collapse MOV X, Y ; [safe instrs] ; MOV Z, X into
/// MOV Z, Y when X is a dead intermediate (nothing reads X between the
/// two MOVs and X is dead after the consumer MOV).
/// After rewriting the consumer, if X is also dead at the producer the
/// producer is erased too.
/// The scan window is bounded to kChainWindow to keep compile-time O(N).
bool V6ClangPeephole::collapseMovChain(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();

  static constexpr unsigned kChainWindow = 8;

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ++I) {
    MachineInstr &ProducerMI = *I;
    if (ProducerMI.getOpcode() != V6Clang::MOVrr)
      continue;

    Register X = ProducerMI.getOperand(0).getReg(); // dead intermediate
    Register Y = ProducerMI.getOperand(1).getReg(); // original source

    if (X == Y) // self-copy — eliminateSelfMov handles these
      continue;

    // Walk forward looking for a consumer MOV Z, X.
    unsigned Steps = 0;
    // YClobbered: Y was written by some intermediate (non-consumer)
    // instruction.  When set the classic "rewrite consumer" transform is
    // invalid (Y's value at the consumer position differs from the value
    // read by the producer), but the "rewrite producer" variant may still
    // apply (see below).
    bool YClobbered = false;
    auto J = std::next(I);
    for (; J != E && Steps < kChainWindow; ++J) {
      if (J->isDebugInstr())
        continue;
      ++Steps;

      bool IsConsumer = J->getOpcode() == V6Clang::MOVrr &&
                        TRI->regsOverlap(J->getOperand(1).getReg(), X);

      bool ReadsX = false, ClobbersX = false, ClobbersY = false;
      for (const MachineOperand &MO : J->operands()) {
        // A call's register-mask operand clobbers every register not listed
        // as preserved.  These clobbers are NOT expressed as explicit reg
        // defs, so they must be checked here or a call between producer and
        // consumer would be wrongly treated as value-preserving.
        if (MO.isRegMask()) {
          if (MO.clobbersPhysReg(X))
            ClobbersX = true;
          if (MO.clobbersPhysReg(Y))
            ClobbersY = true;
          continue;
        }
        if (!MO.isReg() || !MO.getReg())
          continue;
        bool IsConsumerSrc =
            IsConsumer && MO.isUse() && &MO == &J->getOperand(1);
        bool IsConsumerDst =
            IsConsumer && MO.isDef() && &MO == &J->getOperand(0);
        if (TRI->regsOverlap(MO.getReg(), X)) {
          if (MO.isUse() && !MO.isUndef() && !IsConsumerSrc)
            ReadsX = true;
          if (MO.isDef())
            ClobbersX = true;
        }
        if (TRI->regsOverlap(MO.getReg(), Y) && MO.isDef() &&
            !(IsConsumerDst && TRI->regsOverlap(MO.getReg(), Y)))
          ClobbersY = true;
      }

      // Is J the consumer MOV Z, X (X used as source, dead after)?
      // Check this BEFORE the ReadsX bail-out: the consumer itself reads X
      // as its source operand, which would otherwise terminate the scan.
      if (IsConsumer) {
        if (ClobbersX)
          break;
        if (isRegDeadAfter(MBB, J, X, TRI)) {
          auto Resume = std::next(J);
          Register Z = J->getOperand(0).getReg();
          if (!YClobbered && TRI->regsOverlap(Z, Y)) {
            // Round-trip: MOV X, Y ; ... ; MOV Y, X (Y unmodified).
            // Y already holds the value, so both copies are redundant.
            ProducerMI.eraseFromParent();
            J->eraseFromParent();
            if (MBB.empty())
              return true;
            I = (Resume == MBB.begin()) ? Resume : std::prev(Resume);
            Changed = true;
            break;
          }

          if (!YClobbered) {
            // Classic transform: rewrite consumer MOV Z, X → MOV Z, Y,
            // then erase the producer (now a dead write).
            J->getOperand(1).setReg(Y);
            J->getOperand(1).setIsKill(false);
            auto Next = std::next(I);
            ProducerMI.eraseFromParent();
            I = std::prev(Next);
            Changed = true;
          } else {
            // Y was clobbered between producer and consumer, so we cannot
            // replace X with Y at the consumer's position.  Alternative:
            // rewrite the producer MOV X, Y → MOV Z, Y (read Y before it
            // gets clobbered) and erase the consumer.  Valid only when Z
            // is not read or written by any instruction strictly between
            // producer and consumer (otherwise we create a premature def
            // of Z that could be observed by those instructions).
            bool ZUsedBetween = false;
            for (auto K = std::next(I); K != J; ++K) {
              if (K->isDebugInstr())
                continue;
              for (const MachineOperand &MO : K->operands()) {
                // A call regmask that clobbers Z means moving Z's def to the
                // producer position would not survive the call — treat it as
                // a use so the producer-rewrite variant is rejected.
                if (MO.isRegMask()) {
                  if (MO.clobbersPhysReg(Z)) {
                    ZUsedBetween = true;
                    break;
                  }
                  continue;
                }
                if (!MO.isReg() || !MO.getReg())
                  continue;
                if (TRI->regsOverlap(MO.getReg(), Z)) {
                  ZUsedBetween = true;
                  break;
                }
              }
              if (ZUsedBetween)
                break;
            }
            if (!ZUsedBetween) {
              // Rewrite producer: MOV X, Y → MOV Z, Y; erase consumer.
              // I still points to the (now rewritten) producer; the outer
              // ++I will advance past it correctly.
              ProducerMI.getOperand(0).setReg(Z);
              J->eraseFromParent();
              Changed = true;
            }
          }
        }
        break;
      }

      // X is read by something other than a direct MOV Z, X — stop.
      if (ReadsX)
        break;

      // A clobber of X by a non-consumer terminates the scan regardless.
      // A clobber of Y is tracked (YClobbered) but does not terminate the
      // scan: the "rewrite-producer" variant can still apply.
      if (ClobbersX)
        break;
      if (ClobbersY)
        YClobbered = true;
    }
  }

  // O88: MVIr-producer variant.
  // Pattern: MVI X, Imm  ; [window, no read/clobber of X] ; MOV Z, X
  //          where X is dead after the MOV.
  // Transform: emit MVI Z, Imm before the MOV, then erase MOV and MVI X.
  for (auto I = MBB.begin(), E = MBB.end(); I != E; ++I) {
    MachineInstr &ProducerMI = *I;
    if (ProducerMI.getOpcode() != V6Clang::MVIr)
      continue;
    if (isO61PatchedImm(ProducerMI))
      continue;

    Register X   = ProducerMI.getOperand(0).getReg();
    int64_t  Imm = ProducerMI.getOperand(1).getImm();

    unsigned Steps = 0;
    for (auto J = std::next(I); J != E && Steps < kChainWindow; ++J) {
      if (J->isDebugInstr())
        continue;
      ++Steps;

      bool IsConsumer = J->getOpcode() == V6Clang::MOVrr &&
                        TRI->regsOverlap(J->getOperand(1).getReg(), X);

      bool ReadsX = false, ClobbersX = false;
      for (const MachineOperand &MO : J->operands()) {
        if (!MO.isReg() || !MO.getReg())
          continue;
        if (!TRI->regsOverlap(MO.getReg(), X))
          continue;
        // Don't count the consumer's own source operand as a foreign read.
        if (MO.isUse() && !MO.isUndef() &&
            !(IsConsumer && &MO == &J->getOperand(1)))
          ReadsX = true;
        if (MO.isDef())
          ClobbersX = true;
      }

      if (IsConsumer) {
        // Only fold when X is the sole consumer (dead after) and not
        // simultaneously redefined by this instruction.
        if (!ClobbersX && isRegDeadAfter(MBB, J, X, TRI)) {
          Register Z = J->getOperand(0).getReg();
          const TargetInstrInfo &TII =
              *MBB.getParent()->getSubtarget().getInstrInfo();
          BuildMI(MBB, J, J->getDebugLoc(), TII.get(V6Clang::MVIr), Z)
              .addImm(Imm);
          auto Next = std::next(I);
          J->eraseFromParent();
          ProducerMI.eraseFromParent();
          I = std::prev(Next);
          Changed = true;
        }
        break; // stop scan after first consumer regardless of fold
      }

      if (ReadsX || ClobbersX)
        break;
    }
  }

  return Changed;
}

/// O83: Eliminate POP rp / PUSH rp pairs where rp is not used between them
/// and is dead after the PUSH.  The pair performs a useless round-trip through
/// the stack; removing it saves 22 cycles and 2 bytes per occurrence.
///
/// Conditions checked:
///   1. Same register pair for POP and PUSH.
///   2. No instruction between them reads or writes rp (or any sub-register).
///   3. No stack-affecting instruction between them (PUSH, POP, XTHL, SPHL,
///      or any instruction that modifies SP).
///   4. rp is dead after the PUSH (isRegDeadAfter).  PSW is checked half-wise
///      because a later A def alone does not prove FLAGS dead.
static bool isStackAffecting(const MachineInstr &MI,
                             const TargetRegisterInfo *TRI) {
  unsigned Op = MI.getOpcode();
  if (Op == V6Clang::PUSH || Op == V6Clang::POP || Op == V6Clang::XTHL || Op == V6Clang::SPHL)
    return true;
  return MI.modifiesRegister(V6Clang::SP, TRI);
}

bool V6ClangPeephole::eliminateDeadPopPush(MachineBasicBlock &MBB) {
  if (DisablePopPushElim)
    return false;

  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();

  bool Changed = false;
  for (auto I = MBB.begin(), E = MBB.end(); I != E;) {
    if (I->getOpcode() != V6Clang::POP) {
      ++I;
      continue;
    }

    Register Rp = I->getOperand(0).getReg();

    // Scan forward from POP looking for a matching PUSH rp.
    bool CanElim = true;
    MachineBasicBlock::iterator PushIt = E;
    for (auto J = std::next(I); J != E; ++J) {
      if (J->isDebugInstr())
        continue;

      // Found a PUSH of the same register pair — candidate.
      if (J->getOpcode() == V6Clang::PUSH &&
          J->getOperand(0).getReg() == Rp) {
        PushIt = J;
        break;
      }

      // Any stack-affecting instruction (including PUSH/POP of other pairs)
      // invalidates the elimination.
      if (isStackAffecting(*J, TRI)) {
        CanElim = false;
        break;
      }

      // Any instruction that reads or writes rp (or its sub-registers)
      // invalidates the elimination.
      for (const MachineOperand &MO : J->operands()) {
        if (!MO.isReg() || !MO.getReg().isValid())
          continue;
        if (TRI->regsOverlap(MO.getReg(), Rp)) {
          CanElim = false;
          break;
        }
      }
      if (!CanElim)
        break;
    }

    if (!CanElim || PushIt == E) {
      ++I;
      continue;
    }

    // Verify rp is truly dead after the PUSH.  For PSW, check A and FLAGS
    // independently: isRegDeadAfter(PSW) can be fooled by a later A-only def.
    bool DeadAfterPush = TRI->regsOverlap(Rp, V6Clang::PSW)
                             ? isRegDeadAfter(MBB, PushIt, V6Clang::A, TRI) &&
                                   isRegDeadAfter(MBB, PushIt, V6Clang::FLAGS, TRI)
                             : isRegDeadAfter(MBB, PushIt, Rp, TRI);
    if (!DeadAfterPush) {
      ++I;
      continue;
    }

    // Eliminate the pair.  Erase PUSH first (it comes after POP).
    PushIt->eraseFromParent();
    I = MBB.erase(I); // advances I past the erased POP
    Changed = true;
  }
  return Changed;
}

bool V6ClangPeephole::foldInxDcxSpillRoundTrip(MachineBasicBlock &MBB) {
  if (DisableInxDcxSpillFold)
    return false;

  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();
  const TargetInstrInfo &TII =
      *MBB.getParent()->getSubtarget().getInstrInfo();

  // Advance past any debug instructions.
  auto nextReal = [](MachineBasicBlock::iterator It,
                     MachineBasicBlock::iterator End)
      -> MachineBasicBlock::iterator {
    ++It;
    while (It != End && It->isDebugInstr())
      ++It;
    return It;
  };

  bool Changed = false;
  for (auto I = MBB.begin(), E = MBB.end(); I != E;) {
    // Only MOVrr instructions start either pattern.
    if (I->getOpcode() != V6Clang::MOVrr || isO61PatchedImm(*I)) {
      ++I;
      continue;
    }
    Register Dst = I->getOperand(0).getReg();
    Register Src = I->getOperand(1).getReg();
    bool PatternMatched = false;

    // ── Pattern A: MOV rl,L / MOV rh,H / INX|DCX rp /
    //              MOV L,rl / MOV H,rh / SHLD addr ─────────────────────────
    // rl ∈ {C, E}; rh is the paired high byte; rp is BC or DE.
    // Replace with: INX H (or DCX H) / SHLD addr.  Requires rp dead after SHLD.
    do {
      if (Src != V6Clang::L) break;
      if (Dst != V6Clang::C && Dst != V6Clang::E) break;

      Register Rl = Dst;
      Register Rh = (Rl == V6Clang::C) ? V6Clang::B  : V6Clang::D;
      Register Rp = (Rl == V6Clang::C) ? V6Clang::BC : V6Clang::DE;

      auto I1 = nextReal(I,  E);  if (I1 == E) break;
      auto I2 = nextReal(I1, E);  if (I2 == E) break;
      auto I3 = nextReal(I2, E);  if (I3 == E) break;
      auto I4 = nextReal(I3, E);  if (I4 == E) break;
      auto I5 = nextReal(I4, E);  if (I5 == E) break;

      if (I1->getOpcode() != V6Clang::MOVrr)            break;
      if (I1->getOperand(0).getReg() != Rh)          break;
      if (I1->getOperand(1).getReg() != V6Clang::H)      break;
      if (isO61PatchedImm(*I1))                      break;

      bool IsInx;
      if (I2->getOpcode() == V6Clang::INX &&
          I2->getOperand(0).getReg() == Rp)
        IsInx = true;
      else if (I2->getOpcode() == V6Clang::DCX &&
               I2->getOperand(0).getReg() == Rp)
        IsInx = false;
      else
        break;
      if (isO61PatchedImm(*I2))                      break;

      if (I3->getOpcode() != V6Clang::MOVrr)            break;
      if (I3->getOperand(0).getReg() != V6Clang::L)     break;
      if (I3->getOperand(1).getReg() != Rl)          break;
      if (isO61PatchedImm(*I3))                      break;

      if (I4->getOpcode() != V6Clang::MOVrr)            break;
      if (I4->getOperand(0).getReg() != V6Clang::H)     break;
      if (I4->getOperand(1).getReg() != Rh)          break;
      if (isO61PatchedImm(*I4))                      break;

      if (I5->getOpcode() != V6Clang::SHLD)             break;
      if (!isRegDeadAfter(MBB, I5, Rp, TRI))        break;

      // Emit INX H or DCX H before SHLD.
      BuildMI(MBB, I5, I5->getDebugLoc(),
              TII.get(IsInx ? V6Clang::INX : V6Clang::DCX), V6Clang::HL)
          .addReg(V6Clang::HL);

      // Erase I4..I1 in reverse order, then erase I0.
      I4->eraseFromParent();
      I3->eraseFromParent();
      I2->eraseFromParent();
      I1->eraseFromParent();
      I = MBB.erase(I); // erases I0; I now points to the new INX/DCX H
      Changed = true;
      PatternMatched = true;
    } while (false);

    if (PatternMatched) continue;

    // ── Pattern B: MOV rh,H / MOV rl,L / MOV L,rl / MOV H,rh / SHLD addr ──
    // Round-trip copy with no increment — all four MOVs are no-ops.
    // rh ∈ {B, D}; rp is BC or DE.  Requires rp dead after SHLD.
    do {
      if (Src != V6Clang::H) break;
      if (Dst != V6Clang::B && Dst != V6Clang::D) break;

      Register Rh = Dst;
      Register Rl = (Rh == V6Clang::B) ? V6Clang::C : V6Clang::E;
      Register Rp = (Rh == V6Clang::B) ? V6Clang::BC : V6Clang::DE;

      auto J1 = nextReal(I,  E);  if (J1 == E) break;
      auto J2 = nextReal(J1, E);  if (J2 == E) break;
      auto J3 = nextReal(J2, E);  if (J3 == E) break;
      auto J4 = nextReal(J3, E);  if (J4 == E) break;

      if (J1->getOpcode() != V6Clang::MOVrr)            break;
      if (J1->getOperand(0).getReg() != Rl)          break;
      if (J1->getOperand(1).getReg() != V6Clang::L)     break;
      if (isO61PatchedImm(*J1))                      break;

      if (J2->getOpcode() != V6Clang::MOVrr)            break;
      if (J2->getOperand(0).getReg() != V6Clang::L)     break;
      if (J2->getOperand(1).getReg() != Rl)          break;
      if (isO61PatchedImm(*J2))                      break;

      if (J3->getOpcode() != V6Clang::MOVrr)            break;
      if (J3->getOperand(0).getReg() != V6Clang::H)     break;
      if (J3->getOperand(1).getReg() != Rh)          break;
      if (isO61PatchedImm(*J3))                      break;

      if (J4->getOpcode() != V6Clang::SHLD)             break;
      if (!isRegDeadAfter(MBB, J4, Rp, TRI))        break;

      // Erase J3..J1 in reverse order, then erase J0.
      J3->eraseFromParent();
      J2->eraseFromParent();
      J1->eraseFromParent();
      I = MBB.erase(I); // erases J0; I now points to SHLD
      Changed = true;
      PatternMatched = true;
    } while (false);

    if (!PatternMatched)
      ++I;
  }
  return Changed;
}

/// O86 — Pair-copy round-trip elimination.
///
/// Remove the reverse half of a register-pair copy that is immediately
/// followed by copying the pair back to its source:
///
///   MOV A1, B1    ; copy hi byte:  A1 = B1
///   MOV A2, B2    ; copy lo byte:  A2 = B2
///   MOV B1, A1    ; round-trip hi: B1 = A1 = old_B1  ← no-op
///   MOV B2, A2    ; round-trip lo: B2 = A2 = old_B2  ← no-op
///
/// The last two MOVs are genuine no-ops: B1 and B2 are unchanged since
/// steps (1) and (2), so restoring them from A1/A2 has no effect.
/// Handles all 8080 register-pair combinations (BC, DE, HL) and any
/// two distinct 8-bit registers acting as a pair.
///
/// This fires on the pattern emitted after O85 TypeNarrowing in the sieve
/// benchmark inner loop:
///   DAD B ; MOV B,H ; MOV C,L ; MOV H,B ; MOV L,C
/// → DAD B ; MOV B,H ; MOV C,L   (saves 10 cc / iteration)
bool V6ClangPeephole::foldPairCopyRoundTrip(MachineBasicBlock &MBB) {
  if (DisablePairCopyRoundTrip)
    return false;

  bool Changed = false;

  // Helper: advance past debug instructions.
  auto nextNonDbg = [](MachineBasicBlock::iterator It,
                       MachineBasicBlock::iterator End)
      -> MachineBasicBlock::iterator {
    ++It;
    while (It != End && It->isDebugInstr())
      ++It;
    return It;
  };

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ) {
    // (1): MOV A1, B1
    if (I->getOpcode() != V6Clang::MOVrr || isO61PatchedImm(*I)) {
      ++I;
      continue;
    }
    Register A1 = I->getOperand(0).getReg();
    Register B1 = I->getOperand(1).getReg();
    if (A1 == B1) { ++I; continue; } // self-copy; eliminateSelfMov handles it

    // (2): MOV A2, B2
    auto I2 = nextNonDbg(I, E);
    if (I2 == E || I2->getOpcode() != V6Clang::MOVrr || isO61PatchedImm(*I2)) {
      ++I;
      continue;
    }
    Register A2 = I2->getOperand(0).getReg();
    Register B2 = I2->getOperand(1).getReg();
    if (A2 == B2) { ++I; continue; }

    // (3): MOV B1, A1  (reverse of step 1)
    auto I3 = nextNonDbg(I2, E);
    if (I3 == E || I3->getOpcode() != V6Clang::MOVrr || isO61PatchedImm(*I3)) {
      ++I;
      continue;
    }
    if (I3->getOperand(0).getReg() != B1 ||
        I3->getOperand(1).getReg() != A1) {
      ++I;
      continue;
    }

    // (4): MOV B2, A2  (reverse of step 2)
    auto I4 = nextNonDbg(I3, E);
    if (I4 == E || I4->getOpcode() != V6Clang::MOVrr || isO61PatchedImm(*I4)) {
      ++I;
      continue;
    }
    if (I4->getOperand(0).getReg() != B2 ||
        I4->getOperand(1).getReg() != A2) {
      ++I;
      continue;
    }

    // All four participating registers must be distinct so that no step
    // clobbers a source needed by a later step in the sequence.
    if (A1 == A2 || A1 == B2 || A2 == B1 || B1 == B2) {
      ++I;
      continue;
    }

    // Instructions (3) and (4) are no-ops: B1 and B2 were not modified
    // between steps (1)/(2) and (3)/(4) (the four MOVs are consecutive,
    // so no intervening def of B1 or B2 can exist).  Remove them.
    I4->eraseFromParent();
    I3->eraseFromParent();
    I = std::next(I2); // continue from the instruction after (2)
    Changed = true;
  }
  return Changed;
}

bool V6ClangPeephole::runOnMachineFunction(MachineFunction &MF) {
  if (DisablePeephole)
    return false;

  // Several transforms here (e.g. eliminateDeadMov, collapseMovChain) decide
  // whether a register is dead at a block boundary by consulting successor
  // block live-in lists.  Earlier V6CLANG passes (spill-patched reload, spill
  // forwarding) keep values in physical registers across basic blocks without
  // updating the affected successors' live-in lists, leaving them stale — a
  // register that is genuinely live-out can be missing from a successor's
  // live-in set.  Trusting such stale lists makes a live MOV look dead and
  // erasing it miscompiles the program.  Recompute live-ins for the whole
  // function to a fixpoint (necessary because of loop back-edges) so the
  // deadness queries below are sound.
  {
    bool LiveInsChanged = true;
    while (LiveInsChanged) {
      LiveInsChanged = false;
      for (MachineBasicBlock &MBB : llvm::reverse(MF))
        LiveInsChanged |= recomputeLiveIns(MBB);
    }
  }

  bool Changed = false;
  for (MachineBasicBlock &MBB : MF) {
    Changed |= foldXchgSwapRedundancy(MBB); // reduce before cancelAdjacentXchg
    Changed |= cancelAdjacentXchg(MBB);
    Changed |= foldShldLhldToPushPop(MBB);
    Changed |= eliminateDeadPopPush(MBB);   // O83: must follow O43
    Changed |= foldInxDcxSpillRoundTrip(MBB); // O84: must follow O83
    Changed |= foldPairCopyRoundTrip(MBB);   // O86
    Changed |= foldMovAluM(MBB);
    Changed |= foldIncDecMviM(MBB);
    Changed |= eliminateSelfMov(MBB);
    Changed |= eliminateDeadMVI(MBB);   // O82 Pattern A
    Changed |= eliminateDeadMov(MBB);   // O82 follow-up dead MOV cleanup
    Changed |= collapseMovChain(MBB);   // O82 Pattern B
    Changed |= foldCounterBranch(MBB);
    Changed |= foldXraCmpZeroTest(MBB);
    Changed |= foldXchgDad(MBB);
    Changed |= eliminateTailCall(MBB);
    Changed |= foldMviAluImm(MBB);
    Changed |= foldMviZeroToXraA(MBB);
  }
  return Changed;
}

FunctionPass *llvm::createV6ClangPeepholePass() {
  return new V6ClangPeephole();
}
