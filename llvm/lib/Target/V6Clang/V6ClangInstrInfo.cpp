//===-- V6ClangInstrInfo.cpp - V6CLANG Instruction Information --------------------===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#include "V6ClangInstrInfo.h"
#include "V6Clang.h"
#include "V6ClangISelLowering.h"
#include "V6ClangInstrCost.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "llvm/CodeGen/MachineBasicBlock.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"

#define GET_INSTRINFO_CTOR_DTOR
#include "V6ClangGenInstrInfo.inc"

using namespace llvm;

// Returns true if, immediately before MI, the i8080 carry flag is provably
// already zero. Walks backward over instructions that do not modify FLAGS
// (MOV/MVI/LXI/INX/DCX/loads/stores/etc.) to the most recent FLAGS-defining
// instruction; CY is known reset only when that defining op is one of the
// 8080 logical ops (ANA/ANI/XRA/XRI/ORA/ORI), all of which clear CY as a
// side effect. Returns false on BB entry (live-in CY unknown) or any other
// FLAGS definer (ADD/SUB/CMP/INR-DCR/RAR/RLC/etc., or pseudos that may
// expand to such).
static bool priorClearsCarry(const MachineBasicBlock &MBB,
                              MachineBasicBlock::const_iterator MI) {
  while (MI != MBB.begin()) {
    --MI;
    if (MI->isDebugInstr())
      continue;
    if (!MI->definesRegister(V6Clang::FLAGS, /*TRI=*/nullptr))
      continue;
    switch (MI->getOpcode()) {
    case V6Clang::ANAr:
    case V6Clang::ANAM:
    case V6Clang::ANI:
    case V6Clang::XRAr:
    case V6Clang::XRAM:
    case V6Clang::XRI:
    case V6Clang::ORAr:
    case V6Clang::ORAM:
    case V6Clang::ORI:
      return true;
    default:
      return false;
    }
  }
  return false;
}

V6ClangInstrInfo::V6ClangInstrInfo()
    : V6ClangGenInstrInfo(V6Clang::ADJCALLSTACKDOWN, V6Clang::ADJCALLSTACKUP), RI() {}

void V6ClangInstrInfo::copyPhysReg(MachineBasicBlock &MBB,
                                MachineBasicBlock::iterator MI,
                                const DebugLoc &DL, MCRegister DestReg,
                                MCRegister SrcReg, bool KillSrc) const {
  // 8-bit register copy: MOV dest, src
  if (V6Clang::GR8RegClass.contains(DestReg) &&
      V6Clang::GR8RegClass.contains(SrcReg)) {
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr))
        .addReg(DestReg, RegState::Define)
        .addReg(SrcReg, getKillRegState(KillSrc));
    return;
  }

  // 16-bit pair copy: two MOV instructions (hi byte, then lo byte)
  if (V6Clang::GR16RegClass.contains(DestReg) &&
      V6Clang::GR16RegClass.contains(SrcReg)) {
    // DE↔HL with source killed: use XCHG (1B/4cc vs 2B/16cc).
    // Safe because source is dead — the reverse swap side-effect is harmless.
    if (KillSrc &&
        ((DestReg == V6Clang::HL && SrcReg == V6Clang::DE) ||
         (DestReg == V6Clang::DE && SrcReg == V6Clang::HL))) {
      BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
      return;
    }

    const TargetRegisterInfo *TRI = &RI;
    MCRegister DestHi = TRI->getSubReg(DestReg, V6Clang::sub_hi);
    MCRegister DestLo = TRI->getSubReg(DestReg, V6Clang::sub_lo);
    MCRegister SrcHi = TRI->getSubReg(SrcReg, V6Clang::sub_hi);
    MCRegister SrcLo = TRI->getSubReg(SrcReg, V6Clang::sub_lo);

    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr))
        .addReg(DestHi, RegState::Define)
        .addReg(SrcHi, getKillRegState(KillSrc));
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr))
        .addReg(DestLo, RegState::Define)
        .addReg(SrcLo, getKillRegState(KillSrc));
    return;
  }

  // SP → HL: LXI HL, 0 + DAD SP (no direct MOV path on 8080).
  if (DestReg == V6Clang::HL && SrcReg == V6Clang::SP) {
    BuildMI(MBB, MI, DL, get(V6Clang::LXI), V6Clang::HL).addImm(0);
    BuildMI(MBB, MI, DL, get(V6Clang::DAD))
        .addReg(V6Clang::SP);
    return;
  }

  // SP → DE / BC: route via HL but preserve the caller's HL.
  // Sequence: PUSH HL; LXI HL,2; DAD SP; MOV DestHi,H; MOV DestLo,L; POP HL.
  // The +2 in the LXI immediate cancels the SP -= 2 done by PUSH HL, so the
  // value materialised is the original SP value. Clobbers FLAGS (reserved).
  if (SrcReg == V6Clang::SP &&
      (DestReg == V6Clang::DE || DestReg == V6Clang::BC)) {
    const TargetRegisterInfo *TRI = &RI;
    MCRegister DestHi = TRI->getSubReg(DestReg, V6Clang::sub_hi);
    MCRegister DestLo = TRI->getSubReg(DestReg, V6Clang::sub_lo);
    BuildMI(MBB, MI, DL, get(V6Clang::PUSH)).addReg(V6Clang::HL);
    BuildMI(MBB, MI, DL, get(V6Clang::LXI), V6Clang::HL).addImm(2);
    BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(V6Clang::SP);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr))
        .addReg(DestHi, RegState::Define)
        .addReg(V6Clang::H);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr))
        .addReg(DestLo, RegState::Define)
        .addReg(V6Clang::L);
    BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::HL);
    return;
  }

  llvm_unreachable("Cannot copy between these register classes");
}

void V6ClangInstrInfo::storeRegToStackSlot(
    MachineBasicBlock &MBB, MachineBasicBlock::iterator MI, Register SrcReg,
    bool isKill, int FrameIndex, const TargetRegisterClass *RC,
    const TargetRegisterInfo *TRI, Register VReg) const {
  DebugLoc DL;
  if (MI != MBB.end())
    DL = MI->getDebugLoc();

  if (V6Clang::GR8RegClass.hasSubClassEq(RC) ||
      V6Clang::AccRegClass.hasSubClassEq(RC)) {
    BuildMI(MBB, MI, DL, get(V6Clang::V6CLANG_SPILL8))
        .addReg(SrcReg, getKillRegState(isKill))
        .addFrameIndex(FrameIndex);
    return;
  }

  if (V6Clang::GR16RegClass.hasSubClassEq(RC)) {
    BuildMI(MBB, MI, DL, get(V6Clang::V6CLANG_SPILL16))
        .addReg(SrcReg, getKillRegState(isKill))
        .addFrameIndex(FrameIndex);
    return;
  }

  llvm_unreachable("Cannot store this register to stack slot");
}

void V6ClangInstrInfo::loadRegFromStackSlot(
    MachineBasicBlock &MBB, MachineBasicBlock::iterator MI, Register DestReg,
    int FrameIndex, const TargetRegisterClass *RC,
    const TargetRegisterInfo *TRI, Register VReg) const {
  DebugLoc DL;
  if (MI != MBB.end())
    DL = MI->getDebugLoc();

  if (V6Clang::GR8RegClass.hasSubClassEq(RC) ||
      V6Clang::AccRegClass.hasSubClassEq(RC)) {
    BuildMI(MBB, MI, DL, get(V6Clang::V6CLANG_RELOAD8))
        .addReg(DestReg, RegState::Define)
        .addFrameIndex(FrameIndex);
    return;
  }

  if (V6Clang::GR16RegClass.hasSubClassEq(RC)) {
    BuildMI(MBB, MI, DL, get(V6Clang::V6CLANG_RELOAD16))
        .addReg(DestReg, RegState::Define)
        .addFrameIndex(FrameIndex);
    return;
  }

  llvm_unreachable("Cannot load this register from stack slot");
}

//===----------------------------------------------------------------------===//
// Branch Analysis
//===----------------------------------------------------------------------===//

/// Map a Jcc opcode to a V6ClangCC condition code.
static V6ClangCC::CondCode getCondFromJcc(unsigned Opc) {
  switch (Opc) {
  default: llvm_unreachable("Not a V6CLANG conditional branch");
  case V6Clang::JNZ: return V6ClangCC::COND_NZ;
  case V6Clang::JZ:  return V6ClangCC::COND_Z;
  case V6Clang::JNC: return V6ClangCC::COND_NC;
  case V6Clang::JC:  return V6ClangCC::COND_C;
  case V6Clang::JPO: return V6ClangCC::COND_PO;
  case V6Clang::JPE: return V6ClangCC::COND_PE;
  case V6Clang::JP:  return V6ClangCC::COND_P;
  case V6Clang::JM:  return V6ClangCC::COND_M;
  }
}

/// Map a V6ClangCC condition code to a Jcc opcode.
static unsigned getJccFromCond(V6ClangCC::CondCode CC) {
  switch (CC) {
  case V6ClangCC::COND_NZ: return V6Clang::JNZ;
  case V6ClangCC::COND_Z:  return V6Clang::JZ;
  case V6ClangCC::COND_NC: return V6Clang::JNC;
  case V6ClangCC::COND_C:  return V6Clang::JC;
  case V6ClangCC::COND_PO: return V6Clang::JPO;
  case V6ClangCC::COND_PE: return V6Clang::JPE;
  case V6ClangCC::COND_P:  return V6Clang::JP;
  case V6ClangCC::COND_M:  return V6Clang::JM;
  }
  llvm_unreachable("Unknown V6CLANG condition code");
}

/// Return the opposite condition code.
static V6ClangCC::CondCode getOppositeCond(V6ClangCC::CondCode CC) {
  switch (CC) {
  case V6ClangCC::COND_NZ: return V6ClangCC::COND_Z;
  case V6ClangCC::COND_Z:  return V6ClangCC::COND_NZ;
  case V6ClangCC::COND_NC: return V6ClangCC::COND_C;
  case V6ClangCC::COND_C:  return V6ClangCC::COND_NC;
  case V6ClangCC::COND_PO: return V6ClangCC::COND_PE;
  case V6ClangCC::COND_PE: return V6ClangCC::COND_PO;
  case V6ClangCC::COND_P:  return V6ClangCC::COND_M;
  case V6ClangCC::COND_M:  return V6ClangCC::COND_P;
  }
  llvm_unreachable("Unknown V6CLANG condition code");
}

static bool isCondBranch(unsigned Opc) {
  switch (Opc) {
  case V6Clang::JNZ: case V6Clang::JZ: case V6Clang::JNC: case V6Clang::JC:
  case V6Clang::JPO: case V6Clang::JPE: case V6Clang::JP: case V6Clang::JM:
    return true;
  default:
    return false;
  }
}

static bool isUncondBranch(unsigned Opc) {
  return Opc == V6Clang::JMP;
}

bool V6ClangInstrInfo::analyzeBranch(MachineBasicBlock &MBB,
                                  MachineBasicBlock *&TBB,
                                  MachineBasicBlock *&FBB,
                                  SmallVectorImpl<MachineOperand> &Cond,
                                  bool AllowModify) const {
  TBB = nullptr;
  FBB = nullptr;
  Cond.clear();

  // Scan backwards to find branch instructions.
  MachineBasicBlock::iterator I = MBB.end();
  MachineBasicBlock::iterator UnCondBrIter = MBB.end();

  while (I != MBB.begin()) {
    --I;

    if (I->isDebugInstr())
      continue;

    // Not a terminator — stop.
    if (!I->isTerminator())
      break;

    // Handle JMP (unconditional branch).
    if (isUncondBranch(I->getOpcode())) {
      UnCondBrIter = I;

      if (!TBB) {
        TBB = I->getOperand(0).getMBB();
        continue;
      }

      // Multiple unconditional branches — give up.
      return true;
    }

    // Handle Jcc (conditional branch).
    if (isCondBranch(I->getOpcode())) {
      V6ClangCC::CondCode CC = getCondFromJcc(I->getOpcode());

      if (!TBB) {
        // This is the last branch — conditional with fallthrough.
        TBB = I->getOperand(0).getMBB();
        Cond.push_back(MachineOperand::CreateImm(CC));
        continue;
      }

      // Already have a conditional branch — that means we have
      // Jcc + JMP: conditional to TBB, unconditional (fallthrough) to FBB.
      FBB = TBB;
      TBB = I->getOperand(0).getMBB();
      Cond.push_back(MachineOperand::CreateImm(CC));
      continue;
    }

    // Unknown terminator — give up.
    return true;
  }

  return false;
}

unsigned V6ClangInstrInfo::removeBranch(MachineBasicBlock &MBB,
                                     int *BytesRemoved) const {
  MachineBasicBlock::iterator I = MBB.end();
  unsigned Count = 0;

  while (I != MBB.begin()) {
    --I;
    if (I->isDebugInstr())
      continue;
    if (!isUncondBranch(I->getOpcode()) && !isCondBranch(I->getOpcode()))
      break;

    if (BytesRemoved)
      *BytesRemoved += 3; // All branches are 3 bytes
    I->eraseFromParent();
    I = MBB.end();
    ++Count;
  }

  return Count;
}

unsigned V6ClangInstrInfo::insertBranch(MachineBasicBlock &MBB,
                                     MachineBasicBlock *TBB,
                                     MachineBasicBlock *FBB,
                                     ArrayRef<MachineOperand> Cond,
                                     const DebugLoc &DL,
                                     int *BytesAdded) const {
  assert(TBB && "insertBranch requires a true block");

  if (Cond.empty()) {
    // Unconditional branch.
    assert(!FBB && "Unconditional branch with false block?");
    BuildMI(&MBB, DL, get(V6Clang::JMP)).addMBB(TBB);
    if (BytesAdded)
      *BytesAdded = 3;
    return 1;
  }

  // Conditional branch.
  assert(Cond.size() == 1 && "V6CLANG branch condition has single operand");
  auto CC = static_cast<V6ClangCC::CondCode>(Cond[0].getImm());
  unsigned JccOpc = getJccFromCond(CC);
  BuildMI(&MBB, DL, get(JccOpc)).addMBB(TBB);

  if (!FBB) {
    if (BytesAdded)
      *BytesAdded = 3;
    return 1;
  }

  // Conditional + unconditional: Jcc TBB; JMP FBB
  BuildMI(&MBB, DL, get(V6Clang::JMP)).addMBB(FBB);
  if (BytesAdded)
    *BytesAdded = 6;
  return 2;
}

bool V6ClangInstrInfo::reverseBranchCondition(
    SmallVectorImpl<MachineOperand> &Cond) const {
  assert(Cond.size() == 1 && "Invalid V6CLANG branch condition");
  auto CC = static_cast<V6ClangCC::CondCode>(Cond[0].getImm());
  Cond[0].setImm(getOppositeCond(CC));
  return false;
}

//===----------------------------------------------------------------------===//
// Helpers for INX/DCX peephole in expandPostRAPseudo
//===----------------------------------------------------------------------===//

/// Scan backward from \p From in \p MBB looking for an LXI that defines
/// \p Reg with no intervening redefinition. Returns the LXI MachineInstr
/// if found, nullptr otherwise. Stops at the beginning of the block or
/// after a reasonable scan window (16 instructions).
/// If no LXI is found in the current block and \p Reg is not modified before
/// \p From, also checks predecessor blocks for a defining LXI (handles loop
/// preheader constants like LXI BC, 1).
static MachineInstr *findDefiningLXI(MachineBasicBlock &MBB,
                                     MachineBasicBlock::iterator From,
                                     Register Reg,
                                     const TargetRegisterInfo *TRI) {
  const unsigned ScanLimit = 16;
  unsigned Count = 0;
  for (auto I = From; I != MBB.begin() && Count < ScanLimit; ++Count) {
    --I;
    MachineInstr &Cand = *I;

    // Found LXI defining Reg — return it.
    if (Cand.getOpcode() == V6Clang::LXI &&
        Cand.getOperand(0).getReg() == Reg) {
      // O61: a patched LXI carries an MCSymbol imm, not a concrete imm.
      // Its value is unknown at compile time, so we cannot fold from it.
      if (!Cand.getOperand(1).isImm())
        return nullptr;
      return &Cand;
    }

    // If something else defines Reg (including sub-registers), stop.
    if (Cand.modifiesRegister(Reg, TRI))
      return nullptr;
  }

  // Reg is not modified in the current BB before From.
  // Check predecessor blocks: if ALL predecessors have the same LXI value
  // (or don't modify Reg, inheriting from their own predecessors),
  // we can use it. For simplicity, require exactly one non-self predecessor
  // (covers the common loop-preheader case).
  MachineInstr *PredLXI = nullptr;
  for (MachineBasicBlock *Pred : MBB.predecessors()) {
    if (Pred == &MBB)
      continue; // Skip self-loop (back-edge) — Reg unchanged in current BB.
    // Scan backward from end of predecessor.
    unsigned PredCount = 0;
    bool Found = false;
    for (auto I = Pred->end(); I != Pred->begin() && PredCount < ScanLimit;
         ++PredCount) {
      --I;
      if (I->getOpcode() == V6Clang::LXI && I->getOperand(0).getReg() == Reg) {
        // O61: patched LXI has an opaque (MCSymbol) imm — can't fold.
        if (!I->getOperand(1).isImm())
          return nullptr;
        if (PredLXI && PredLXI->getOperand(1).getImm() !=
                            I->getOperand(1).getImm())
          return nullptr; // Conflicting values from different predecessors.
        PredLXI = &*I;
        Found = true;
        break;
      }
      if (I->modifiesRegister(Reg, TRI))
        return nullptr; // Reg modified by non-LXI in predecessor.
    }
    if (!Found && !PredLXI)
      return nullptr; // Predecessor doesn't define Reg via LXI.
  }
  return PredLXI;
}

/// Return true if the FLAGS register implicit-def on \p MI is dead.
static bool isFlagsDefDead(const MachineInstr &MI) {
  for (const MachineOperand &MO : MI.implicit_operands()) {
    if (MO.isReg() && MO.isDef() && MO.getReg() == V6Clang::FLAGS)
      return MO.isDead();
  }
  // No FLAGS implicit def found — conservatively safe (no flags produced).
  return true;
}

/// Return true if Reg has a verifier-visible defined value before iterator I.
/// Backward scan: the most recent event wins. An explicit def makes Reg
/// available; a killed use, regmask clobber, or lack of live-in means a later
/// instruction must not read Reg unless the read is marked undef.
///
/// This is used only for verifier annotations such as XCHG/XRA undef uses.
/// It does not prove the old value is semantically needed, only whether MIR may
/// legally model a read of that physical register at this point.
static bool isRegLiveBefore(MachineBasicBlock &MBB,
                            MachineBasicBlock::iterator I, Register Reg,
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

static void markXchgUseUndef(MachineInstr *XchgMI, Register Reg) {
  if (MachineOperand *MO = XchgMI->findRegisterUseOperand(Reg,
                                                          /*isKill=*/false))
    MO->setIsUndef(true);
}

/// Mark all explicit uses of Reg as undef. This is for zero/idempotent idioms
/// where the instruction encoding names Reg as an input, but the old value is
/// irrelevant to the result. Example: XRA A always produces zero, so an
/// undefined incoming A is legal once the MIR operands are annotated.
static void markRegUsesUndef(MachineInstr *MI, Register Reg) {
  for (MachineOperand &MO : MI->operands()) {
    if (MO.isReg() && MO.isUse() && MO.getReg() == Reg)
      MO.setIsUndef(true);
  }
}

/// Return true if \p Reg is not used by any instruction between \p After
/// (exclusive) and the next overlapping redefinition or end of \p MBB.
///
/// Important pair-register caveat: when Reg is HL/DE/BC this helper answers
/// "is the old overlapping value killed before the next overlapping read?" A
/// def of L therefore makes the old HL pair value dead even if H is later read
/// as an independent i8 value. Do not use this directly to decide whether it is
/// safe to clobber an entire pair while preserving unrelated live halves; check
/// the halves explicitly, as V6CLANG_DAD does for H and L below.
static bool isRegDeadAfter(MachineBasicBlock &MBB,
                           MachineBasicBlock::iterator After,
                           Register Reg,
                           const TargetRegisterInfo *TRI) {
  for (auto I = std::next(After), E = MBB.end(); I != E; ++I) {
    bool UsesReg = false;
    bool DefsReg = false;
    for (const MachineOperand &MO : I->operands()) {
      if (!MO.isReg() || !TRI->regsOverlap(MO.getReg(), Reg))
        continue;
      if (MO.isUse() && !MO.isUndef()) {
        bool IsArtifact = false;
        if (MO.isImplicit() && MO.isKill() &&
            TRI->isSubRegister(MO.getReg(), Reg)) {
          for (const MachineOperand &Sub : I->operands()) {
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
          UsesReg = true;
      }
      if (MO.isDef())
        DefsReg = true;
    }
    if (UsesReg)
      return false;
    if (DefsReg)
      return true; // Redefined before use — the LXI's value is dead.
  }
  // Reached end of block. Check if Reg is live-out.
  for (MachineBasicBlock *Succ : MBB.successors()) {
    for (MCRegAliasIterator AI(Reg, TRI, /*IncludeSelf=*/true); AI.isValid();
         ++AI) {
      if (Succ->isLiveIn(*AI))
        return false;
    }
  }
  return true;
}

/// Check if a physical register is dead after a given instruction.
/// Scans forward from MI (exclusive) to the end of MBB.
/// Returns true if no read before an overlapping redef, and Reg is not in any
/// successor live-in set.
///
/// Same caveat as isRegDeadAfter(): for a pair register this is old-pair-value
/// liveness, not proof that both physical halves may be clobbered. Use separate
/// H/L, D/E, or B/C checks when the expansion can destroy both halves.
static bool isRegDeadAtMI(unsigned Reg, const MachineInstr &MI,
                          MachineBasicBlock &MBB,
                          const TargetRegisterInfo *TRI) {
  for (auto I = std::next(MI.getIterator()); I != MBB.end(); ++I) {
    bool usesReg = false, defsReg = false;
    for (const MachineOperand &MO : I->operands()) {
      if (!MO.isReg() || !TRI->regsOverlap(MO.getReg(), Reg))
        continue;
      if (MO.isUse() && !MO.isUndef()) {
        bool IsArtifact = false;
        if (MO.isImplicit() && MO.isKill() &&
            TRI->isSubRegister(MO.getReg(), Reg)) {
          for (const MachineOperand &Sub : I->operands()) {
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
      return false;
    if (defsReg)
      return true;
  }
  for (MachineBasicBlock *Succ : MBB.successors()) {
    for (MCRegAliasIterator AI(Reg, TRI, /*IncludeSelf=*/true); AI.isValid();
         ++AI) {
      if (Succ->isLiveIn(*AI))
        return false;
    }
  }
  return true;
}

/// O71 — Find a GR8 register that is dead at MI, or Register() if none.
/// Skips A (callers handle A specially via PUSH PSW / POP PSW). Skips
/// any register aliased by Exclude1 / Exclude2 (typically the address
/// pair and/or destination pair of a 16-bit load expansion).
static Register findDeadGR8AtMI(const MachineInstr &MI,
                                MachineBasicBlock &MBB,
                                const TargetRegisterInfo *TRI,
                                Register Exclude1 = Register(),
                                Register Exclude2 = Register()) {
  // GR8 minus A. Order is arbitrary; preferring the BC pair first leaves
  // H/L (often live as pointer halves) for last.
  static const unsigned Candidates[] = {
      V6Clang::B, V6Clang::C, V6Clang::D, V6Clang::E, V6Clang::H, V6Clang::L,
  };
  for (unsigned R : Candidates) {
    if (Exclude1 && TRI->regsOverlap(R, Exclude1))
      continue;
    if (Exclude2 && TRI->regsOverlap(R, Exclude2))
      continue;
    if (isRegDeadAtMI(R, MI, MBB, TRI))
      return Register(R);
  }
  return Register();
}

/// O49 — Direct memory M-operand pseudo expansion helper.
/// Emits any M-operand instruction (ADDM/SUBM/.../MVIM/INRM/DCRM) with
/// appropriate HL/DE/BC address staging. `Emit` is a callable that
/// builds the physical instruction at the insertion point.
template <typename EmitFn>
static void expandMemOpM(MachineBasicBlock &MBB, MachineInstr &MI,
                         const V6ClangInstrInfo &TII,
                         const V6ClangRegisterInfo &RI,
                         Register AddrReg, EmitFn Emit) {
  DebugLoc DL = MI.getDebugLoc();
  auto Ip = MI.getIterator();

  if (AddrReg == V6Clang::HL) {
    Emit(MBB, Ip);
    return;
  }
  if (AddrReg == V6Clang::DE) {
    // XCHG; OP M; XCHG — restores HL and DE. The trailing XCHG can
    // be omitted only when BOTH HL and DE are dead after MI: the first
    // XCHG puts the address in HL and old-HL in DE, so if DE is still
    // live after the pseudo (e.g. a subsequent STORE8_P uses DE as the
    // address register), omitting the restore leaves DE = old-HL
    // instead of the original address, causing the store to write to
    // the wrong location.
    bool HLDead = isRegDeadAtMI(V6Clang::HL, MI, MBB, &RI);
    bool DEDead = isRegDeadAtMI(V6Clang::DE, MI, MBB, &RI);
    BuildMI(MBB, Ip, DL, TII.get(V6Clang::XCHG));
    Emit(MBB, Ip);
    if (!HLDead || !DEDead)
      BuildMI(MBB, Ip, DL, TII.get(V6Clang::XCHG));
    return;
  }
  // AddrReg == V6Clang::BC — no swap instruction; copy B→H, C→L, restore HL.
  bool HLDead = isRegDeadAtMI(V6Clang::HL, MI, MBB, &RI);
  if (!HLDead)
    BuildMI(MBB, Ip, DL, TII.get(V6Clang::PUSH))
        .addReg(V6Clang::HL, RegState::Kill)
        .addReg(V6Clang::SP, RegState::ImplicitDefine);
  BuildMI(MBB, Ip, DL, TII.get(V6Clang::MOVrr), V6Clang::L).addReg(V6Clang::C);
  BuildMI(MBB, Ip, DL, TII.get(V6Clang::MOVrr), V6Clang::H).addReg(V6Clang::B);
  Emit(MBB, Ip);
  if (!HLDead)
    BuildMI(MBB, Ip, DL, TII.get(V6Clang::POP), V6Clang::HL)
        .addReg(V6Clang::SP, RegState::ImplicitDefine);
}

bool V6ClangInstrInfo::expandPostRAPseudo(MachineInstr &MI) const {
  MachineBasicBlock &MBB = *MI.getParent();
  DebugLoc DL = MI.getDebugLoc();

  // Speculatively insert annotation comment before expansion.
  // Removed in `default` case when no expansion occurs.
  MachineInstr *CommentMI = nullptr;
  if (getV6ClangAnnotatePseudosEnabled()) {
    CommentMI = BuildMI(MBB, MI, DL, get(V6Clang::V6CLANG_PSEUDO_COMMENT))
                    .addImm(MI.getOpcode())
                    .getInstr();
  }

  switch (MI.getOpcode()) {
  default:
    if (CommentMI)
      CommentMI->eraseFromParent();
    return false;

  case V6Clang::V6CLANG_BUILD_PAIR: {
    // Combine two i8 values into i16 register pair.
    Register Dst = MI.getOperand(0).getReg();
    Register Lo = MI.getOperand(1).getReg();
    Register Hi = MI.getOperand(2).getReg();
    MCRegister DstLo = RI.getSubReg(Dst, V6Clang::sub_lo);
    MCRegister DstHi = RI.getSubReg(Dst, V6Clang::sub_hi);
    // Copy hi first in case DstLo == Hi (avoids clobbering).
    if (Hi != DstHi)
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(Hi);
    if (Lo != DstLo)
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(Lo);
    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_NEG16: {
    // Negate a 16-bit pair without first materializing a zero scratch pair.
    Register DstReg = MI.getOperand(0).getReg();
    Register SrcReg = MI.getOperand(1).getReg();
    MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
    MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);
    MCRegister SrcLo = RI.getSubReg(SrcReg, V6Clang::sub_lo);
    MCRegister SrcHi = RI.getSubReg(SrcReg, V6Clang::sub_hi);

    MachineInstr *XraMI = BuildMI(MBB, MI, DL, get(V6Clang::XRAr), V6Clang::A)
                              .addReg(V6Clang::A)
                              .addReg(V6Clang::A)
                              .getInstr();
    if (!isRegLiveBefore(MBB, XraMI->getIterator(), V6Clang::A, &RI))
      markRegUsesUndef(XraMI, V6Clang::A);

    BuildMI(MBB, MI, DL, get(V6Clang::SUBr), V6Clang::A)
        .addReg(V6Clang::A)
        .addReg(SrcLo);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::A);
    BuildMI(MBB, MI, DL, get(V6Clang::SBBr), V6Clang::A)
        .addReg(V6Clang::A)
        .addReg(V6Clang::A);
    BuildMI(MBB, MI, DL, get(V6Clang::SUBr), V6Clang::A)
        .addReg(V6Clang::A)
        .addReg(SrcHi);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::A);

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_NEG8: {
    // Result-only i8 negate. Use CMA; INR A only when the source is already
    // in A; keep the subtract-based shape for every other case.
    Register Dst = MI.getOperand(0).getReg();
    Register Src = MI.getOperand(1).getReg();
    bool SrcKilled = MI.getOperand(1).isKill();

    // RA may materialize a short-lived copy `MOV Src, A` immediately before
    // the pseudo when the original value already lives in A. Fold that copy
    // back into the accumulator-only negate shape.
    if (Src != V6Clang::A && SrcKilled) {
      auto PrevIt = MI.getIterator();
      while (PrevIt != MBB.begin()) {
        --PrevIt;
        if (PrevIt->isDebugInstr() || PrevIt->getOpcode() == V6Clang::V6CLANG_PSEUDO_COMMENT)
          continue;

        bool IsCopyFromA = false;
        if (PrevIt->getOpcode() == V6Clang::MOVrr) {
          IsCopyFromA = PrevIt->getOperand(0).getReg() == Src &&
                        PrevIt->getOperand(1).getReg() == V6Clang::A;
        } else if (PrevIt->isCopy()) {
          IsCopyFromA = PrevIt->getOperand(0).getReg() == Src &&
                        PrevIt->getOperand(1).getReg() == V6Clang::A;
        }

        if (IsCopyFromA) {
          PrevIt->eraseFromParent();
          Src = V6Clang::A;
        }
        break;
      }
    }

    if (Src == V6Clang::A) {
      BuildMI(MBB, MI, DL, get(V6Clang::CMA), V6Clang::A).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::INRr), V6Clang::A).addReg(V6Clang::A);
      if (Dst != V6Clang::A)
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), Dst).addReg(V6Clang::A);
    } else {
      MachineInstr *XraMI = BuildMI(MBB, MI, DL, get(V6Clang::XRAr), V6Clang::A)
                                .addReg(V6Clang::A)
                                .addReg(V6Clang::A)
                                .getInstr();
      if (!isRegLiveBefore(MBB, XraMI->getIterator(), V6Clang::A, &RI))
        markRegUsesUndef(XraMI, V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::SUBr), V6Clang::A)
          .addReg(V6Clang::A)
          .addReg(Src, getKillRegState(SrcKilled));
      if (Dst != V6Clang::A)
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), Dst).addReg(V6Clang::A);
    }

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_SEXT: {
    // Sign-extend i8 to i16 via RLC + SBB.
    // RLC rotates A left: bit 7 → carry.
    // SBB A: A = A - A - carry = -carry = 0x00 or 0xFF.
    Register Dst = MI.getOperand(0).getReg();
    Register Src = MI.getOperand(1).getReg();
    MCRegister DstLo = RI.getSubReg(Dst, V6Clang::sub_lo);
    MCRegister DstHi = RI.getSubReg(Dst, V6Clang::sub_hi);

    // Copy source to destination low byte first.
    if (Src != DstLo)
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(Src);
    // Compute sign extension: MOV A, Src; RLC; SBB A; MOV DstHi, A
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(Src);
    BuildMI(MBB, MI, DL, get(V6Clang::RLC), V6Clang::A).addReg(V6Clang::A);
    BuildMI(MBB, MI, DL, get(V6Clang::SBBr), V6Clang::A)
        .addReg(V6Clang::A).addReg(V6Clang::A);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::A);
    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_BRCOND: {
    MachineBasicBlock *Target = MI.getOperand(0).getMBB();
    int64_t CC = MI.getOperand(1).getImm();

    unsigned JccOpc;
    switch (CC) {
    default: llvm_unreachable("Unknown V6CLANG condition code");
    case V6ClangCC::COND_NZ: JccOpc = V6Clang::JNZ; break;
    case V6ClangCC::COND_Z:  JccOpc = V6Clang::JZ;  break;
    case V6ClangCC::COND_NC: JccOpc = V6Clang::JNC; break;
    case V6ClangCC::COND_C:  JccOpc = V6Clang::JC;  break;
    case V6ClangCC::COND_PO: JccOpc = V6Clang::JPO; break;
    case V6ClangCC::COND_PE: JccOpc = V6Clang::JPE; break;
    case V6ClangCC::COND_P:  JccOpc = V6Clang::JP;  break;
    case V6ClangCC::COND_M:  JccOpc = V6Clang::JM;  break;
    }

    BuildMI(MBB, MI, DL, get(JccOpc)).addMBB(Target);
    MI.eraseFromParent();
    return true;
  }

  //===------------------------------------------------------------------===//
  // M7: i16 arithmetic pseudo expansions
  //===------------------------------------------------------------------===//

  // O41: Pre-RA INX/DCX pseudos — expand to N copies of INX/DCX rp.
  case V6Clang::V6CLANG_INX16: {
    Register Rp = MI.getOperand(0).getReg();
    unsigned Count = MI.getOperand(2).getImm();
    for (unsigned I = 0; I < Count; ++I)
      BuildMI(MBB, MI, DL, get(V6Clang::INX), Rp).addReg(Rp);
    MI.eraseFromParent();
    return true;
  }
  case V6Clang::V6CLANG_DCX16: {
    Register Rp = MI.getOperand(0).getReg();
    unsigned Count = MI.getOperand(2).getImm();
    for (unsigned I = 0; I < Count; ++I)
      BuildMI(MBB, MI, DL, get(V6Clang::DCX), Rp).addReg(Rp);
    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_DAD: {
    // V6CLANG_DAD: dst = lhs + rhs via physical DAD instruction.
    Register DstReg = MI.getOperand(0).getReg();
    Register LhsReg = MI.getOperand(1).getReg();
    Register RhsReg = MI.getOperand(2).getReg();
    assert(V6Clang::GR16RegClass.contains(DstReg) &&
           "V6CLANG_DAD result must be an allocatable register pair");

    Register BaseReg = LhsReg;
    Register AddReg = RhsReg;
    if (RhsReg == V6Clang::HL) {
      BaseReg = RhsReg;
      AddReg = LhsReg;
    }
    // V6CLANG_DAD physically writes the whole HL pair. The helper's pair query
    // would answer whether the old 16-bit HL value is dead; that is too weak
    // here because a later def of L can kill the old pair value while H is
    // still live as an independent i8. Since skipping preservation clobbers
    // both halves, require both H and L to be dead separately.
    bool HLDead = isRegDeadAfter(MBB, MI.getIterator(), V6Clang::H, &RI) &&
            isRegDeadAfter(MBB, MI.getIterator(), V6Clang::L, &RI);
    bool PreserveHL = DstReg != V6Clang::HL && !HLDead;

    // Try INX/DCX chains for small constants loaded by a preceding LXI.
    // INX/DCX set no flags, so this is only valid when FLAGS is dead.
    if (isFlagsDefDead(MI)) {
      MachineInstr *LXI = findDefiningLXI(MBB, MI.getIterator(), AddReg, &RI);
      if (LXI) {
        int64_t ImmVal = LXI->getOperand(1).getImm();
        if (ImmVal > 0x7FFF)
          ImmVal -= 0x10000;
        if (ImmVal != 0) {
          unsigned AbsVal =
              static_cast<unsigned>(ImmVal > 0 ? ImmVal : -ImmVal);
          unsigned InxOpc = ImmVal > 0 ? V6Clang::INX : V6Clang::DCX;
          V6ClangOptMode Mode = getV6ClangOptMode(*MBB.getParent());
          V6ClangInstrCost InxCost = V6ClangCost::INX * AbsVal;
          V6ClangInstrCost DadCost = V6ClangCost::LXI + V6ClangCost::DAD;
          if (InxCost.isCheaperOrEqual(DadCost, Mode)) {
            if (PreserveHL)
              BuildMI(MBB, MI, DL, get(V6Clang::PUSH)).addReg(V6Clang::HL);
            if (BaseReg != V6Clang::HL)
              copyPhysReg(MBB, MI, DL, V6Clang::HL, BaseReg, /*KillSrc=*/false);
            for (unsigned I = 0; I < AbsVal; ++I)
              BuildMI(MBB, MI, DL, get(InxOpc), V6Clang::HL).addReg(V6Clang::HL);
            if (DstReg != V6Clang::HL)
              copyPhysReg(MBB, MI, DL, DstReg, V6Clang::HL, /*KillSrc=*/false);
            if (PreserveHL)
              BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::HL);
            Register ConstReg = LXI->getOperand(0).getReg();
            if (LXI->getParent() == &MBB &&
                isRegDeadAfter(MBB, MI.getIterator(), ConstReg, &RI))
              LXI->eraseFromParent();
            MI.eraseFromParent();
            return true;
          }
        }
      }
    }

    if (PreserveHL && BaseReg == V6Clang::HL && AddReg == V6Clang::DE &&
        DstReg == V6Clang::DE) {
      BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
      BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(V6Clang::DE);
      BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
      MI.eraseFromParent();
      return true;
    }

    if (PreserveHL)
      BuildMI(MBB, MI, DL, get(V6Clang::PUSH)).addReg(V6Clang::HL);
    if (BaseReg != V6Clang::HL)
      copyPhysReg(MBB, MI, DL, V6Clang::HL, BaseReg, /*KillSrc=*/false);
    BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(AddReg);
    if (DstReg != V6Clang::HL)
      copyPhysReg(MBB, MI, DL, DstReg, V6Clang::HL, /*KillSrc=*/false);
    if (PreserveHL)
      BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::HL);
    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_ADD16: {
    // dst = lhs + rhs (16-bit)
    Register DstReg = MI.getOperand(0).getReg();
    Register LhsReg = MI.getOperand(1).getReg();
    Register RhsReg = MI.getOperand(2).getReg();

    // INX/DCX chains for small constants via cost model.
    // Checked BEFORE DAD so that HL benefits too (INX doesn't clobber
    // a helper pair).
    if (isFlagsDefDead(MI)) {
      // Try RhsReg as the constant.
      MachineInstr *LXI = findDefiningLXI(MBB, MI.getIterator(), RhsReg, &RI);
      Register BaseReg = LhsReg;
      if (!LXI) {
        // Try LhsReg as the constant (add is commutative).
        LXI = findDefiningLXI(MBB, MI.getIterator(), LhsReg, &RI);
        BaseReg = RhsReg;
      }
      if (LXI && DstReg == BaseReg) {
        int64_t ImmVal = LXI->getOperand(1).getImm();
        // Normalize unsigned 16-bit to signed.
        if (ImmVal > 0x7FFF)
          ImmVal -= 0x10000;
        if (ImmVal != 0) {
          unsigned AbsVal =
              static_cast<unsigned>(ImmVal > 0 ? ImmVal : -ImmVal);
          unsigned InxOpc = ImmVal > 0 ? V6Clang::INX : V6Clang::DCX;
          V6ClangOptMode Mode = getV6ClangOptMode(*MBB.getParent());
          V6ClangInstrCost InxCost = V6ClangCost::INX * AbsVal;
          V6ClangInstrCost DadCost = V6ClangCost::LXI + V6ClangCost::DAD;
          if (InxCost.isCheaperOrEqual(DadCost, Mode)) {
            for (unsigned I = 0; I < AbsVal; ++I)
              BuildMI(MBB, MI, DL, get(InxOpc), DstReg).addReg(DstReg);
            Register ConstReg = LXI->getOperand(0).getReg();
            if (LXI->getParent() == &MBB &&
                isRegDeadAfter(MBB, MI.getIterator(), ConstReg, &RI))
              LXI->eraseFromParent();
            MI.eraseFromParent();
            return true;
          }
        }
      }
    }

    // DAD rp: HL = HL + rp. Only sets Carry flag.
    // Optimization: if dst==HL and one operand is HL, use DAD rp (12cc)
    // instead of the full 6-instruction 8-bit chain (~40cc).
    if (DstReg == V6Clang::HL && LhsReg == V6Clang::HL) {
      BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(RhsReg);
      MI.eraseFromParent();
      return true;
    }
    if (DstReg == V6Clang::HL && RhsReg == V6Clang::HL) {
      // ADD is commutative: HL = rp + HL → DAD rp
      BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(LhsReg);
      MI.eraseFromParent();
      return true;
    }

    // DE = DE + DE. Preserve HL with XCHG; DAD H; XCHG (18cc, 3B),
    // instead of the general A-byte chain (24cc, 6B). The second XCHG
    // restores old HL; if it was undef, mark the XCHG implicit reads as
    // undef for the MIR verifier.
    if (DstReg == V6Clang::DE && LhsReg == V6Clang::DE && RhsReg == V6Clang::DE) {
      bool HLLive = isRegLiveBefore(MBB, MI.getIterator(), V6Clang::HL, &RI);
      MachineInstr *FirstXchg = BuildMI(MBB, MI, DL, get(V6Clang::XCHG)).getInstr();
      BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(V6Clang::HL);
      MachineInstr *SecondXchg = BuildMI(MBB, MI, DL, get(V6Clang::XCHG)).getInstr();
      if (!HLLive) {
        markXchgUseUndef(FirstXchg, V6Clang::HL);
        markXchgUseUndef(SecondXchg, V6Clang::DE);
      }
      MI.eraseFromParent();
      return true;
    }

    // DE = DE + BC. Preserve HL with XCHG; DAD B; XCHG (20cc, 3B),
    // instead of the general A-byte chain. This is valid even when old HL
    // is live because the second XCHG restores it. If old HL is undef, mark
    // the corresponding XCHG implicit reads as undef for the MIR verifier.
    if (DstReg == V6Clang::DE &&
        ((LhsReg == V6Clang::DE && RhsReg == V6Clang::BC) ||
         (LhsReg == V6Clang::BC && RhsReg == V6Clang::DE))) {
      bool HLLive = isRegLiveBefore(MBB, MI.getIterator(), V6Clang::HL, &RI);
      MachineInstr *FirstXchg = BuildMI(MBB, MI, DL, get(V6Clang::XCHG)).getInstr();
      BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(V6Clang::BC);
      MachineInstr *SecondXchg = BuildMI(MBB, MI, DL, get(V6Clang::XCHG)).getInstr();
      if (!HLLive) {
        markXchgUseUndef(FirstXchg, V6Clang::HL);
        markXchgUseUndef(SecondXchg, V6Clang::DE);
      }
      MI.eraseFromParent();
      return true;
    }

    // BC = BC + DE (or commutative) with DE dead after.
    // Route through HL via XCHG; DAD B; XCHG; MOV B,D; MOV C,E (36cc, 5B)
    // instead of the general 8-bit A-chain (40cc, 6B). HL is preserved by
    // the paired XCHGs. If old HL is undef, mark the XCHG reads accordingly.
    // Mirror of the DE=DE+BC fast path above.
    if (DstReg == V6Clang::BC &&
        ((LhsReg == V6Clang::BC && RhsReg == V6Clang::DE) ||
         (LhsReg == V6Clang::DE && RhsReg == V6Clang::BC)) &&
        isRegDeadAfter(MBB, MI.getIterator(), V6Clang::DE, &RI)) {
      bool HLLive = isRegLiveBefore(MBB, MI.getIterator(), V6Clang::HL, &RI);
      MachineInstr *FirstXchg = BuildMI(MBB, MI, DL, get(V6Clang::XCHG)).getInstr();
      BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(V6Clang::BC);
      MachineInstr *SecondXchg = BuildMI(MBB, MI, DL, get(V6Clang::XCHG)).getInstr();
      if (!HLLive) {
        markXchgUseUndef(FirstXchg, V6Clang::HL);
        markXchgUseUndef(SecondXchg, V6Clang::DE);
      }
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::B).addReg(V6Clang::D);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::C).addReg(V6Clang::E);
      MI.eraseFromParent();
      return true;
    }

    // --- Path A: one operand is HL, DstReg != HL ---
    // Use DAD + copy result out (via XCHG for DE, MOV pair for BC).
    if (DstReg != V6Clang::HL &&
        (LhsReg == V6Clang::HL || RhsReg == V6Clang::HL)) {
      Register OtherReg = (LhsReg == V6Clang::HL) ? RhsReg : LhsReg;
      bool HLDead = isRegDeadAfter(MBB, MI.getIterator(), V6Clang::HL, &RI);

      if (DstReg == V6Clang::DE) {
        if (HLDead) {
          // A1-DE: DAD OtherReg; XCHG → 16cc, 2B
          BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(OtherReg);
          BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
          MI.eraseFromParent();
          return true;
        }
        if (OtherReg == V6Clang::DE) {
          // A2-DE: DE = HL + DE, HL live. XCHG; DAD DE; XCHG → 20cc, 3B
          BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
          BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(V6Clang::DE);
          BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
          MI.eraseFromParent();
          return true;
        }
        // A3-DE: DE = HL + BC, HL live. Preserve HL explicitly around DAD.
        BuildMI(MBB, MI, DL, get(V6Clang::PUSH)).addReg(V6Clang::HL);
        BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(OtherReg);
        BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
        BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::HL);
        MI.eraseFromParent();
        return true;
      }

      if (HLDead) {
        // A-general (dest=BC): DAD + MOV pair → 28cc, 3B
        BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(OtherReg);
        MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);
        MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::H);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::L);
        MI.eraseFromParent();
        return true;
      }
      // A-general live-HL (dest=BC): preserve HL explicitly around DAD.
      BuildMI(MBB, MI, DL, get(V6Clang::PUSH)).addReg(V6Clang::HL);
      BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(OtherReg);
      MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);
      MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::H);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::L);
      BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::HL);
      MI.eraseFromParent();
      return true;
    }

    // --- Path B: DstReg == HL, neither operand is HL ---
    // Copy one operand into HL (via XCHG for DE, MOV pair otherwise),
    // then DAD the other.
    if (DstReg == V6Clang::HL && LhsReg != V6Clang::HL && RhsReg != V6Clang::HL) {
      // B1-DE: one operand is DE (not both), DE dead → XCHG + DAD
      if (LhsReg != RhsReg) {
        Register DEOp = Register();
        Register NonDEOp = Register();
        if (LhsReg == V6Clang::DE) {
          DEOp = LhsReg;
          NonDEOp = RhsReg;
        } else if (RhsReg == V6Clang::DE) {
          DEOp = RhsReg;
          NonDEOp = LhsReg;
        }
        if (DEOp && isRegDeadAfter(MBB, MI.getIterator(), V6Clang::DE, &RI)) {
          // XCHG; DAD NonDEOp → 16cc, 2B
          BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
          BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(NonDEOp);
          MI.eraseFromParent();
          return true;
        }
      }

      // B-general: MOV pair + DAD → 28cc, 3B
      {
        MCRegister LhsHi = RI.getSubReg(LhsReg, V6Clang::sub_hi);
        MCRegister LhsLo = RI.getSubReg(LhsReg, V6Clang::sub_lo);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::H).addReg(LhsHi);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::L).addReg(LhsLo);
        BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(RhsReg);
        MI.eraseFromParent();
        return true;
      }
    }

    // General case: expand to 8-bit chain.
    MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
    MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);
    MCRegister LhsLo = RI.getSubReg(LhsReg, V6Clang::sub_lo);
    MCRegister LhsHi = RI.getSubReg(LhsReg, V6Clang::sub_hi);
    MCRegister RhsLo = RI.getSubReg(RhsReg, V6Clang::sub_lo);
    MCRegister RhsHi = RI.getSubReg(RhsReg, V6Clang::sub_hi);

    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(LhsLo);
    BuildMI(MBB, MI, DL, get(V6Clang::ADDr), V6Clang::A)
        .addReg(V6Clang::A).addReg(RhsLo);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::A);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(LhsHi);
    BuildMI(MBB, MI, DL, get(V6Clang::ADCr), V6Clang::A)
        .addReg(V6Clang::A).addReg(RhsHi);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::A);

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_SUB16: {
    // dst = lhs - rhs (16-bit)
    Register DstReg = MI.getOperand(0).getReg();
    Register LhsReg = MI.getOperand(1).getReg();
    Register RhsReg = MI.getOperand(2).getReg();

    // DCX/INX chains for small constants via cost model.
    // Subtraction is not commutative: only RhsReg can be the constant.
    if (isFlagsDefDead(MI) && DstReg == LhsReg) {
      MachineInstr *LXI = findDefiningLXI(MBB, MI.getIterator(), RhsReg, &RI);
      if (LXI) {
        int64_t ImmVal = LXI->getOperand(1).getImm();
        // Normalize unsigned 16-bit to signed.
        if (ImmVal > 0x7FFF)
          ImmVal -= 0x10000;
        if (ImmVal != 0) {
          unsigned AbsVal =
              static_cast<unsigned>(ImmVal > 0 ? ImmVal : -ImmVal);
          unsigned InxOpc = ImmVal > 0 ? V6Clang::DCX : V6Clang::INX;
          V6ClangOptMode Mode = getV6ClangOptMode(*MBB.getParent());
          V6ClangInstrCost InxCost = V6ClangCost::INX * AbsVal;
          V6ClangInstrCost DadCost = V6ClangCost::LXI + V6ClangCost::DAD;
          if (InxCost.isCheaperOrEqual(DadCost, Mode)) {
            for (unsigned I = 0; I < AbsVal; ++I)
              BuildMI(MBB, MI, DL, get(InxOpc), DstReg).addReg(DstReg);
            Register ConstReg = LXI->getOperand(0).getReg();
            if (LXI->getParent() == &MBB &&
                isRegDeadAfter(MBB, MI.getIterator(), ConstReg, &RI))
              LXI->eraseFromParent();
            MI.eraseFromParent();
            return true;
          }
        }
      }
    }

    MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
    MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);
    MCRegister LhsLo = RI.getSubReg(LhsReg, V6Clang::sub_lo);
    MCRegister LhsHi = RI.getSubReg(LhsReg, V6Clang::sub_hi);
    MCRegister RhsLo = RI.getSubReg(RhsReg, V6Clang::sub_lo);
    MCRegister RhsHi = RI.getSubReg(RhsReg, V6Clang::sub_hi);

    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(LhsLo);
    BuildMI(MBB, MI, DL, get(V6Clang::SUBr), V6Clang::A)
        .addReg(V6Clang::A).addReg(RhsLo);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::A);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(LhsHi);
    BuildMI(MBB, MI, DL, get(V6Clang::SBBr), V6Clang::A)
        .addReg(V6Clang::A).addReg(RhsHi);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::A);

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_AND16:
  case V6Clang::V6CLANG_OR16:
  case V6Clang::V6CLANG_XOR16: {
    // dst = lhs OP rhs (16-bit, pair-wise 8-bit)
    unsigned OpOpc;
    switch (MI.getOpcode()) {
    case V6Clang::V6CLANG_AND16: OpOpc = V6Clang::ANAr; break;
    case V6Clang::V6CLANG_OR16:  OpOpc = V6Clang::ORAr; break;
    case V6Clang::V6CLANG_XOR16: OpOpc = V6Clang::XRAr; break;
    default: llvm_unreachable("unexpected opcode");
    }

    Register DstReg = MI.getOperand(0).getReg();
    Register LhsReg = MI.getOperand(1).getReg();
    Register RhsReg = MI.getOperand(2).getReg();

    MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
    MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);
    MCRegister LhsLo = RI.getSubReg(LhsReg, V6Clang::sub_lo);
    MCRegister LhsHi = RI.getSubReg(LhsReg, V6Clang::sub_hi);
    MCRegister RhsLo = RI.getSubReg(RhsReg, V6Clang::sub_lo);
    MCRegister RhsHi = RI.getSubReg(RhsReg, V6Clang::sub_hi);

    // O89: skip hi-byte computation when DstHi is dead (e.g. (u8)(a OP b)).
    bool HiDead = isRegDeadAfter(MBB, MI.getIterator(), DstHi, &RI);

    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(LhsLo);
    BuildMI(MBB, MI, DL, get(OpOpc), V6Clang::A)
        .addReg(V6Clang::A).addReg(RhsLo);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::A);
    if (!HiDead) {
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(LhsHi);
      BuildMI(MBB, MI, DL, get(OpOpc), V6Clang::A)
          .addReg(V6Clang::A).addReg(RhsHi);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::A);
    }

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_AND16_IMM:
  case V6Clang::V6CLANG_OR16_IMM:
  case V6Clang::V6CLANG_XOR16_IMM: {
    // O93: dst = src OP imm16 (constant). dst and src are tied to the same
    // pair. The constant is loaded into A byte-wise and the cheaper 4cc
    // register ALU form is applied (legal because AND/OR/XOR are commutative),
    // so no scratch register pair is needed. Per-byte 0x00/0xFF identities are
    // folded away, and a dead high byte is skipped (O89-style).
    unsigned Kind = MI.getOpcode();
    unsigned OpOpc;
    switch (Kind) {
    case V6Clang::V6CLANG_AND16_IMM: OpOpc = V6Clang::ANAr; break;
    case V6Clang::V6CLANG_OR16_IMM:  OpOpc = V6Clang::ORAr; break;
    case V6Clang::V6CLANG_XOR16_IMM: OpOpc = V6Clang::XRAr; break;
    default: llvm_unreachable("unexpected opcode");
    }

    Register DstReg = MI.getOperand(0).getReg();
    uint64_t Imm = MI.getOperand(2).getImm();
    unsigned LoByte = Imm & 0xFF;
    unsigned HiByte = (Imm >> 8) & 0xFF;

    MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
    MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);

    // O89: skip the hi-byte work entirely when DstHi is dead (e.g. (u8)(x OP C)).
    bool HiDead = isRegDeadAfter(MBB, MI.getIterator(), DstHi, &RI);

    // Emit `RegByte = RegByte OP ByteVal` with per-byte identity folding.
    auto emitByte = [&](unsigned ByteVal, MCRegister RegByte) {
      switch (Kind) {
      case V6Clang::V6CLANG_AND16_IMM:
        if (ByteVal == 0xFF)
          return; // x & 0xFF == x — identity.
        if (ByteVal == 0x00) {
          // x & 0x00 == 0 — just zero the byte (O55 may fold MVI A,0 → XRA A).
          BuildMI(MBB, MI, DL, get(V6Clang::MVIr), RegByte).addImm(0);
          return;
        }
        break;
      case V6Clang::V6CLANG_OR16_IMM:
        if (ByteVal == 0x00)
          return; // x | 0x00 == x — identity.
        if (ByteVal == 0xFF) {
          // x | 0xFF == 0xFF — set the byte.
          BuildMI(MBB, MI, DL, get(V6Clang::MVIr), RegByte).addImm(0xFF);
          return;
        }
        break;
      case V6Clang::V6CLANG_XOR16_IMM:
        if (ByteVal == 0x00)
          return; // x ^ 0x00 == x — identity.
        break;
      }
      // Generic: MVI A, ByteVal; OP A, RegByte; MOV RegByte, A.
      BuildMI(MBB, MI, DL, get(V6Clang::MVIr), V6Clang::A).addImm(ByteVal);
      BuildMI(MBB, MI, DL, get(OpOpc), V6Clang::A).addReg(V6Clang::A).addReg(RegByte);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), RegByte).addReg(V6Clang::A);
    };

    emitByte(LoByte, DstLo);
    if (!HiDead)
      emitByte(HiByte, DstHi);

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_CMP16_ZERO: {
    // O34: Zero-test for i16 — MOV A, Hi; ORA Lo → Z=1 iff pair==0.
    Register SrcReg = MI.getOperand(0).getReg();
    MCRegister SrcLo = RI.getSubReg(SrcReg, V6Clang::sub_lo);
    MCRegister SrcHi = RI.getSubReg(SrcReg, V6Clang::sub_hi);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(SrcHi);
    BuildMI(MBB, MI, DL, get(V6Clang::ORAr), V6Clang::A)
        .addReg(V6Clang::A).addReg(SrcLo);
    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_CMP16_SIGN: {
    // Signed compare against zero — XRA A; ADD hi(src) exposes the pair's
    // sign bit in S while staying cheaper than the generic IMM compare.
    Register SrcReg = MI.getOperand(0).getReg();
    MCRegister SrcHi = RI.getSubReg(SrcReg, V6Clang::sub_hi);

    MachineInstr *XraMI = BuildMI(MBB, MI, DL, get(V6Clang::XRAr), V6Clang::A)
                              .addReg(V6Clang::A)
                              .addReg(V6Clang::A)
                              .getInstr();
    if (!isRegLiveBefore(MBB, XraMI->getIterator(), V6Clang::A, &RI))
      markRegUsesUndef(XraMI, V6Clang::A);

    BuildMI(MBB, MI, DL, get(V6Clang::ADDr), V6Clang::A)
        .addReg(V6Clang::A)
        .addReg(SrcHi);

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_CMP8_ZERO: {
    // O80: Zero-test for i8 with three liveness-driven shapes.
    //   src = A          → ORA A                  (1B / 4cc)
    //   src ≠ A, A dead  → XRA A; CMP src         (2B / 8cc, O38 path)
    //   src ≠ A, A live  → INR src; DCR src       (2B / 16cc, A-preserving)
    // INR/DCR set Z/S/P/AC from src's original value and leave A and CY
    // untouched. All zero-test consumers (V6CLANG_BRCOND / V6CLANG_SELECT_CC)
    // read only Z/S/P, so the CY/AC divergence vs ORA A is unobservable.
    Register Src = MI.getOperand(0).getReg();
    bool SrcKilled = MI.getOperand(0).isKill();

    if (Src == V6Clang::A) {
      // Shape 1: src already in A → ORA A.
      BuildMI(MBB, MI, DL, get(V6Clang::ORAr), V6Clang::A)
          .addReg(V6Clang::A).addReg(V6Clang::A);
    } else if (isRegDeadAtMI(V6Clang::A, MI, MBB, &RI)) {
      // Shape 2: A dead → XRA A; CMP src (preserves O38 emission).
      MachineInstr *XraMI = BuildMI(MBB, MI, DL, get(V6Clang::XRAr), V6Clang::A)
        .addReg(V6Clang::A).addReg(V6Clang::A).getInstr();
      if (!isRegLiveBefore(MBB, XraMI->getIterator(), V6Clang::A, &RI))
      markRegUsesUndef(XraMI, V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::CMPr))
          .addReg(V6Clang::A)
          .addReg(Src, getKillRegState(SrcKilled));
    } else {
      // Shape 3: A live → INR src; DCR src (A-preserving zero-test).
      // Both INR/DCR are tied ($rd = $src). The kill flag belongs only
      // on the second use (DCR) so the first (INR) doesn't kill src
      // before the pair completes.
      BuildMI(MBB, MI, DL, get(V6Clang::INRr), Src).addReg(Src);
      BuildMI(MBB, MI, DL, get(V6Clang::DCRr), Src)
          .addReg(Src, getKillRegState(SrcKilled));
    }

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_CMP16: {
    // Compare lhs vs rhs (16-bit) via SUB/SBB.
    // Sets FLAGS: C for unsigned, S for signed. Z only for hi byte.
    Register LhsReg = MI.getOperand(0).getReg();
    Register RhsReg = MI.getOperand(1).getReg();

    MCRegister LhsLo = RI.getSubReg(LhsReg, V6Clang::sub_lo);
    MCRegister LhsHi = RI.getSubReg(LhsReg, V6Clang::sub_hi);
    MCRegister RhsLo = RI.getSubReg(RhsReg, V6Clang::sub_lo);
    MCRegister RhsHi = RI.getSubReg(RhsReg, V6Clang::sub_hi);

    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(LhsLo);
    BuildMI(MBB, MI, DL, get(V6Clang::SUBr), V6Clang::A)
        .addReg(V6Clang::A).addReg(RhsLo);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(LhsHi);
    BuildMI(MBB, MI, DL, get(V6Clang::SBBr), V6Clang::A)
        .addReg(V6Clang::A).addReg(RhsHi);

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_CMP16_IMM: {
    // O24: Compare lhs vs immediate (16-bit) via MVI+SUB/SBB.
    // Same as BR_CC16_IMM ordering expansion, minus the Jcc.
    // The K→K-1 + CC inversion was already done in LowerSELECT_CC.
    Register LhsReg = MI.getOperand(0).getReg();
    MachineOperand &RhsOp = MI.getOperand(1);

    MCRegister LhsLo = RI.getSubReg(LhsReg, V6Clang::sub_lo);
    MCRegister LhsHi = RI.getSubReg(LhsReg, V6Clang::sub_hi);

    auto addImmLo = [&](MachineInstrBuilder &MIB) {
      if (RhsOp.isImm()) {
        MIB.addImm(RhsOp.getImm() & 0xFF);
      } else if (RhsOp.isGlobal()) {
        MIB.addGlobalAddress(RhsOp.getGlobal(), RhsOp.getOffset(),
                             V6ClangII::MO_LO8);
      } else if (RhsOp.isSymbol()) {
        MIB.addExternalSymbol(RhsOp.getSymbolName(), V6ClangII::MO_LO8);
      } else {
        llvm_unreachable("Unexpected operand type in V6CLANG_CMP16_IMM");
      }
    };
    auto addImmHi = [&](MachineInstrBuilder &MIB) {
      if (RhsOp.isImm()) {
        MIB.addImm((RhsOp.getImm() >> 8) & 0xFF);
      } else if (RhsOp.isGlobal()) {
        MIB.addGlobalAddress(RhsOp.getGlobal(), RhsOp.getOffset(),
                             V6ClangII::MO_HI8);
      } else if (RhsOp.isSymbol()) {
        MIB.addExternalSymbol(RhsOp.getSymbolName(), V6ClangII::MO_HI8);
      } else {
        llvm_unreachable("Unexpected operand type in V6CLANG_CMP16_IMM");
      }
    };

    {
      auto MIB = BuildMI(MBB, MI, DL, get(V6Clang::MVIr), V6Clang::A);
      addImmLo(MIB);
    }
    BuildMI(MBB, MI, DL, get(V6Clang::SUBr), V6Clang::A)
        .addReg(V6Clang::A).addReg(LhsLo);
    {
      auto MIB = BuildMI(MBB, MI, DL, get(V6Clang::MVIr), V6Clang::A);
      addImmHi(MIB);
    }
    BuildMI(MBB, MI, DL, get(V6Clang::SBBr), V6Clang::A)
        .addReg(V6Clang::A).addReg(LhsHi);

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_BR_CC16: {
    // Fused 16-bit compare + conditional branch.
    // Different sequences depending on condition code.
    // Operand layout: 0=$lhs, 1=$rhs, 2=$cc, 3=$dst
    Register LhsReg = MI.getOperand(0).getReg();
    Register RhsReg = MI.getOperand(1).getReg();
    int64_t CC = MI.getOperand(2).getImm();
    MachineBasicBlock *Target = MI.getOperand(3).getMBB();

    MCRegister LhsLo = RI.getSubReg(LhsReg, V6Clang::sub_lo);
    MCRegister LhsHi = RI.getSubReg(LhsReg, V6Clang::sub_hi);
    MCRegister RhsLo = RI.getSubReg(RhsReg, V6Clang::sub_lo);
    MCRegister RhsHi = RI.getSubReg(RhsReg, V6Clang::sub_hi);

    if (CC == V6ClangCC::COND_Z || CC == V6ClangCC::COND_NZ) {
      // EQ/NE: CMP-based non-destructive expansion with MBB splitting.
      // Each byte is compared independently with an early-exit branch.
      // Neither LHS nor RHS is clobbered.
      //
      // IMPORTANT: We must NOT splice instructions from MBB to the new
      // block — ExpandPostRAPseudos uses make_early_inc_range which
      // pre-advances the iterator, and splicing would move that iterator
      // into the new MBB, causing an infinite loop. Instead, we record
      // MBB's successors, clear them, and set up both blocks from scratch.

      // Record original successors before modifying.
      SmallVector<MachineBasicBlock *, 2> OrigSuccessors(
          MBB.successors().begin(), MBB.successors().end());

      // Find the fallthrough successor (the one that's not Target).
      MachineBasicBlock *FallthroughMBB = nullptr;
      for (auto *Succ : OrigSuccessors) {
        if (Succ != Target) {
          FallthroughMBB = Succ;
          break;
        }
      }
      // If there's only one successor (Target == fallthrough), use it.
      if (!FallthroughMBB && OrigSuccessors.size() == 1)
        FallthroughMBB = OrigSuccessors[0];

      // Remove all original successors from MBB.
      while (!MBB.succ_empty())
        MBB.removeSuccessor(MBB.succ_begin());

      // Erase all terminators from MBB (V6CLANG_BR_CC16 + any trailing JMP).
      // We must not use MI after this since it gets erased here.
      while (!MBB.empty() && MBB.back().isTerminator())
        MBB.pop_back();

      // Create CompareHiMBB for the second byte comparison.
      MachineFunction *MF = MBB.getParent();
      MachineBasicBlock *CompareHiMBB =
          MF->CreateMachineBasicBlock(MBB.getBasicBlock());
      MF->insert(std::next(MBB.getIterator()), CompareHiMBB);

      if (CC == V6ClangCC::COND_NZ) {
        // NE: both JNZ go to Target.
        //   MBB: MOV A, LhsLo; CMP RhsLo; JNZ Target → fallthrough CompareHiMBB
        //   CompareHiMBB: MOV A, LhsHi; CMP RhsHi; JNZ Target; JMP FallthroughMBB

        BuildMI(&MBB, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(LhsLo);
        BuildMI(&MBB, DL, get(V6Clang::CMPr))
            .addReg(V6Clang::A).addReg(RhsLo);
        BuildMI(&MBB, DL, get(V6Clang::JNZ)).addMBB(Target);

        MBB.addSuccessor(Target);
        MBB.addSuccessor(CompareHiMBB);

        BuildMI(CompareHiMBB, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(LhsHi);
        BuildMI(CompareHiMBB, DL, get(V6Clang::CMPr))
            .addReg(V6Clang::A).addReg(RhsHi);
        BuildMI(CompareHiMBB, DL, get(V6Clang::JNZ)).addMBB(Target);
        // Explicit JMP so analyzeBranch sees Cond+Uncond (Jcc Target + JMP Fallthrough).
        // BranchFolding will remove this JMP if FallthroughMBB is the layout successor.
        BuildMI(CompareHiMBB, DL, get(V6Clang::JMP)).addMBB(FallthroughMBB);

        CompareHiMBB->addSuccessor(Target);
        CompareHiMBB->addSuccessor(FallthroughMBB);

      } else {
        // EQ: first JNZ skips to fallthrough, second JZ jumps to target.
        //   MBB: MOV A, LhsLo; CMP RhsLo; JNZ FallthroughMBB → fallthrough CompareHiMBB
        //   CompareHiMBB: MOV A, LhsHi; CMP RhsHi; JZ Target; JMP FallthroughMBB

        BuildMI(&MBB, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(LhsLo);
        BuildMI(&MBB, DL, get(V6Clang::CMPr))
            .addReg(V6Clang::A).addReg(RhsLo);
        BuildMI(&MBB, DL, get(V6Clang::JNZ)).addMBB(FallthroughMBB);

        MBB.addSuccessor(FallthroughMBB);
        MBB.addSuccessor(CompareHiMBB);

        BuildMI(CompareHiMBB, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(LhsHi);
        BuildMI(CompareHiMBB, DL, get(V6Clang::CMPr))
            .addReg(V6Clang::A).addReg(RhsHi);
        BuildMI(CompareHiMBB, DL, get(V6Clang::JZ)).addMBB(Target);
        // Explicit JMP so analyzeBranch sees Cond+Uncond (Jcc Target + JMP Fallthrough).
        // BranchFolding will remove this JMP if FallthroughMBB is the layout successor.
        BuildMI(CompareHiMBB, DL, get(V6Clang::JMP)).addMBB(FallthroughMBB);

        CompareHiMBB->addSuccessor(Target);
        CompareHiMBB->addSuccessor(FallthroughMBB);
      }

      // MI was already erased by the pop_back loop above.
      return true;
    }

    // For C/NC/M/P: use SUB/SBB sequence then Jcc.
    // SUB lo, SBB hi → carry/sign flag correct for unsigned/signed comparison.
    {
      unsigned JccOpc;
      switch (CC) {
      default: llvm_unreachable("Unknown V6CLANG condition code");
      case V6ClangCC::COND_C:  JccOpc = V6Clang::JC;  break;
      case V6ClangCC::COND_NC: JccOpc = V6Clang::JNC; break;
      case V6ClangCC::COND_M:  JccOpc = V6Clang::JM;  break;
      case V6ClangCC::COND_P:  JccOpc = V6Clang::JP;  break;
      case V6ClangCC::COND_PO: JccOpc = V6Clang::JPO; break;
      case V6ClangCC::COND_PE: JccOpc = V6Clang::JPE; break;
      }

      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(LhsLo);
      BuildMI(MBB, MI, DL, get(V6Clang::SUBr), V6Clang::A)
          .addReg(V6Clang::A).addReg(RhsLo);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(LhsHi);
      BuildMI(MBB, MI, DL, get(V6Clang::SBBr), V6Clang::A)
          .addReg(V6Clang::A).addReg(RhsHi);
      BuildMI(MBB, MI, DL, get(JccOpc)).addMBB(Target);

      MI.eraseFromParent();
      return true;
    }
  }

  case V6Clang::V6CLANG_BR_CC16_IMM: {
    // Fused 16-bit compare + branch with immediate RHS.
    // Operand layout: 0=$lhs(GR16), 1=$rhs(imm16), 2=$cc, 3=$dst
    // Expansion: MVI A, lo8(rhs); CMP LhsLo; Jcc; MVI A, hi8(rhs); CMP LhsHi; Jcc
    Register LhsReg = MI.getOperand(0).getReg();
    MachineOperand &RhsOp = MI.getOperand(1);
    int64_t CC = MI.getOperand(2).getImm();
    MachineBasicBlock *Target = MI.getOperand(3).getMBB();

    assert((CC == V6ClangCC::COND_Z || CC == V6ClangCC::COND_NZ ||
            CC == V6ClangCC::COND_C || CC == V6ClangCC::COND_NC ||
            CC == V6ClangCC::COND_M || CC == V6ClangCC::COND_P) &&
           "V6CLANG_BR_CC16_IMM: unsupported condition code");

    MCRegister LhsLo = RI.getSubReg(LhsReg, V6Clang::sub_lo);
    MCRegister LhsHi = RI.getSubReg(LhsReg, V6Clang::sub_hi);

    // --- O27: Fast zero-test path (MOV A, Hi; ORA Lo; Jcc) ---
    // When comparing against immediate 0, use the 8080 idiom:
    //   MOV A, Hi; ORA Lo → Z flag set iff (Hi|Lo)==0, i.e. pair==0
    // This avoids the MBB split and saves 10B+24cc per instance.
    // IMPORTANT: ORA only sets Z meaningfully — the C flag is cleared and
    // the S flag reflects bit 7 of the OR result, not the sign of $lhs.
    // So this fast path is only valid for EQ/NE (Z/NZ). For ordering
    // conditions (C/NC/M/P) against 0 we must fall through to the
    // MVI+SUB/SBB sequence below, which produces correct flags.
    if (RhsOp.isImm() && RhsOp.getImm() == 0 &&
        (CC == V6ClangCC::COND_Z || CC == V6ClangCC::COND_NZ)) {
      unsigned JccOpc = (CC == V6ClangCC::COND_Z) ? V6Clang::JZ : V6Clang::JNZ;
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(LhsHi);
      BuildMI(MBB, MI, DL, get(V6Clang::ORAr), V6Clang::A)
          .addReg(V6Clang::A).addReg(LhsLo);
      BuildMI(MBB, MI, DL, get(JccOpc)).addMBB(Target);
      MI.eraseFromParent();
      return true;
    }

    // Build MVI operands: for plain integers, mask directly.
    // For global addresses, use target flags (MO_LO8/MO_HI8) — the
    // AsmPrinter wraps them in V6ClangMCExpr for lo8/hi8 assembly output.
    auto addImmLo = [&](MachineInstrBuilder &MIB) {
      if (RhsOp.isImm()) {
        MIB.addImm(RhsOp.getImm() & 0xFF);
      } else if (RhsOp.isGlobal()) {
        MIB.addGlobalAddress(RhsOp.getGlobal(), RhsOp.getOffset(),
                             V6ClangII::MO_LO8);
      } else if (RhsOp.isSymbol()) {
        MIB.addExternalSymbol(RhsOp.getSymbolName(), V6ClangII::MO_LO8);
      } else {
        llvm_unreachable("Unexpected operand type in V6CLANG_BR_CC16_IMM");
      }
    };
    auto addImmHi = [&](MachineInstrBuilder &MIB) {
      if (RhsOp.isImm()) {
        MIB.addImm((RhsOp.getImm() >> 8) & 0xFF);
      } else if (RhsOp.isGlobal()) {
        MIB.addGlobalAddress(RhsOp.getGlobal(), RhsOp.getOffset(),
                             V6ClangII::MO_HI8);
      } else if (RhsOp.isSymbol()) {
        MIB.addExternalSymbol(RhsOp.getSymbolName(), V6ClangII::MO_HI8);
      } else {
        llvm_unreachable("Unexpected operand type in V6CLANG_BR_CC16_IMM");
      }
    };

    // O24: Ordering conditions (C/NC/M/P) — MVI+SUB/SBB then Jcc.
    // Unlike EQ/NE, ordering processes both bytes via the borrow chain
    // before a single conditional branch. No MBB splitting needed.
    if (CC == V6ClangCC::COND_C || CC == V6ClangCC::COND_NC ||
        CC == V6ClangCC::COND_M || CC == V6ClangCC::COND_P) {
      unsigned JccOpc;
      switch (CC) {
      default: llvm_unreachable("Unknown ordering CC");
      case V6ClangCC::COND_C:  JccOpc = V6Clang::JC;  break;
      case V6ClangCC::COND_NC: JccOpc = V6Clang::JNC; break;
      case V6ClangCC::COND_M:  JccOpc = V6Clang::JM;  break;
      case V6ClangCC::COND_P:  JccOpc = V6Clang::JP;  break;
      }

      {
        auto MIB = BuildMI(MBB, MI, DL, get(V6Clang::MVIr), V6Clang::A);
        addImmLo(MIB);
      }
      BuildMI(MBB, MI, DL, get(V6Clang::SUBr), V6Clang::A)
          .addReg(V6Clang::A).addReg(LhsLo);
      {
        auto MIB = BuildMI(MBB, MI, DL, get(V6Clang::MVIr), V6Clang::A);
        addImmHi(MIB);
      }
      BuildMI(MBB, MI, DL, get(V6Clang::SBBr), V6Clang::A)
          .addReg(V6Clang::A).addReg(LhsHi);
      BuildMI(MBB, MI, DL, get(JccOpc)).addMBB(Target);

      MI.eraseFromParent();
      return true;
    }

    // EQ/NE: Same MBB-splitting pattern as V6CLANG_BR_CC16 EQ/NE path.
    SmallVector<MachineBasicBlock *, 2> OrigSuccessors(
        MBB.successors().begin(), MBB.successors().end());

    MachineBasicBlock *FallthroughMBB = nullptr;
    for (auto *Succ : OrigSuccessors) {
      if (Succ != Target) {
        FallthroughMBB = Succ;
        break;
      }
    }
    if (!FallthroughMBB && OrigSuccessors.size() == 1)
      FallthroughMBB = OrigSuccessors[0];

    while (!MBB.succ_empty())
      MBB.removeSuccessor(MBB.succ_begin());

    while (!MBB.empty() && MBB.back().isTerminator())
      MBB.pop_back();

    // O29: When lo8 == hi8, skip the hi-byte MVI (A already holds the value
    // from the lo-byte comparison — CMP and Jcc don't modify A).
    bool SameLoHi = RhsOp.isImm() &&
        (RhsOp.getImm() & 0xFF) == ((RhsOp.getImm() >> 8) & 0xFF);

    MachineFunction *MF = MBB.getParent();
    MachineBasicBlock *CompareHiMBB =
        MF->CreateMachineBasicBlock(MBB.getBasicBlock());
    MF->insert(std::next(MBB.getIterator()), CompareHiMBB);
    CompareHiMBB->addLiveIn(LhsHi);

    if (CC == V6ClangCC::COND_NZ) {
      // NE: MVI A, lo8; CMP LhsLo; JNZ Target | MVI A, hi8; CMP LhsHi; JNZ Target
      {
        auto MIB = BuildMI(&MBB, DL, get(V6Clang::MVIr), V6Clang::A);
        addImmLo(MIB);
      }
      BuildMI(&MBB, DL, get(V6Clang::CMPr))
          .addReg(V6Clang::A).addReg(LhsLo);
      BuildMI(&MBB, DL, get(V6Clang::JNZ)).addMBB(Target);

      MBB.addSuccessor(Target);
      MBB.addSuccessor(CompareHiMBB);

      if (!SameLoHi) {
        auto MIB = BuildMI(CompareHiMBB, DL, get(V6Clang::MVIr), V6Clang::A);
        addImmHi(MIB);
      } else {
        CompareHiMBB->addLiveIn(V6Clang::A);
      }
      BuildMI(CompareHiMBB, DL, get(V6Clang::CMPr))
          .addReg(V6Clang::A).addReg(LhsHi);
      BuildMI(CompareHiMBB, DL, get(V6Clang::JNZ)).addMBB(Target);
      BuildMI(CompareHiMBB, DL, get(V6Clang::JMP)).addMBB(FallthroughMBB);

      CompareHiMBB->addSuccessor(Target);
      CompareHiMBB->addSuccessor(FallthroughMBB);
    } else {
      // EQ: MVI A, lo8; CMP LhsLo; JNZ Fallthrough | MVI A, hi8; CMP LhsHi; JZ Target
      {
        auto MIB = BuildMI(&MBB, DL, get(V6Clang::MVIr), V6Clang::A);
        addImmLo(MIB);
      }
      BuildMI(&MBB, DL, get(V6Clang::CMPr))
          .addReg(V6Clang::A).addReg(LhsLo);
      BuildMI(&MBB, DL, get(V6Clang::JNZ)).addMBB(FallthroughMBB);

      MBB.addSuccessor(FallthroughMBB);
      MBB.addSuccessor(CompareHiMBB);

      if (!SameLoHi) {
        auto MIB = BuildMI(CompareHiMBB, DL, get(V6Clang::MVIr), V6Clang::A);
        addImmHi(MIB);
      } else {
        CompareHiMBB->addLiveIn(V6Clang::A);
      }
      BuildMI(CompareHiMBB, DL, get(V6Clang::CMPr))
          .addReg(V6Clang::A).addReg(LhsHi);
      BuildMI(CompareHiMBB, DL, get(V6Clang::JZ)).addMBB(Target);
      BuildMI(CompareHiMBB, DL, get(V6Clang::JMP)).addMBB(FallthroughMBB);

      CompareHiMBB->addSuccessor(Target);
      CompareHiMBB->addSuccessor(FallthroughMBB);
    }

    // MI was already erased by the pop_back loop above.
    return true;
  }

  //===------------------------------------------------------------------===//
  // M7: i16 load/store pseudo expansions
  //===------------------------------------------------------------------===//

  case V6Clang::V6CLANG_LOAD16_P: {
    // O71 — Honest per-shape preservation.
    //
    // The pseudo declares (outs GR16:$dst, ins GR16:$addr) with no Defs.
    // Pre-RA passes treat the load as preserving every register except
    // $dst. The expander dispatches on the (addr, dst) physreg pair and
    // emits whatever cheap recovery code the shape needs to honour that
    // contract for live registers (DCX rp to undo INX, dead-GR8 spare to
    // avoid clobbering A, PUSH PSW / POP PSW or PUSH H / POP H as
    // last-resort wrappers).
    Register DstReg  = MI.getOperand(0).getReg();
    Register AddrReg = MI.getOperand(1).getReg();

    MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
    MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);

    // Helper closures. All emit at MI (replaced below by eraseFromParent).
    auto emitDCX = [&](MCRegister Pair) {
      BuildMI(MBB, MI, DL, get(V6Clang::DCX), Pair).addReg(Pair);
    };
    auto emitINXHL = [&]() {
      BuildMI(MBB, MI, DL, get(V6Clang::INX), V6Clang::HL).addReg(V6Clang::HL);
    };
    auto emitMOVrM = [&](MCRegister Dst) {
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrM), Dst);
    };
    auto emitMOVrr = [&](MCRegister Dst, MCRegister Src) {
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), Dst).addReg(Src);
    };
    auto emitXCHG = [&]() {
      BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
    };

    if (AddrReg == V6Clang::HL && DstReg == V6Clang::HL) {
      // Case 1: addr=HL, dst=HL.
      //   MOV Spare, M; INX H; MOV H, M; MOV L, Spare
      // Spare candidate must avoid HL (its halves are the destination).
      // No DCX H — dst=HL means original HL is being overwritten by
      // definition; not live across the pseudo as the prior value.
      Register Spare = findDeadGR8AtMI(MI, MBB, &RI, V6Clang::HL);
      bool UseA = !Spare;
      MCRegister Tmp = UseA ? MCRegister(V6Clang::A) : Spare.asMCReg();
      bool ALive = UseA && !isRegDeadAtMI(V6Clang::A, MI, MBB, &RI);
      if (ALive)
        BuildMI(MBB, MI, DL, get(V6Clang::PUSH)).addReg(V6Clang::PSW);
      emitMOVrM(Tmp);
      emitINXHL();
      emitMOVrM(V6Clang::H);
      emitMOVrr(V6Clang::L, Tmp);
      if (ALive)
        BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::PSW);
    } else if (AddrReg == V6Clang::HL) {
      // Case 2: addr=HL, dst ∈ {BC, DE}.
      //   MOV DstLo, M; INX H; MOV DstHi, M; (DCX H if HL live)
      emitMOVrM(DstLo);
      emitINXHL();
      emitMOVrM(DstHi);
      if (!isRegDeadAtMI(V6Clang::HL, MI, MBB, &RI))
        emitDCX(V6Clang::HL);
    } else if (AddrReg == V6Clang::DE && DstReg == V6Clang::DE) {
      // Case 4: addr=DE, dst=DE.
      //   XCHG; MOV Spare, M; INX H; MOV H, M; MOV L, Spare; XCHG
      //
      // Spare selection here is subtle. After the leading XCHG:
      //   HL = address     (used by the load body, must not be clobbered)
      //   DE = orig HL     (D = H_orig, E = L_orig)
      // The trailing XCHG swaps DE↔HL again, restoring orig HL into HL
      // and delivering *p (currently in HL) into DE. Whatever value is
      // sitting in D (resp. E) at the moment of XCHG #2 ends up in H
      // (resp. L) post-load. So the spare may be:
      //   B  iff B is dead across MI
      //   C  iff C is dead across MI
      //   D  iff H is dead across MI   (using D clobbers H_orig)
      //   E  iff L is dead across MI   (using E clobbers L_orig)
      //   H, L — never (they hold the address mid-sequence)
      // Falls back to A with PUSH PSW / POP PSW iff A is live.
      // No DCX D — dst=DE means caller wanted DE redefined.
      auto findCase4Spare = [&]() -> Register {
        if (isRegDeadAtMI(V6Clang::B, MI, MBB, &RI)) return Register(V6Clang::B);
        if (isRegDeadAtMI(V6Clang::C, MI, MBB, &RI)) return Register(V6Clang::C);
        if (isRegDeadAtMI(V6Clang::H, MI, MBB, &RI)) return Register(V6Clang::D);
        if (isRegDeadAtMI(V6Clang::L, MI, MBB, &RI)) return Register(V6Clang::E);
        return Register();
      };
      Register Spare = findCase4Spare();
      bool UseA = !Spare;
      MCRegister Tmp = UseA ? MCRegister(V6Clang::A) : Spare.asMCReg();
      bool ALive = UseA && !isRegDeadAtMI(V6Clang::A, MI, MBB, &RI);
      if (ALive)
        BuildMI(MBB, MI, DL, get(V6Clang::PUSH)).addReg(V6Clang::PSW);
      emitXCHG();
      emitMOVrM(Tmp);
      emitINXHL();
      emitMOVrM(V6Clang::H);
      emitMOVrr(V6Clang::L, Tmp);
      emitXCHG();
      if (ALive)
        BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::PSW);
    } else if (AddrReg == V6Clang::DE) {
      // Cases 3a / 3b: addr=DE, dst ∈ {BC, HL}.
      //   XCHG; MOV LoadLo, M; INX H; MOV LoadHi, M; XCHG; (DCX D if DE live)
      // For dst=BC: LoadLo=C, LoadHi=B (BC halves) — trailing XCHG just
      //             restores HL from the DE-stashed orig-HL.
      // For dst=HL: LoadLo=E, LoadHi=D — we cannot stage in H/L because
      //             HL holds the address after the leading XCHG. Stage
      //             in DE halves; the trailing XCHG then delivers
      //             HL ← loaded, DE ← address+1.
      MCRegister LoadLo, LoadHi;
      if (DstReg == V6Clang::HL) {
        LoadLo = V6Clang::E;
        LoadHi = V6Clang::D;
      } else {
        LoadLo = DstLo;
        LoadHi = DstHi;
      }
      emitXCHG();
      emitMOVrM(LoadLo);
      emitINXHL();
      emitMOVrM(LoadHi);
      emitXCHG();
      if (!isRegDeadAtMI(V6Clang::DE, MI, MBB, &RI))
        emitDCX(V6Clang::DE);
    } else if (DstReg == V6Clang::HL) {
      // Case 6: addr=BC, dst=HL. Two shapes; pick whichever is cheapest.
      //
      //   Shape A — M-staging (used when A is live AND a non-HL/BC GR8
      //   spare is dead, i.e. spare ∈ {D,E}). 6B / 48cc, no A traffic,
      //   BC preserved automatically:
      //     MOV H,B; MOV L,C; MOV S,M; INX H; MOV H,M; MOV L,S
      //
      //   Shape B — LDAX (otherwise). A is the staging temp; BC is
      //   corrupted by INX B and recovered with DCX B if live:
      //     [A-preserve]; LDAX B; MOV L,A; INX B; LDAX B; MOV H,A;
      //     [A-restore]; (DCX B if BC live)
      //   A-preserve = none (A dead) | PUSH PSW / POP PSW (A live, no spare).
      //   With A dead: 5B / 40cc (+1B/8cc if DCX B). With A live + no
      //   spare: 7B / 68cc (+1B/8cc if DCX B).
      //
      // No PUSH H / POP H — dst=HL means original HL is dead.
      bool ADead = isRegDeadAtMI(V6Clang::A, MI, MBB, &RI);
      Register Spare = findDeadGR8AtMI(MI, MBB, &RI, V6Clang::HL, V6Clang::BC);
      if (!ADead && Spare) {
        // Shape A.
        MCRegister Tmp = Spare.asMCReg();
        emitMOVrr(V6Clang::H, V6Clang::B);
        emitMOVrr(V6Clang::L, V6Clang::C);
        emitMOVrM(Tmp);
        emitINXHL();
        emitMOVrM(V6Clang::H);
        emitMOVrr(V6Clang::L, Tmp);
      } else {
        // Shape B.
        bool APushPop = !ADead;
        if (APushPop)
          BuildMI(MBB, MI, DL, get(V6Clang::PUSH)).addReg(V6Clang::PSW);
        BuildMI(MBB, MI, DL, get(V6Clang::LDAX), V6Clang::A).addReg(V6Clang::BC);
        emitMOVrr(V6Clang::L, V6Clang::A);
        BuildMI(MBB, MI, DL, get(V6Clang::INX), V6Clang::BC).addReg(V6Clang::BC);
        BuildMI(MBB, MI, DL, get(V6Clang::LDAX), V6Clang::A).addReg(V6Clang::BC);
        emitMOVrr(V6Clang::H, V6Clang::A);
        if (APushPop)
          BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::PSW);
        if (!isRegDeadAtMI(V6Clang::BC, MI, MBB, &RI))
          emitDCX(V6Clang::BC);
      }
    } else if (DstReg == V6Clang::BC) {
      // Case 5b: addr=BC, dst=BC. Three-tier dispatch (no DCX BC needed
      // since BC is the destination):
      //
      //   Tier 1 — HL fully dead (5B / 40cc):
      //     MOV H,B; MOV L,C; MOV C,M; INX H; MOV B,M
      //
      //   Tier 2 — A dead AND a GR8 spare (excluding BC) is dead
      //   (6B / 48cc). The spare buffers the low byte across INX B so we
      //   never write into the address pair before the second LDAX:
      //     LDAX B; MOV S,A; INX B; LDAX B; MOV B,A; MOV C,S
      //
      //   Tier 3 — worst case (7B / 68cc): PUSH H wraps tier-1 body.
      bool HLDead = isRegDeadAtMI(V6Clang::HL, MI, MBB, &RI);
      if (HLDead) {
        emitMOVrr(V6Clang::H, V6Clang::B);
        emitMOVrr(V6Clang::L, V6Clang::C);
        emitMOVrM(V6Clang::C);
        emitINXHL();
        emitMOVrM(V6Clang::B);
      } else {
        bool ADead = isRegDeadAtMI(V6Clang::A, MI, MBB, &RI);
        Register Spare =
            ADead ? findDeadGR8AtMI(MI, MBB, &RI, V6Clang::BC) : Register();
        if (Spare) {
          MCRegister Tmp = Spare.asMCReg();
          BuildMI(MBB, MI, DL, get(V6Clang::LDAX), V6Clang::A).addReg(V6Clang::BC);
          emitMOVrr(Tmp, V6Clang::A);
          BuildMI(MBB, MI, DL, get(V6Clang::INX), V6Clang::BC).addReg(V6Clang::BC);
          BuildMI(MBB, MI, DL, get(V6Clang::LDAX), V6Clang::A).addReg(V6Clang::BC);
          emitMOVrr(V6Clang::B, V6Clang::A);
          emitMOVrr(V6Clang::C, Tmp);
        } else {
          BuildMI(MBB, MI, DL, get(V6Clang::PUSH))
              .addReg(V6Clang::HL, RegState::Kill)
              .addReg(V6Clang::SP, RegState::ImplicitDefine);
          emitMOVrr(V6Clang::H, V6Clang::B);
          emitMOVrr(V6Clang::L, V6Clang::C);
          emitMOVrM(V6Clang::C);
          emitINXHL();
          emitMOVrM(V6Clang::B);
          BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::HL)
              .addReg(V6Clang::SP, RegState::ImplicitDefine);
        }
      }
    } else {
      // Case 5a: addr=BC, dst=DE. Four-way dispatch:
      //
      //   HL dead (any A) — current shape (5B / 40cc, BC preserved):
      //     MOV H,B; MOV L,C; MOV E,M; INX H; MOV D,M
      //
      //   HL live, A dead — LDAX shape (5B/40cc + 1B/8cc DCX if BC live):
      //     LDAX B; MOV E,A; INX B; LDAX B; MOV D,A; (DCX B if BC live)
      //
      //   HL live, A live, spare ∈ {H,L} dead — LDAX shape with cheap
      //   MOV-wrap A-preservation (7B / 56cc + DCX if BC live). Spare
      //   must be ≠ A, B, C, D, E so it can only come from {H, L}, and
      //   we already know one of H/L is live so the other half must be
      //   the candidate (case-4-style per-byte rule).
      //
      //   Otherwise (HL fully live, A live) — PUSH H wraps current shape
      //   (7B / 68cc, BC preserved).
      bool HLDead = isRegDeadAtMI(V6Clang::HL, MI, MBB, &RI);
      if (HLDead) {
        emitMOVrr(V6Clang::H, V6Clang::B);
        emitMOVrr(V6Clang::L, V6Clang::C);
        emitMOVrM(V6Clang::E);
        emitINXHL();
        emitMOVrM(V6Clang::D);
      } else {
        bool ADead = isRegDeadAtMI(V6Clang::A, MI, MBB, &RI);
        auto findCase5aSpare = [&]() -> Register {
          if (isRegDeadAtMI(V6Clang::H, MI, MBB, &RI)) return Register(V6Clang::H);
          if (isRegDeadAtMI(V6Clang::L, MI, MBB, &RI)) return Register(V6Clang::L);
          return Register();
        };
        Register Spare = ADead ? Register() : findCase5aSpare();
        if (ADead || Spare) {
          MCRegister Tmp;
          if (!ADead) {
            Tmp = Spare.asMCReg();
            emitMOVrr(Tmp, V6Clang::A);
          }
          BuildMI(MBB, MI, DL, get(V6Clang::LDAX), V6Clang::A).addReg(V6Clang::BC);
          emitMOVrr(V6Clang::E, V6Clang::A);
          BuildMI(MBB, MI, DL, get(V6Clang::INX), V6Clang::BC).addReg(V6Clang::BC);
          BuildMI(MBB, MI, DL, get(V6Clang::LDAX), V6Clang::A).addReg(V6Clang::BC);
          emitMOVrr(V6Clang::D, V6Clang::A);
          if (!ADead)
            emitMOVrr(V6Clang::A, Tmp);
          if (!isRegDeadAtMI(V6Clang::BC, MI, MBB, &RI))
            emitDCX(V6Clang::BC);
        } else {
          BuildMI(MBB, MI, DL, get(V6Clang::PUSH))
              .addReg(V6Clang::HL, RegState::Kill)
              .addReg(V6Clang::SP, RegState::ImplicitDefine);
          emitMOVrr(V6Clang::H, V6Clang::B);
          emitMOVrr(V6Clang::L, V6Clang::C);
          emitMOVrM(V6Clang::E);
          emitINXHL();
          emitMOVrM(V6Clang::D);
          BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::HL)
              .addReg(V6Clang::SP, RegState::ImplicitDefine);
        }
      }
    }

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_STORE16_P: {
    // O72 — Honest per-shape preservation, mirroring O71's LOAD16_P
    // redesign. The pseudo declares (ins GR16:$val, GR16:$addr) with no
    // Defs. Pre-RA passes treat the store as preserving every register
    // except memory. The expander dispatches on the (addr, val) physreg
    // pair and emits whatever cheap recovery code each shape needs.
    Register ValReg  = MI.getOperand(0).getReg();
    Register AddrReg = MI.getOperand(1).getReg();

    MCRegister ValLo = RI.getSubReg(ValReg, V6Clang::sub_lo);
    MCRegister ValHi = RI.getSubReg(ValReg, V6Clang::sub_hi);

    auto emitDCX = [&](MCRegister Pair) {
      BuildMI(MBB, MI, DL, get(V6Clang::DCX), Pair).addReg(Pair);
    };
    auto emitINXHL = [&]() {
      BuildMI(MBB, MI, DL, get(V6Clang::INX), V6Clang::HL).addReg(V6Clang::HL);
    };
    auto emitINX = [&](MCRegister Pair) {
      BuildMI(MBB, MI, DL, get(V6Clang::INX), Pair).addReg(Pair);
    };
    auto emitMOVMr = [&](MCRegister Src) {
      BuildMI(MBB, MI, DL, get(V6Clang::MOVMr)).addReg(Src);
    };
    auto emitMOVrr = [&](MCRegister Dst, MCRegister Src) {
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), Dst).addReg(Src);
    };
    auto emitXCHG = [&]() {
      BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
    };
    auto emitSTAX = [&](MCRegister Pair) {
      BuildMI(MBB, MI, DL, get(V6Clang::STAX)).addReg(V6Clang::A).addReg(Pair);
    };

    if (AddrReg == V6Clang::HL && ValReg == V6Clang::HL) {
      // Row 1: addr=HL, val=HL.
      //   MOV Spare, H; MOV M, L; INX H; MOV M, Spare; (DCX H if HL live)
      // INX H may carry from L into H, so the high byte must be parked
      // in a GR8 *before* INX. Spare candidate avoids HL (its halves are
      // the value and the address).
      Register Spare = findDeadGR8AtMI(MI, MBB, &RI, V6Clang::HL);
      bool UseA = !Spare;
      MCRegister Tmp = UseA ? MCRegister(V6Clang::A) : Spare.asMCReg();
      bool ALive = UseA && !isRegDeadAtMI(V6Clang::A, MI, MBB, &RI);
      if (ALive)
        BuildMI(MBB, MI, DL, get(V6Clang::PUSH)).addReg(V6Clang::PSW);
      emitMOVrr(Tmp, V6Clang::H);
      emitMOVMr(V6Clang::L);
      emitINXHL();
      emitMOVMr(Tmp);
      if (ALive)
        BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::PSW);
      if (!isRegDeadAtMI(V6Clang::HL, MI, MBB, &RI))
        emitDCX(V6Clang::HL);
    } else if (AddrReg == V6Clang::HL) {
      // Row 2: addr=HL, val ∈ {BC, DE}.
      //   MOV M, ValLo; INX H; MOV M, ValHi; (DCX H if HL live)
      emitMOVMr(ValLo);
      emitINXHL();
      emitMOVMr(ValHi);
      if (!isRegDeadAtMI(V6Clang::HL, MI, MBB, &RI))
        emitDCX(V6Clang::HL);
    } else if (AddrReg == V6Clang::DE && ValReg == V6Clang::DE) {
      // Row 4: addr=DE, val=DE.
      //   XCHG; MOV Spare, H; MOV M, L; INX H; MOV M, Spare; XCHG;
      //   (DCX D if DE live)
      // After leading XCHG: HL = orig DE = address (= value), DE = orig HL.
      // The body stores the two halves of the address-which-is-the-value
      // through HL. The trailing XCHG restores HL from DE; whatever sits
      // in D / E at that moment ends up in H / L. So Spare candidates:
      //   B  iff B dead;  C iff C dead;
      //   D  iff H dead   (using D would otherwise destroy H_orig);
      //   E  iff L dead   (using E would otherwise destroy L_orig);
      //   A  iff A dead   (with PUSH PSW fallback);
      //   H, L — never (they hold the address mid-sequence).
      auto findRow4Spare = [&]() -> Register {
        if (isRegDeadAtMI(V6Clang::B, MI, MBB, &RI)) return Register(V6Clang::B);
        if (isRegDeadAtMI(V6Clang::C, MI, MBB, &RI)) return Register(V6Clang::C);
        if (isRegDeadAtMI(V6Clang::H, MI, MBB, &RI)) return Register(V6Clang::D);
        if (isRegDeadAtMI(V6Clang::L, MI, MBB, &RI)) return Register(V6Clang::E);
        return Register();
      };
      Register Spare = findRow4Spare();
      bool UseA = !Spare;
      MCRegister Tmp = UseA ? MCRegister(V6Clang::A) : Spare.asMCReg();
      bool ALive = UseA && !isRegDeadAtMI(V6Clang::A, MI, MBB, &RI);
      if (ALive)
        BuildMI(MBB, MI, DL, get(V6Clang::PUSH)).addReg(V6Clang::PSW);
      emitXCHG();
      emitMOVrr(Tmp, V6Clang::H);
      emitMOVMr(V6Clang::L);
      emitINXHL();
      emitMOVMr(Tmp);
      emitXCHG();
      if (ALive)
        BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::PSW);
      if (!isRegDeadAtMI(V6Clang::DE, MI, MBB, &RI))
        emitDCX(V6Clang::DE);
    } else if (AddrReg == V6Clang::DE) {
      // Rows 3a/3b: addr=DE, val ∈ {HL, BC}.
      //   XCHG; MOV M, lo; INX H; MOV M, hi; XCHG; (DCX D if DE live)
      // For val=HL: after leading XCHG, HL = address, DE = orig HL.
      //   Body stores mem[address] = E (= L_orig = lo of val),
      //   mem[address+1] = D (= H_orig = hi of val). Trailing XCHG
      //   restores HL = orig HL, leaves DE = address+1.
      // For val=BC: BC is unaffected by XCHG. lo = C, hi = B.
      MCRegister StoreLo, StoreHi;
      if (ValReg == V6Clang::HL) {
        StoreLo = V6Clang::E;
        StoreHi = V6Clang::D;
      } else {
        StoreLo = ValLo;
        StoreHi = ValHi;
      }
      emitXCHG();
      emitMOVMr(StoreLo);
      emitINXHL();
      emitMOVMr(StoreHi);
      emitXCHG();
      if (!isRegDeadAtMI(V6Clang::DE, MI, MBB, &RI))
        emitDCX(V6Clang::DE);
    } else if (ValReg != V6Clang::BC) {
      // Row 5: addr=BC, val ∈ {HL, DE}.
      //   [MOV Spare, A | PUSH PSW]    if A live
      //   MOV A, lo; STAX B; INX B; MOV A, hi; STAX B
      //   [MOV A, Spare | POP PSW]
      //   (DCX B if BC live)
      // STAX rp only accepts A as source. The Spare exclusion set is
      // {A, BC, ValReg}: the body reads both halves of the value via
      // MOV A, lo / MOV A, hi, and writes/reads BC via STAX/INX, so the
      // save target must survive the body unchanged.
      bool ALive = !isRegDeadAtMI(V6Clang::A, MI, MBB, &RI);
      Register Spare;
      if (ALive)
        Spare = findDeadGR8AtMI(MI, MBB, &RI, V6Clang::BC, ValReg);
      bool UsePush = ALive && !Spare;
      if (Spare)
        emitMOVrr(Spare.asMCReg(), V6Clang::A);
      else if (UsePush)
        BuildMI(MBB, MI, DL, get(V6Clang::PUSH)).addReg(V6Clang::PSW);
      emitMOVrr(V6Clang::A, ValLo);
      emitSTAX(V6Clang::BC);
      emitINX(V6Clang::BC);
      emitMOVrr(V6Clang::A, ValHi);
      emitSTAX(V6Clang::BC);
      if (Spare)
        emitMOVrr(V6Clang::A, Spare.asMCReg());
      else if (UsePush)
        BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::PSW);
      if (!isRegDeadAtMI(V6Clang::BC, MI, MBB, &RI))
        emitDCX(V6Clang::BC);
    } else {
      // Row 6: addr=BC, val=BC. Three-tier dispatch on HL liveness and
      // GR8 spare availability:
      //   6a — HL dead: use HL as scratch, no restore.
      //   6b — HL live, GR8 spare available: STAX-body with A saved into
      //        the spare (HL untouched).
      //   6c — HL live, no GR8 spare: PUSH H / scratch body / POP H.
      bool HLDead = isRegDeadAtMI(V6Clang::HL, MI, MBB, &RI);
      bool BCLive = !isRegDeadAtMI(V6Clang::BC, MI, MBB, &RI);

      if (HLDead) {
        // 6a — 5B / 40cc.
        emitMOVrr(V6Clang::H, V6Clang::B);
        emitMOVrr(V6Clang::L, V6Clang::C);
        emitMOVMr(V6Clang::C);
        emitINXHL();
        emitMOVMr(V6Clang::B);
        if (BCLive)
          emitDCX(V6Clang::BC);
      } else {
        // HL live.  Body reads both halves of BC, so Spare must exclude
        // BC. A is excluded automatically by findDeadGR8AtMI.
        Register Spare = findDeadGR8AtMI(MI, MBB, &RI, V6Clang::BC);
        if (Spare) {
          // 6b — STAX body, save A into Spare. HL untouched.
          bool ALive = !isRegDeadAtMI(V6Clang::A, MI, MBB, &RI);
          if (ALive)
            emitMOVrr(Spare.asMCReg(), V6Clang::A);
          emitMOVrr(V6Clang::A, V6Clang::C);
          emitSTAX(V6Clang::BC);
          emitINX(V6Clang::BC);
          emitMOVrr(V6Clang::A, V6Clang::B);
          emitSTAX(V6Clang::BC);
          if (ALive)
            emitMOVrr(V6Clang::A, Spare.asMCReg());
          if (BCLive)
            emitDCX(V6Clang::BC);
        } else {
          // 6c — PUSH H / scratch body / POP H.
          BuildMI(MBB, MI, DL, get(V6Clang::PUSH))
              .addReg(V6Clang::HL, RegState::Kill)
              .addReg(V6Clang::SP, RegState::ImplicitDefine);
          emitMOVrr(V6Clang::H, V6Clang::B);
          emitMOVrr(V6Clang::L, V6Clang::C);
          emitMOVMr(V6Clang::C);
          emitINXHL();
          emitMOVMr(V6Clang::B);
          BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::HL)
              .addReg(V6Clang::SP, RegState::ImplicitDefine);
          if (BCLive)
            emitDCX(V6Clang::BC);
        }
      }
    }

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_LOAD16_G: {
    // Load 16-bit from global address. O73: per-shape, liveness-aware.
    //   dst=HL: LHLD addr                                   (3B / 20cc)
    //   dst=DE: XCHG; LHLD addr; XCHG                       (5B / 28cc)
    //   dst=BC, HL dead:    LHLD; MOV B,H; MOV C,L          (5B / 36cc)
    //   dst=BC, A dead:     LDA; MOV C,A; LDA+1; MOV B,A    (8B / 48cc)
    //   dst=BC, fallback:   PUSH H; LHLD; MOVs; POP H       (7B / 64cc)
    Register DstReg = MI.getOperand(0).getReg();
    MachineOperand &AddrOp = MI.getOperand(1);

    auto emitLHLD = [&](MachineBasicBlock::iterator InsertPt) {
      auto MIB = BuildMI(MBB, InsertPt, DL, get(V6Clang::LHLD), V6Clang::HL);
      if (AddrOp.isGlobal())
        MIB.addGlobalAddress(AddrOp.getGlobal(), AddrOp.getOffset());
      else
        MIB.addImm(AddrOp.getImm());
    };

    if (DstReg == V6Clang::HL) {
      emitLHLD(MI);
    } else if (DstReg == V6Clang::DE) {
      // dst=DE, HL dead: LHLD addr; XCHG (4B / 24cc).
      //   HL is scratch — LHLD overwrites it, XCHG moves loaded value
      //   into DE; HL ends up holding old DE which is dead anyway.
      // dst=DE, HL live: XCHG; LHLD addr; XCHG (5B / 28cc).
      //   First XCHG saves HL into DE (the value brought into HL by
      //   the first XCHG is dead, since the second XCHG overwrites HL
      //   with the loaded value). If DE wasn't live before, annotate
      //   the first XCHG's DE read as undef.
      if (isRegDeadAtMI(V6Clang::HL, MI, MBB, &RI)) {
        emitLHLD(MI);
        BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
      } else {
        MachineInstr *FirstXchg =
            BuildMI(MBB, MI, DL, get(V6Clang::XCHG)).getInstr();
        emitLHLD(MI);
        BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
        if (!isRegLiveBefore(MBB, FirstXchg->getIterator(), V6Clang::DE, &RI))
          markXchgUseUndef(FirstXchg, V6Clang::DE);
      }
    } else {
      // BC: three-way dispatch on (HLDead, ADead). See O73 design.
      MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
      MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);

      bool HLDead = isRegDeadAtMI(V6Clang::HL, MI, MBB, &RI);
      bool ADead  = isRegDeadAtMI(V6Clang::A, MI, MBB, &RI);

      if (HLDead) {
        // 5B / 36cc: LHLD addr; MOV B,H; MOV C,L (HL is scratch).
        emitLHLD(MI);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::H);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::L);
      } else if (ADead) {
        // 8B / 48cc: LDA addr; MOV C,A; LDA addr+1; MOV B,A.
        // Preserves HL — strictly cheaper than PUSH/POP wrap (−16cc, +1B).
        auto emitLDA = [&](int64_t Bias) {
          auto MIB = BuildMI(MBB, MI, DL, get(V6Clang::LDA), V6Clang::A);
          if (AddrOp.isGlobal())
            MIB.addGlobalAddress(AddrOp.getGlobal(),
                                 AddrOp.getOffset() + Bias);
          else
            MIB.addImm(AddrOp.getImm() + Bias);
        };
        emitLDA(0);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::A);
        emitLDA(1);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::A);
      } else {
        // 7B / 64cc fallback: PUSH H; LHLD; MOV B,H; MOV C,L; POP H.
        BuildMI(MBB, MI, DL, get(V6Clang::PUSH))
            .addReg(V6Clang::HL, RegState::Kill)
            .addReg(V6Clang::SP, RegState::ImplicitDefine);
        emitLHLD(MI);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::H);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::L);
        BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::HL)
            .addReg(V6Clang::SP, RegState::ImplicitDefine);
      }
    }

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_STORE16_G: {
    // Store 16-bit to global address. O74: per-shape, liveness-aware.
    //   val=HL:                 SHLD addr                            (3B / 20cc)
    //   val=DE, HL dead:        XCHG; SHLD addr                      (4B / 24cc)
    //   val=DE, fallback:       XCHG; SHLD addr; XCHG                (5B / 28cc)
    //   val=BC, HL dead:        MOV H,B; MOV L,C; SHLD addr          (5B / 36cc)
    //   val=BC, A dead:         MOV A,C; STA; MOV A,B; STA+1         (8B / 48cc)
    //   val=BC, fallback:       PUSH H; MOV H,B; MOV L,C; SHLD; POP H (7B / 64cc)
    Register ValReg = MI.getOperand(0).getReg();
    MachineOperand &AddrOp = MI.getOperand(1);

    auto emitSHLD = [&]() {
      auto MIB = BuildMI(MBB, MI, DL, get(V6Clang::SHLD)).addReg(V6Clang::HL);
      if (AddrOp.isGlobal())
        MIB.addGlobalAddress(AddrOp.getGlobal(), AddrOp.getOffset());
      else
        MIB.addImm(AddrOp.getImm());
    };

    if (ValReg == V6Clang::HL) {
      emitSHLD();
    } else if (ValReg == V6Clang::DE) {
      bool HLDead = isRegDeadAtMI(V6Clang::HL, MI, MBB, &RI);
      BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
      emitSHLD();
      if (!HLDead)
        BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
    } else {
      // val=BC: three-way dispatch on (HLDead, ADead).
      bool HLDead = isRegDeadAtMI(V6Clang::HL, MI, MBB, &RI);
      bool ADead  = isRegDeadAtMI(V6Clang::A,  MI, MBB, &RI);

      if (HLDead) {
        // 5B / 36cc: MOV H,B; MOV L,C; SHLD addr.
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::H).addReg(V6Clang::B);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::L).addReg(V6Clang::C);
        emitSHLD();
      } else if (ADead) {
        // 8B / 48cc: MOV A,C; STA addr; MOV A,B; STA addr+1.
        // Preserves HL — strictly cheaper than PUSH/POP wrap (−16cc, +1B).
        auto emitSTA = [&](int64_t Bias) {
          auto MIB = BuildMI(MBB, MI, DL, get(V6Clang::STA)).addReg(V6Clang::A);
          if (AddrOp.isGlobal())
            MIB.addGlobalAddress(AddrOp.getGlobal(),
                                 AddrOp.getOffset() + Bias);
          else
            MIB.addImm(AddrOp.getImm() + Bias);
        };
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(V6Clang::C);
        emitSTA(0);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(V6Clang::B);
        emitSTA(1);
      } else {
        // 7B / 64cc fallback: PUSH H; MOV H,B; MOV L,C; SHLD; POP H.
        BuildMI(MBB, MI, DL, get(V6Clang::PUSH))
            .addReg(V6Clang::HL, RegState::Kill)
            .addReg(V6Clang::SP, RegState::ImplicitDefine);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::H).addReg(V6Clang::B);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::L).addReg(V6Clang::C);
        emitSHLD();
        BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::HL)
            .addReg(V6Clang::SP, RegState::ImplicitDefine);
      }
    }

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_SHL16_DAD: {
    // Left shift i16 by 1..7 via repeated DAD H.
    Register DstReg = MI.getOperand(0).getReg();
    Register SrcReg = MI.getOperand(1).getReg();
    unsigned ShAmt = MI.getOperand(2).getImm();

    bool HLDead = isRegDeadAfter(MBB, MI.getIterator(), V6Clang::H, &RI) &&
                  isRegDeadAfter(MBB, MI.getIterator(), V6Clang::L, &RI);

    if (DstReg == V6Clang::DE && SrcReg == V6Clang::DE) {
      BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
      for (unsigned i = 0; i < ShAmt; ++i)
        BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(V6Clang::HL);
      BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
      MI.eraseFromParent();
      return true;
    }

    bool PreserveHL = DstReg != V6Clang::HL && !HLDead;
    if (PreserveHL)
      BuildMI(MBB, MI, DL, get(V6Clang::PUSH)).addReg(V6Clang::HL);
    if (SrcReg != V6Clang::HL)
      copyPhysReg(MBB, MI, DL, V6Clang::HL, SrcReg, /*KillSrc=*/false);
    for (unsigned i = 0; i < ShAmt; ++i)
      BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(V6Clang::HL);
    if (DstReg != V6Clang::HL)
      copyPhysReg(MBB, MI, DL, DstReg, V6Clang::HL, /*KillSrc=*/false);
    if (PreserveHL)
      BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::HL);

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_SHL16_BYTE: {
    // Left shift i16 by 8 via byte-lane move.
    Register DstReg = MI.getOperand(0).getReg();
    Register SrcReg = MI.getOperand(1).getReg();

    MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);
    MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
    MCRegister SrcLo = RI.getSubReg(SrcReg, V6Clang::sub_lo);

    if (DstHi != SrcLo)
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(SrcLo);
    BuildMI(MBB, MI, DL, get(V6Clang::MVIr), DstLo).addImm(0);

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_SHL16_RAM_HI: {
    // Left shift i16 by 9..15 via byte-lane move plus A-domain byte work.
    // 9..13 use repeated ADD A; 14..15 use the rotate-and-mask form.
    Register DstReg = MI.getOperand(0).getReg();
    Register SrcReg = MI.getOperand(1).getReg();
    unsigned ShAmt = MI.getOperand(2).getImm();

    MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);
    MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
    MCRegister SrcLo = RI.getSubReg(SrcReg, V6Clang::sub_lo);

    unsigned TailAmt = ShAmt - 8;
    if (TailAmt >= 6) {
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(SrcLo);
      for (unsigned i = 0; i < 16 - ShAmt; ++i)
        BuildMI(MBB, MI, DL, get(V6Clang::RRC), V6Clang::A).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::ANI), V6Clang::A)
          .addReg(V6Clang::A)
          .addImm(ShAmt == 14 ? 0xC0 : 0x80);
      BuildMI(MBB, MI, DL, get(V6Clang::MVIr), DstLo).addImm(0);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::A);
    } else {
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(SrcLo);
      for (unsigned i = 0; i < TailAmt; ++i)
        BuildMI(MBB, MI, DL, get(V6Clang::ADDr), V6Clang::A)
            .addReg(V6Clang::A).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::MVIr), DstLo).addImm(0);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::A);
    }

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_SRL16_RAR: {
    // Logical right shift i16 by 1..2 via the per-bit RAR loop.
    Register DstReg = MI.getOperand(0).getReg();
    Register SrcReg = MI.getOperand(1).getReg();
    unsigned ShAmt = MI.getOperand(2).getImm();

    MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);
    MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
    MCRegister SrcHi = RI.getSubReg(SrcReg, V6Clang::sub_hi);
    MCRegister SrcLo = RI.getSubReg(SrcReg, V6Clang::sub_lo);

    if (DstReg != SrcReg) {
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(SrcHi);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(SrcLo);
    }
    bool CYClear = priorClearsCarry(MBB, MI);
    for (unsigned i = 0; i < ShAmt; ++i) {
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(DstHi);
      if (!CYClear)
        BuildMI(MBB, MI, DL, get(V6Clang::ORAr), V6Clang::A)
            .addReg(V6Clang::A).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::RAR), V6Clang::A).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(DstLo);
      BuildMI(MBB, MI, DL, get(V6Clang::RAR), V6Clang::A).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::A);
      CYClear = false;
    }

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_SRL16_24BIT: {
    // Logical right shift i16 by 3..7 via the 24-bit DAD/ADC trick.
    Register DstReg = MI.getOperand(0).getReg();
    Register SrcReg = MI.getOperand(1).getReg();
    unsigned ShAmt = MI.getOperand(2).getImm();

    bool HLDead = isRegDeadAfter(MBB, MI.getIterator(), V6Clang::H, &RI) &&
                  isRegDeadAfter(MBB, MI.getIterator(), V6Clang::L, &RI);

    if (DstReg == V6Clang::DE && SrcReg == V6Clang::DE) {
      BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
      BuildMI(MBB, MI, DL, get(V6Clang::XRAr), V6Clang::A)
          .addReg(V6Clang::A).addReg(V6Clang::A);
      for (unsigned i = 0; i < 8 - ShAmt; ++i) {
        BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(V6Clang::HL);
        BuildMI(MBB, MI, DL, get(V6Clang::ADCr), V6Clang::A)
            .addReg(V6Clang::A).addReg(V6Clang::A);
      }
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::L).addReg(V6Clang::H);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::H).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
      MI.eraseFromParent();
      return true;
    }

    bool PreserveHL = DstReg != V6Clang::HL && !HLDead;
    if (PreserveHL)
      BuildMI(MBB, MI, DL, get(V6Clang::PUSH)).addReg(V6Clang::HL);
    if (SrcReg != V6Clang::HL)
      copyPhysReg(MBB, MI, DL, V6Clang::HL, SrcReg, /*KillSrc=*/false);
    BuildMI(MBB, MI, DL, get(V6Clang::XRAr), V6Clang::A)
        .addReg(V6Clang::A).addReg(V6Clang::A);
    for (unsigned i = 0; i < 8 - ShAmt; ++i) {
      BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(V6Clang::HL);
      BuildMI(MBB, MI, DL, get(V6Clang::ADCr), V6Clang::A)
          .addReg(V6Clang::A).addReg(V6Clang::A);
    }
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::L).addReg(V6Clang::H);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::H).addReg(V6Clang::A);
    if (DstReg != V6Clang::HL)
      copyPhysReg(MBB, MI, DL, DstReg, V6Clang::HL, /*KillSrc=*/false);
    if (PreserveHL)
      BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::HL);

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_SRL16_BYTE: {
    // Logical right shift i16 by 8 via byte-lane move.
    Register DstReg = MI.getOperand(0).getReg();
    Register SrcReg = MI.getOperand(1).getReg();

    MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);
    MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
    MCRegister SrcHi = RI.getSubReg(SrcReg, V6Clang::sub_hi);

    if (DstLo != SrcHi)
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(SrcHi);
    BuildMI(MBB, MI, DL, get(V6Clang::MVIr), DstHi).addImm(0);

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_SRL16_RAM_LO: {
    // Logical right shift i16 by 9..15 via rotate-and-mask.
    Register DstReg = MI.getOperand(0).getReg();
    Register SrcReg = MI.getOperand(1).getReg();
    unsigned ShAmt = MI.getOperand(2).getImm();

    MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);
    MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
    MCRegister SrcHi = RI.getSubReg(SrcReg, V6Clang::sub_hi);

    unsigned TailAmt = ShAmt - 8;
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(SrcHi);
    if (TailAmt <= 4) {
      for (unsigned i = 0; i < TailAmt; ++i)
        BuildMI(MBB, MI, DL, get(V6Clang::RRC), V6Clang::A).addReg(V6Clang::A);
    } else {
      for (unsigned i = 0; i < 8 - TailAmt; ++i)
        BuildMI(MBB, MI, DL, get(V6Clang::RLC), V6Clang::A).addReg(V6Clang::A);
    }
    BuildMI(MBB, MI, DL, get(V6Clang::ANI), V6Clang::A)
        .addReg(V6Clang::A)
        .addImm((1u << (16 - ShAmt)) - 1u);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::A);
    BuildMI(MBB, MI, DL, get(V6Clang::MVIr), DstHi).addImm(0);

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_SRA16_RAR: {
    // Arithmetic right shift i16 by 1..2 via the per-bit RAR loop.
    Register DstReg = MI.getOperand(0).getReg();
    Register SrcReg = MI.getOperand(1).getReg();
    unsigned ShAmt = MI.getOperand(2).getImm();

    MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);
    MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
    MCRegister SrcHi = RI.getSubReg(SrcReg, V6Clang::sub_hi);
    MCRegister SrcLo = RI.getSubReg(SrcReg, V6Clang::sub_lo);

    if (DstReg != SrcReg) {
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(SrcHi);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(SrcLo);
    }
    for (unsigned i = 0; i < ShAmt; ++i) {
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(DstHi);
      BuildMI(MBB, MI, DL, get(V6Clang::RLC), V6Clang::A)
          .addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(DstHi);
      BuildMI(MBB, MI, DL, get(V6Clang::RAR), V6Clang::A)
          .addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(DstLo);
      BuildMI(MBB, MI, DL, get(V6Clang::RAR), V6Clang::A)
          .addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::A);
    }

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_SRA16_24BIT: {
    // Arithmetic right shift i16 by 3..7 via the sign-seeded 24-bit trick.
    Register DstReg = MI.getOperand(0).getReg();
    Register SrcReg = MI.getOperand(1).getReg();
    unsigned ShAmt = MI.getOperand(2).getImm();

    bool HLDead = isRegDeadAfter(MBB, MI.getIterator(), V6Clang::H, &RI) &&
                  isRegDeadAfter(MBB, MI.getIterator(), V6Clang::L, &RI);

    if (DstReg == V6Clang::DE && SrcReg == V6Clang::DE) {
      BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(V6Clang::H);
      BuildMI(MBB, MI, DL, get(V6Clang::RLC), V6Clang::A).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::SBBr), V6Clang::A)
          .addReg(V6Clang::A).addReg(V6Clang::A);
      for (unsigned i = 0; i < 8 - ShAmt; ++i) {
        BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(V6Clang::HL);
        BuildMI(MBB, MI, DL, get(V6Clang::ADCr), V6Clang::A)
            .addReg(V6Clang::A).addReg(V6Clang::A);
      }
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::L).addReg(V6Clang::H);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::H).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
      MI.eraseFromParent();
      return true;
    }

    bool PreserveHL = DstReg != V6Clang::HL && !HLDead;
    if (PreserveHL)
      BuildMI(MBB, MI, DL, get(V6Clang::PUSH)).addReg(V6Clang::HL);
    if (SrcReg != V6Clang::HL)
      copyPhysReg(MBB, MI, DL, V6Clang::HL, SrcReg, /*KillSrc=*/false);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(V6Clang::H);
    BuildMI(MBB, MI, DL, get(V6Clang::RLC), V6Clang::A).addReg(V6Clang::A);
    BuildMI(MBB, MI, DL, get(V6Clang::SBBr), V6Clang::A)
        .addReg(V6Clang::A).addReg(V6Clang::A);
    for (unsigned i = 0; i < 8 - ShAmt; ++i) {
      BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(V6Clang::HL);
      BuildMI(MBB, MI, DL, get(V6Clang::ADCr), V6Clang::A)
          .addReg(V6Clang::A).addReg(V6Clang::A);
    }
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::L).addReg(V6Clang::H);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::H).addReg(V6Clang::A);
    if (DstReg != V6Clang::HL)
      copyPhysReg(MBB, MI, DL, DstReg, V6Clang::HL, /*KillSrc=*/false);
    if (PreserveHL)
      BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::HL);

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_SRA16_BYTE: {
    // Arithmetic right shift i16 by 8 via byte-lane move plus sign splat.
    Register DstReg = MI.getOperand(0).getReg();
    Register SrcReg = MI.getOperand(1).getReg();

    MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);
    MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
    MCRegister SrcHi = RI.getSubReg(SrcReg, V6Clang::sub_hi);

    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(SrcHi);
    if (DstLo != SrcHi)
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(SrcHi);
    BuildMI(MBB, MI, DL, get(V6Clang::RLC), V6Clang::A).addReg(V6Clang::A);
    BuildMI(MBB, MI, DL, get(V6Clang::SBBr), V6Clang::A)
        .addReg(V6Clang::A).addReg(V6Clang::A);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::A);

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_SRA16_RAM_LO: {
    // Arithmetic right shift i16 by 9..15.
    // Keep the older byte-lane + one-step form for >>9; collapse >>15 to a
    // direct sign splat; use rotate-and-mask plus sign-fill for the rest.
    Register DstReg = MI.getOperand(0).getReg();
    Register SrcReg = MI.getOperand(1).getReg();
    unsigned ShAmt = MI.getOperand(2).getImm();

    MCRegister DstHi = RI.getSubReg(DstReg, V6Clang::sub_hi);
    MCRegister DstLo = RI.getSubReg(DstReg, V6Clang::sub_lo);
    MCRegister SrcHi = RI.getSubReg(SrcReg, V6Clang::sub_hi);
    bool DstHiDead = isRegDeadAfter(MBB, MI.getIterator(), DstHi, &RI);

    unsigned TailAmt = ShAmt - 8;
    if (TailAmt == 1) {
      if (DstHiDead) {
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(SrcHi);
        BuildMI(MBB, MI, DL, get(V6Clang::RLC), V6Clang::A).addReg(V6Clang::A);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(SrcHi);
        BuildMI(MBB, MI, DL, get(V6Clang::RAR), V6Clang::A).addReg(V6Clang::A);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::A);
        MI.eraseFromParent();
        return true;
      }

      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(SrcHi);
      if (DstLo != SrcHi)
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(SrcHi);
      BuildMI(MBB, MI, DL, get(V6Clang::RLC), V6Clang::A).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::SBBr), V6Clang::A)
          .addReg(V6Clang::A).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(DstLo);
      BuildMI(MBB, MI, DL, get(V6Clang::RLC), V6Clang::A).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(DstLo);
      BuildMI(MBB, MI, DL, get(V6Clang::RAR), V6Clang::A).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::A);
      MI.eraseFromParent();
      return true;
    }

    if (TailAmt == 7) {
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(SrcHi);
      BuildMI(MBB, MI, DL, get(V6Clang::RLC), V6Clang::A).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::SBBr), V6Clang::A)
          .addReg(V6Clang::A).addReg(V6Clang::A);
      if (!DstHiDead)
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::A);
      MI.eraseFromParent();
      return true;
    }

    if (DstHiDead) {
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(SrcHi);
      if (TailAmt <= 4) {
        for (unsigned i = 0; i < TailAmt; ++i)
          BuildMI(MBB, MI, DL, get(V6Clang::RRC), V6Clang::A).addReg(V6Clang::A);
      } else {
        for (unsigned i = 0; i < 8 - TailAmt; ++i)
          BuildMI(MBB, MI, DL, get(V6Clang::RLC), V6Clang::A).addReg(V6Clang::A);
      }
      BuildMI(MBB, MI, DL, get(V6Clang::ANI), V6Clang::A)
          .addReg(V6Clang::A)
          .addImm((1u << (8 - TailAmt)) - 1u);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::A);

      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(SrcHi);
      BuildMI(MBB, MI, DL, get(V6Clang::RLC), V6Clang::A).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::SBBr), V6Clang::A)
          .addReg(V6Clang::A).addReg(V6Clang::A);
      BuildMI(MBB, MI, DL, get(V6Clang::ANI), V6Clang::A)
          .addReg(V6Clang::A)
          .addImm((0xFFu << (8 - TailAmt)) & 0xFFu);
      BuildMI(MBB, MI, DL, get(V6Clang::ORAr), V6Clang::A)
          .addReg(V6Clang::A).addReg(DstLo);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::A);

      MI.eraseFromParent();
      return true;
    }

    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(SrcHi);
    if (TailAmt <= 4) {
      for (unsigned i = 0; i < TailAmt; ++i)
        BuildMI(MBB, MI, DL, get(V6Clang::RRC), V6Clang::A).addReg(V6Clang::A);
    } else {
      for (unsigned i = 0; i < 8 - TailAmt; ++i)
        BuildMI(MBB, MI, DL, get(V6Clang::RLC), V6Clang::A).addReg(V6Clang::A);
    }
    BuildMI(MBB, MI, DL, get(V6Clang::ANI), V6Clang::A)
        .addReg(V6Clang::A)
        .addImm((1u << (8 - TailAmt)) - 1u);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::A);

    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(SrcHi);
    BuildMI(MBB, MI, DL, get(V6Clang::RLC), V6Clang::A).addReg(V6Clang::A);
    BuildMI(MBB, MI, DL, get(V6Clang::SBBr), V6Clang::A)
        .addReg(V6Clang::A).addReg(V6Clang::A);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstHi).addReg(V6Clang::A);
    BuildMI(MBB, MI, DL, get(V6Clang::ANI), V6Clang::A)
        .addReg(V6Clang::A)
        .addImm((0xFFu << (8 - TailAmt)) & 0xFFu);
    BuildMI(MBB, MI, DL, get(V6Clang::ORAr), V6Clang::A)
        .addReg(V6Clang::A).addReg(DstLo);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), DstLo).addReg(V6Clang::A);

    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_ROTL16_1: {
    // O68 Phase 2: rotl i16 x, 1
    //   DAD H        ; HL <<= 1, CY = old bit 15      (10cc, 1B)
    //   MVI A, 0     ; (does not touch flags — CY preserved) ( 7cc, 2B)
    //   ADC L        ; A = 0 + L + CY = L | CY        ( 4cc, 1B)
    //   MOV L, A     ;                                ( 5cc, 1B)
    // GR16Ptr / tied $dst=$src guarantees Dst == Src == HL post-RA,
    // so no framing is needed. Total: 4 instr / 5B / 26cc, A clobbered
    // (matches today's expand semantics). MVI A,0 chosen over MOV A,L
    // + ACI 0 to break the L→A→A dep chain and save 1cc.
    BuildMI(MBB, MI, DL, get(V6Clang::DAD)).addReg(V6Clang::HL);
    BuildMI(MBB, MI, DL, get(V6Clang::MVIr), V6Clang::A).addImm(0);
    BuildMI(MBB, MI, DL, get(V6Clang::ADCr), V6Clang::A).addReg(V6Clang::A).addReg(V6Clang::L);
    BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::L).addReg(V6Clang::A);
    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_LOAD8_P: {
    // HL-preserving expansion with 4-priority chain.
    Register DstReg = MI.getOperand(0).getReg();
    Register AddrReg = MI.getOperand(1).getReg();

    if (AddrReg == V6Clang::HL) {
      // Priority 1: addr is HL — just load (7cc)
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrM))
          .addReg(DstReg, RegState::Define);
    } else if (DstReg == V6Clang::A &&
               (AddrReg == V6Clang::BC || AddrReg == V6Clang::DE)) {
      // Priority 2: LDAX — dst is A (7cc)
      BuildMI(MBB, MI, DL, get(V6Clang::LDAX))
          .addReg(DstReg, RegState::Define)
          .addReg(AddrReg);
    } else if ((AddrReg == V6Clang::BC || AddrReg == V6Clang::DE) &&
               isRegDeadAtMI(V6Clang::A, MI, MBB, &RI)) {
      // Priority 3: LDAX then move — A is dead (12cc)
      BuildMI(MBB, MI, DL, get(V6Clang::LDAX))
          .addReg(V6Clang::A, RegState::Define)
          .addReg(AddrReg);
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr))
          .addReg(DstReg, RegState::Define).addReg(V6Clang::A);
    } else {
      // Priority 4: AddrReg ∈ {BC, DE}, DstReg != A. O76 — three-way
      // dispatch on (AddrReg, A-liveness, dead-GR8 availability):
      //   7  : addr=DE, A live           → XCHG bypass        (3B/16cc)
      //   6a : addr=BC, A live, SpareR   → SpareR-A envelope  (4B/32cc)
      //   6b : addr=BC, A live, no spare → PSW-wrap fallback  (4B/44cc)
      //   4/5: A dead                    → LDAX + MOV         (2B/16cc)
      bool ALive = !isRegDeadAtMI(V6Clang::A, MI, MBB, &RI);

      // partner(dst) = XCHG image of dst. After `XCHG; MOV r,M; XCHG`
      // the byte loaded into `partnerOf(dst)` ends up in `dst`. Correct
      // for every non-A dst:
      //   - dst ∈ {B, C, H, L}: bypass preserves DE.
      //   - dst ∈ {D, E}      : bypass clobbers DE, but RA's
      //     subreg-def-kills-superreg-use invariant guarantees DE is
      //     dead-after the pseudo whenever it allocates dst ∈ {D, E}
      //     for addr=DE. See plan_O76_V6CLANG_LOAD8_P_redesign.md.
      auto partnerOf = [](Register R) -> Register {
        switch (R) {
        case V6Clang::B: return V6Clang::B;
        case V6Clang::C: return V6Clang::C;
        case V6Clang::H: return V6Clang::D;
        case V6Clang::L: return V6Clang::E;
        case V6Clang::D: return V6Clang::H;
        case V6Clang::E: return V6Clang::L;
        default:     return Register();
        }
      };

      if (ALive && AddrReg == V6Clang::DE) {
        // 7: XCHG bypass. 3B / 16cc, unconditional for any non-A dst.
        BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrM))
            .addReg(partnerOf(DstReg), RegState::Define);
        BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
      } else if (ALive) {
        // 6a / 6b: addr=BC, A live. Try SpareR-A first (saves 12cc vs
        // PSW-wrap, same byte count). Exclude A and DstReg — SpareR
        // must survive the post-LDAX `MOV dst,A`.
        Register SpareR = findDeadGR8AtMI(MI, MBB, &RI,
                                          /*Exclude1=*/V6Clang::A,
                                          /*Exclude2=*/DstReg);
        if (SpareR) {
          // 6a: MOV spareR,A; LDAX; MOV dst,A; MOV A,spareR.
          BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), SpareR).addReg(V6Clang::A);
          BuildMI(MBB, MI, DL, get(V6Clang::LDAX))
              .addReg(V6Clang::A, RegState::Define).addReg(AddrReg);
          BuildMI(MBB, MI, DL, get(V6Clang::MOVrr))
              .addReg(DstReg, RegState::Define).addReg(V6Clang::A);
          BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(SpareR);
        } else {
          // 6b: PUSH PSW; LDAX; MOV dst,A; POP PSW (legacy fallback).
          BuildMI(MBB, MI, DL, get(V6Clang::PUSH)).addReg(V6Clang::PSW);
          BuildMI(MBB, MI, DL, get(V6Clang::LDAX))
              .addReg(V6Clang::A, RegState::Define).addReg(AddrReg);
          BuildMI(MBB, MI, DL, get(V6Clang::MOVrr))
              .addReg(DstReg, RegState::Define).addReg(V6Clang::A);
          BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::PSW);
        }
      } else {
        // 4 / 5: A dead — plain LDAX + MOV.
        BuildMI(MBB, MI, DL, get(V6Clang::LDAX))
            .addReg(V6Clang::A, RegState::Define).addReg(AddrReg);
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr))
            .addReg(DstReg, RegState::Define).addReg(V6Clang::A);
      }
    }
    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_STORE8_P: {
    // HL-preserving expansion with 4-priority chain.
    Register SrcReg = MI.getOperand(0).getReg();
    Register AddrReg = MI.getOperand(1).getReg();

    if (AddrReg == V6Clang::HL) {
      // Priority 1: addr is HL — just store (7cc)
      BuildMI(MBB, MI, DL, get(V6Clang::MOVMr)).addReg(SrcReg);
    } else if (SrcReg == V6Clang::A &&
               (AddrReg == V6Clang::BC || AddrReg == V6Clang::DE)) {
      // Priority 2: STAX — src already in A (7cc)
      BuildMI(MBB, MI, DL, get(V6Clang::STAX))
          .addReg(SrcReg).addReg(AddrReg);
    } else if ((AddrReg == V6Clang::BC || AddrReg == V6Clang::DE) &&
               isRegDeadAtMI(V6Clang::A, MI, MBB, &RI)) {
      // Priority 3: route through A for STAX — A is dead (12cc)
      BuildMI(MBB, MI, DL, get(V6Clang::MOVrr))
          .addReg(V6Clang::A, RegState::Define).addReg(SrcReg);
      BuildMI(MBB, MI, DL, get(V6Clang::STAX))
          .addReg(V6Clang::A).addReg(AddrReg);
    } else {
      // Priority 4: AddrReg ∈ {BC, DE}, SrcReg != A. O77 — three-way
      // dispatch on (AddrReg, A-liveness, dead-GR8 availability):
      //   7  : addr=DE, A live           → XCHG bypass        (3B/16cc)
      //   6a : addr=BC, A live, SpareR   → SpareR-A envelope  (4B/32cc)
      //   6b : addr=BC, A live, no spare → PSW-wrap fallback  (4B/44cc)
      //   4/5: A dead                    → MOV A,src + STAX   (2B/16cc)
      bool ALive = !isRegDeadAtMI(V6Clang::A, MI, MBB, &RI);

      // partner(src) = XCHG image of src. After `XCHG; MOV M,r; XCHG`
      // the byte stored is the value originally in `src` for every
      // non-A src — the body MOV M,r only reads a register and writes
      // memory, so the trailing XCHG fully restores DE. Unlike the
      // load (O76), there is no `src ∈ {D, E}` edge case.
      auto partnerOf = [](Register R) -> Register {
        switch (R) {
        case V6Clang::B: return V6Clang::B;
        case V6Clang::C: return V6Clang::C;
        case V6Clang::H: return V6Clang::D;
        case V6Clang::L: return V6Clang::E;
        case V6Clang::D: return V6Clang::H;
        case V6Clang::E: return V6Clang::L;
        default:     return Register();
        }
      };

      if (ALive && AddrReg == V6Clang::DE) {
        // 7: XCHG bypass. 3B / 16cc, unconditional for any non-A src.
        BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
        BuildMI(MBB, MI, DL, get(V6Clang::MOVMr))
            .addReg(partnerOf(SrcReg));
        BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
      } else if (ALive) {
        // 6a / 6b: addr=BC, A live. Try SpareR-A first (saves 12cc vs
        // PSW-wrap, same byte count). Exclude AddrReg (BC) and SrcReg
        // — SpareR must not alias the address pair (STAX B reads BC)
        // nor the source (`MOV spareR,A` would clobber src before it
        // is read into A).
        Register SpareR =
            findDeadGR8AtMI(MI, MBB, &RI, AddrReg, SrcReg);
        if (SpareR) {
          // 6a: MOV spareR,A; MOV A,src; STAX B; MOV A,spareR.
          BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), SpareR).addReg(V6Clang::A);
          BuildMI(MBB, MI, DL, get(V6Clang::MOVrr))
              .addReg(V6Clang::A, RegState::Define).addReg(SrcReg);
          BuildMI(MBB, MI, DL, get(V6Clang::STAX))
              .addReg(V6Clang::A).addReg(AddrReg);
          BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::A).addReg(SpareR);
        } else {
          // 6b: PUSH PSW; MOV A,src; STAX B; POP PSW (legacy fallback).
          BuildMI(MBB, MI, DL, get(V6Clang::PUSH)).addReg(V6Clang::PSW);
          BuildMI(MBB, MI, DL, get(V6Clang::MOVrr))
              .addReg(V6Clang::A, RegState::Define).addReg(SrcReg);
          BuildMI(MBB, MI, DL, get(V6Clang::STAX))
              .addReg(V6Clang::A).addReg(AddrReg);
          BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::PSW);
        }
      } else {
        // 4 / 5: A dead — plain MOV A,src + STAX.
        BuildMI(MBB, MI, DL, get(V6Clang::MOVrr))
            .addReg(V6Clang::A, RegState::Define).addReg(SrcReg);
        BuildMI(MBB, MI, DL, get(V6Clang::STAX))
            .addReg(V6Clang::A).addReg(AddrReg);
      }
    }
    MI.eraseFromParent();
    return true;
  }

  //===------------------------------------------------------------------===//
  // O49 — Direct memory ALU / store / RMW pseudos.
  //===------------------------------------------------------------------===//

  case V6Clang::V6CLANG_ADD_M_P:
  case V6Clang::V6CLANG_ADC_M_P:
  case V6Clang::V6CLANG_SUB_M_P:
  case V6Clang::V6CLANG_SBB_M_P:
  case V6Clang::V6CLANG_ANA_M_P:
  case V6Clang::V6CLANG_ORA_M_P:
  case V6Clang::V6CLANG_XRA_M_P: {
    // Operands: 0=$dst(Acc tied), 1=$lhs(Acc tied), 2=$addr(GR16).
    unsigned MOpc;
    switch (MI.getOpcode()) {
    case V6Clang::V6CLANG_ADD_M_P: MOpc = V6Clang::ADDM; break;
    case V6Clang::V6CLANG_ADC_M_P: MOpc = V6Clang::ADCM; break;
    case V6Clang::V6CLANG_SUB_M_P: MOpc = V6Clang::SUBM; break;
    case V6Clang::V6CLANG_SBB_M_P: MOpc = V6Clang::SBBM; break;
    case V6Clang::V6CLANG_ANA_M_P: MOpc = V6Clang::ANAM; break;
    case V6Clang::V6CLANG_ORA_M_P: MOpc = V6Clang::ORAM; break;
    case V6Clang::V6CLANG_XRA_M_P: MOpc = V6Clang::XRAM; break;
    default: llvm_unreachable("unexpected ALU M opcode");
    }
    Register AddrReg = MI.getOperand(2).getReg();
    expandMemOpM(MBB, MI, *this, RI, AddrReg,
        [&](MachineBasicBlock &B, MachineBasicBlock::iterator Ip) {
          // Physical M ALU ops: (outs Acc:$dst)(ins Acc:$lhs), tied.
          BuildMI(B, Ip, DL, get(MOpc), V6Clang::A).addReg(V6Clang::A);
        });
    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_CMP_M_P: {
    // Operands: 0=$lhs(Acc), 1=$addr(GR16). No register output.
    Register AddrReg = MI.getOperand(1).getReg();
    expandMemOpM(MBB, MI, *this, RI, AddrReg,
        [&](MachineBasicBlock &B, MachineBasicBlock::iterator Ip) {
          // Physical CMPM: (outs)(ins Acc:$lhs).
          BuildMI(B, Ip, DL, get(V6Clang::CMPM)).addReg(V6Clang::A);
        });
    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_STORE8_IMM_P: {
    // Operands: 0=$imm(imm8), 1=$addr(GR16).
    // Per-shape dispatch (O78). See design/future_plans/O78_*.md.
    int64_t Imm = MI.getOperand(0).getImm();
    Register AddrReg = MI.getOperand(1).getReg();

    if (AddrReg == V6Clang::HL) {
      // Row 1: direct.  2B / 12cc.
      BuildMI(MBB, MI, DL, get(V6Clang::MVIM)).addImm(Imm);
    } else {
      bool ADead = isRegDeadAtMI(V6Clang::A, MI, MBB, &RI);
      if (ADead) {
        // Rows 2/3: A dead → MVI A, imm; STAX rp.  3B / 16cc.
        BuildMI(MBB, MI, DL, get(V6Clang::MVIr), V6Clang::A).addImm(Imm);
        BuildMI(MBB, MI, DL, get(V6Clang::STAX))
            .addReg(V6Clang::A).addReg(AddrReg);
      } else if (AddrReg == V6Clang::DE) {
        // Row 4: A live, addr=DE → XCHG bypass.  4B / 20cc.
        BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
        BuildMI(MBB, MI, DL, get(V6Clang::MVIM)).addImm(Imm);
        BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
      } else {
        // AddrReg == V6Clang::BC, A live.
        bool HLDead = isRegDeadAtMI(V6Clang::HL, MI, MBB, &RI);
        bool DEDead = isRegDeadAtMI(V6Clang::DE, MI, MBB, &RI);
        if (HLDead) {
          // Row 5: BC + HL dead.  4B / 28cc.
          BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::L).addReg(V6Clang::C);
          BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::H).addReg(V6Clang::B);
          BuildMI(MBB, MI, DL, get(V6Clang::MVIM)).addImm(Imm);
        } else if (DEDead) {
          // Row 6: BC + HL live + DE dead → DE-route.  5B / 36cc.
          BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::D).addReg(V6Clang::B);
          BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::E).addReg(V6Clang::C);
          BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
          BuildMI(MBB, MI, DL, get(V6Clang::MVIM)).addImm(Imm);
          BuildMI(MBB, MI, DL, get(V6Clang::XCHG));
        } else {
          // Row 7: BC, all live → PUSH H envelope (legacy).  6B / 56cc.
          BuildMI(MBB, MI, DL, get(V6Clang::PUSH))
              .addReg(V6Clang::HL, RegState::Kill)
              .addReg(V6Clang::SP, RegState::ImplicitDefine);
          BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::L).addReg(V6Clang::C);
          BuildMI(MBB, MI, DL, get(V6Clang::MOVrr), V6Clang::H).addReg(V6Clang::B);
          BuildMI(MBB, MI, DL, get(V6Clang::MVIM)).addImm(Imm);
          BuildMI(MBB, MI, DL, get(V6Clang::POP), V6Clang::HL)
              .addReg(V6Clang::SP, RegState::ImplicitDefine);
        }
      }
    }
    MI.eraseFromParent();
    return true;
  }

  case V6Clang::V6CLANG_INR_M_P:
  case V6Clang::V6CLANG_DCR_M_P: {
    // Operand: 0=$addr(GR16).
    unsigned MOpc = (MI.getOpcode() == V6Clang::V6CLANG_INR_M_P) ? V6Clang::INRM
                                                        : V6Clang::DCRM;
    Register AddrReg = MI.getOperand(0).getReg();
    expandMemOpM(MBB, MI, *this, RI, AddrReg,
        [&](MachineBasicBlock &B, MachineBasicBlock::iterator Ip) {
          BuildMI(B, Ip, DL, get(MOpc));
        });
    MI.eraseFromParent();
    return true;
  }
  }
}
