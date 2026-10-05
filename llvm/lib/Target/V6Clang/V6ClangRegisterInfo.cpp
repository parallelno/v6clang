//===-- V6ClangRegisterInfo.cpp - V6CLANG Register Information --------------------===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#include "V6ClangRegisterInfo.h"
#include "V6Clang.h"
#include "V6ClangFrameLowering.h"
#include "V6ClangMachineFunctionInfo.h"
#include "V6ClangSpillExpand.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"

#define GET_REGINFO_TARGET_DESC
#include "V6ClangGenRegisterInfo.inc"

using namespace llvm;

V6ClangRegisterInfo::V6ClangRegisterInfo() : V6ClangGenRegisterInfo(V6CLANG::PC) {}

static void markXchgUseUndef(MachineInstr *XchgMI, Register Reg) {
  if (MachineOperand *MO = XchgMI->findRegisterUseOperand(Reg,
                                                          /*isKill=*/false))
    MO->setIsUndef(true);
}

const MCPhysReg *
V6ClangRegisterInfo::getCalleeSavedRegs(const MachineFunction *MF) const {
  // Per design §6.1: no callee-saved registers — all are caller-saved.
  static const MCPhysReg CalleeSavedRegs[] = {0};
  return CalleeSavedRegs;
}

const uint32_t *
V6ClangRegisterInfo::getCallPreservedMask(const MachineFunction &MF,
                                       CallingConv::ID CC) const {
  // No registers are preserved across calls.
  static const uint32_t Mask[(V6CLANG::NUM_TARGET_REGS + 31) / 32] = {0};
  return Mask;
}

BitVector V6ClangRegisterInfo::getReservedRegs(const MachineFunction &MF) const {
  BitVector Reserved(getNumRegs());
  Reserved.set(V6CLANG::SP);
  Reserved.set(V6CLANG::PC);
  Reserved.set(V6CLANG::FLAGS);
  Reserved.set(V6CLANG::PSW);

  // When using a frame pointer, reserve BC (and its sub-registers B, C).
  const V6ClangFrameLowering *TFI = static_cast<const V6ClangFrameLowering *>(
      MF.getSubtarget().getFrameLowering());
  if (TFI->hasFP(MF)) {
    Reserved.set(V6CLANG::BC);
    Reserved.set(V6CLANG::B);
    Reserved.set(V6CLANG::C);
  }

  return Reserved;
}

const TargetRegisterClass *
V6ClangRegisterInfo::getLargestLegalSuperClass(
    const TargetRegisterClass *RC, const MachineFunction &MF) const {
  // Widen Acc (singleton {A}) to GR8 ({A,B,C,D,E,H,L}) so the register
  // allocator can park Acc-constrained values in other GPRs and insert
  // MOV A,r copies when the value is actually needed in A.
  if (V6CLANG::AccRegClass.hasSubClassEq(RC))
    return &V6CLANG::GR8RegClass;
  return TargetRegisterInfo::getLargestLegalSuperClass(RC, MF);
}

/// Check if a physical register is dead after a given instruction (O42).
/// Scans forward from MI (exclusive) to end of MBB.
/// Returns true if no read before redef, and Reg not in any successor livein.
// Moved to V6ClangSpillExpand.cpp (O64). Declared in V6ClangSpillExpand.h.

bool V6ClangRegisterInfo::eliminateFrameIndex(MachineBasicBlock::iterator II,
                                           int SPAdj,
                                           unsigned FIOperandNum,
                                           RegScavenger *RS) const {
  MachineInstr &MI = *II;
  MachineBasicBlock &MBB = *MI.getParent();
  MachineFunction &MF = *MBB.getParent();
  const MachineFrameInfo &MFI = MF.getFrameInfo();
  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();
  DebugLoc DL = MI.getDebugLoc();

  int FrameIndex = MI.getOperand(FIOperandNum).getIndex();
  int Offset = MFI.getObjectOffset(FrameIndex) + MFI.getStackSize() + SPAdj;

  // Insert annotation comment before expansion (if enabled).
  MachineInstr *CommentMI = nullptr;
  if (getV6ClangAnnotatePseudosEnabled()) {
    CommentMI = BuildMI(MBB, II, DL, TII.get(V6CLANG::V6CLANG_PSEUDO_COMMENT))
                    .addImm(MI.getOpcode())
                    .getInstr();
  }

  // --- Static stack expansion (O10) ---
  // If this function uses static stack allocation, expand spill/reload
  // pseudos using direct global addresses instead of SP-relative sequences.
  auto *FuncInfo = MF.getInfo<V6ClangMachineFunctionInfo>();
  if (FuncInfo && FuncInfo->hasStaticStack() &&
      FuncInfo->hasStaticSlot(FrameIndex)) {
    GlobalVariable *GV = FuncInfo->getStaticStackGV();
    int64_t StaticOffset = FuncInfo->getStaticOffset(FrameIndex);

    unsigned Opc = MI.getOpcode();

    if (Opc == V6CLANG::V6CLANG_LEA_FI) {
      // LXI HL, __v6clang_static_stack+offset (no DAD SP needed)
      Register DstReg = MI.getOperand(0).getReg();
      BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
          .addReg(DstReg, RegState::Define)
          .addGlobalAddress(GV, StaticOffset);
      MI.eraseFromParent();
      return true;
    }

    if (Opc == V6CLANG::V6CLANG_SPILL8) {
      Register SrcReg = MI.getOperand(0).getReg();
      bool IsKill = MI.getOperand(0).isKill();
      if (SrcReg == V6CLANG::A) {
        // STA __v6clang_ss+offset (16cc, 3B)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::STA))
            .addReg(V6CLANG::A, getKillRegState(IsKill))
            .addGlobalAddress(GV, StaticOffset);
      } else {
        // O64 ladder handles Shape B (r in {B,C,D,E}) and Shape C (r in {H,L}).
        expandSpill8Static(MI, II, SrcReg, IsKill, TII, this,
            [&](MachineInstrBuilder &B) {
              B.addGlobalAddress(GV, StaticOffset);
            });
      }
      MI.eraseFromParent();
      return true;
    }

    if (Opc == V6CLANG::V6CLANG_RELOAD8) {
      Register DstReg = MI.getOperand(0).getReg();
      if (DstReg == V6CLANG::A) {
        // LDA __v6clang_ss+offset (16cc, 3B)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::LDA), V6CLANG::A)
            .addGlobalAddress(GV, StaticOffset);
      } else {
        // O64 ladder handles Shape B (r in {B,C,D,E}) and Shape C (r in {H,L}).
        expandReload8Static(MI, II, DstReg, TII, this,
            [&](MachineInstrBuilder &B) {
              B.addGlobalAddress(GV, StaticOffset);
            });
      }
      MI.eraseFromParent();
      return true;
    }

    if (Opc == V6CLANG::V6CLANG_SPILL16) {
      Register SrcReg = MI.getOperand(0).getReg();
      bool IsKill = MI.getOperand(0).isKill();
      if (SrcReg == V6CLANG::HL) {
        // SHLD __v6clang_ss+offset (16cc, 3B)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::SHLD))
            .addReg(V6CLANG::HL)
            .addGlobalAddress(GV, StaticOffset);
      } else if (SrcReg == V6CLANG::DE) {
        // XCHG; SHLD addr; XCHG (24cc, 5B)
        // O42: skip trailing XCHG only when BOTH HL is dead AND DE is killed.
        // XCHG swaps both registers, so skipping it corrupts whichever is
        // still live: DE (if not killed) or HL (if not dead).
        bool HLDead = isPairDeadAfterMI(V6CLANG::HL, MI, MBB, this);
        BuildMI(MBB, II, DL, TII.get(V6CLANG::XCHG));
        BuildMI(MBB, II, DL, TII.get(V6CLANG::SHLD))
            .addReg(V6CLANG::HL)
            .addGlobalAddress(GV, StaticOffset);
        if (!(IsKill && HLDead))
          BuildMI(MBB, II, DL, TII.get(V6CLANG::XCHG));
      } else {
        // BC: PUSH HL; LXI HL, addr; MOV M, C; INX HL; MOV M, B; POP HL
        MCRegister SrcLo = getSubReg(SrcReg, V6CLANG::sub_lo);
        MCRegister SrcHi = getSubReg(SrcReg, V6CLANG::sub_hi);
        // O42: when HL is dead, use MOV L,C; MOV H,B; SHLD addr (5B, 32cc)
        bool HLDead = isPairDeadAfterMI(V6CLANG::HL, MI, MBB, this);
        if (HLDead) {
          BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
              .addReg(V6CLANG::L, RegState::Define)
              .addReg(SrcLo, getKillRegState(IsKill));
          BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
              .addReg(V6CLANG::H, RegState::Define)
              .addReg(SrcHi, getKillRegState(IsKill));
          BuildMI(MBB, II, DL, TII.get(V6CLANG::SHLD))
              .addReg(V6CLANG::HL)
              .addGlobalAddress(GV, StaticOffset);
        } else {
          BuildMI(MBB, II, DL, TII.get(V6CLANG::PUSH)).addReg(V6CLANG::HL);
          BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
              .addReg(V6CLANG::HL, RegState::Define)
              .addGlobalAddress(GV, StaticOffset);
          BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVMr))
              .addReg(SrcLo, getKillRegState(IsKill));
          BuildMI(MBB, II, DL, TII.get(V6CLANG::INX), V6CLANG::HL).addReg(V6CLANG::HL);
          BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVMr))
              .addReg(SrcHi, getKillRegState(IsKill));
          BuildMI(MBB, II, DL, TII.get(V6CLANG::POP), V6CLANG::HL);
        }
      }
      MI.eraseFromParent();
      return true;
    }

    if (Opc == V6CLANG::V6CLANG_RELOAD16) {
      Register DstReg = MI.getOperand(0).getReg();
      if (DstReg == V6CLANG::HL) {
        // LHLD __v6clang_ss+offset (16cc, 3B)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::LHLD), V6CLANG::HL)
            .addGlobalAddress(GV, StaticOffset);
      } else if (DstReg == V6CLANG::DE) {
        // O42: when HL is dead, use LHLD addr; XCHG (4B, 20cc)
        // instead of XCHG; LHLD addr; XCHG (5B, 24cc)
        // Check H and L independently: pair query stops at first def of
        // either half, so is too conservative when only one half is live.
        bool HLDead = isRegDeadAfterMI(V6CLANG::H, MI, MBB, this) &&
                      isRegDeadAfterMI(V6CLANG::L, MI, MBB, this);
        if (HLDead) {
          BuildMI(MBB, II, DL, TII.get(V6CLANG::LHLD), V6CLANG::HL)
              .addGlobalAddress(GV, StaticOffset);
          MachineInstr *XchgMI =
              BuildMI(MBB, II, DL, TII.get(V6CLANG::XCHG)).getInstr();
          markXchgUseUndef(XchgMI, V6CLANG::DE);
        } else {
          // XCHG; LHLD addr; XCHG (24cc, 5B)
          MachineInstr *FirstXchg =
              BuildMI(MBB, II, DL, TII.get(V6CLANG::XCHG)).getInstr();
          markXchgUseUndef(FirstXchg, V6CLANG::DE);
          BuildMI(MBB, II, DL, TII.get(V6CLANG::LHLD), V6CLANG::HL)
              .addGlobalAddress(GV, StaticOffset);
          BuildMI(MBB, II, DL, TII.get(V6CLANG::XCHG));
        }
      } else {
        // BC: PUSH HL; LXI HL, addr; MOV C, M; INX HL; MOV B, M; POP HL
        MCRegister DstLo = getSubReg(DstReg, V6CLANG::sub_lo);
        MCRegister DstHi = getSubReg(DstReg, V6CLANG::sub_hi);
        // O42: when HL is dead, use LHLD addr; MOV C,L; MOV B,H (5B, 30cc)
        // Check H and L independently: pair query stops at first def of
        // either half, so is too conservative when only one half is live.
        bool HLDead = isRegDeadAfterMI(V6CLANG::H, MI, MBB, this) &&
                      isRegDeadAfterMI(V6CLANG::L, MI, MBB, this);
        if (HLDead) {
          BuildMI(MBB, II, DL, TII.get(V6CLANG::LHLD), V6CLANG::HL)
              .addGlobalAddress(GV, StaticOffset);
          BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
              .addReg(DstLo, RegState::Define).addReg(V6CLANG::L);
          BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
              .addReg(DstHi, RegState::Define).addReg(V6CLANG::H);
        } else {
          BuildMI(MBB, II, DL, TII.get(V6CLANG::PUSH)).addReg(V6CLANG::HL);
          BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
              .addReg(V6CLANG::HL, RegState::Define)
              .addGlobalAddress(GV, StaticOffset);
          BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM))
              .addReg(DstLo, RegState::Define);
          BuildMI(MBB, II, DL, TII.get(V6CLANG::INX), V6CLANG::HL).addReg(V6CLANG::HL);
          BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM))
              .addReg(DstHi, RegState::Define);
          BuildMI(MBB, II, DL, TII.get(V6CLANG::POP), V6CLANG::HL);
        }
      }
      MI.eraseFromParent();
      return true;
    }

    // Direct stack/frame-index value loads and stores. Unlike the
    // SP-relative path these need no `DAD SP` — the static slot address is
    // absolute. The *_FI pseudos clobber HL (Defs=[HL, FLAGS]), so the
    // address may be formed in HL freely.
    if (Opc == V6CLANG::V6CLANG_LOAD8_FI) {
      Register DstReg = MI.getOperand(0).getReg();
      if (DstReg == V6CLANG::A) {
        // LDA __v6clang_ss+offset (13cc, 3B)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::LDA), V6CLANG::A)
            .addGlobalAddress(GV, StaticOffset);
      } else {
        BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
            .addReg(V6CLANG::HL, RegState::Define)
            .addGlobalAddress(GV, StaticOffset);
        BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM))
            .addReg(DstReg, RegState::Define);
      }
      MI.eraseFromParent();
      return true;
    }

    if (Opc == V6CLANG::V6CLANG_LOAD16_FI) {
      Register DstReg = MI.getOperand(0).getReg();
      if (DstReg == V6CLANG::HL) {
        // LHLD __v6clang_ss+offset (16cc, 3B)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::LHLD), V6CLANG::HL)
            .addGlobalAddress(GV, StaticOffset);
      } else {
        // DE or BC: LXI HL, addr; MOV lo, M; INX HL; MOV hi, M
        Register DstLo = getSubReg(DstReg, V6CLANG::sub_lo);
        Register DstHi = getSubReg(DstReg, V6CLANG::sub_hi);
        BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
            .addReg(V6CLANG::HL, RegState::Define)
            .addGlobalAddress(GV, StaticOffset);
        BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM))
            .addReg(DstLo, RegState::Define);
        BuildMI(MBB, II, DL, TII.get(V6CLANG::INX), V6CLANG::HL).addReg(V6CLANG::HL);
        BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM))
            .addReg(DstHi, RegState::Define);
      }
      MI.eraseFromParent();
      return true;
    }

    if (Opc == V6CLANG::V6CLANG_STORE8_FI) {
      Register SrcReg = MI.getOperand(0).getReg();
      bool IsKill = MI.getOperand(0).isKill();
      if (SrcReg == V6CLANG::A) {
        // STA __v6clang_ss+offset (13cc, 3B)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::STA))
            .addReg(V6CLANG::A, getKillRegState(IsKill))
            .addGlobalAddress(GV, StaticOffset);
      } else {
        // SrcReg is GR8NoHL (never H/L), so MOV M, r is safe with HL holding
        // the address.
        BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
            .addReg(V6CLANG::HL, RegState::Define)
            .addGlobalAddress(GV, StaticOffset);
        BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVMr))
            .addReg(SrcReg, getKillRegState(IsKill));
      }
      MI.eraseFromParent();
      return true;
    }

    if (Opc == V6CLANG::V6CLANG_STORE16_FI) {
      // SrcReg is GR16Idx (BC or DE only, never HL), so forming the address
      // in HL does not clobber the value.
      Register SrcReg = MI.getOperand(0).getReg();
      bool IsKill = MI.getOperand(0).isKill();
      Register SrcLo = getSubReg(SrcReg, V6CLANG::sub_lo);
      Register SrcHi = getSubReg(SrcReg, V6CLANG::sub_hi);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
          .addReg(V6CLANG::HL, RegState::Define)
          .addGlobalAddress(GV, StaticOffset);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVMr))
          .addReg(SrcLo, getKillRegState(IsKill));
      BuildMI(MBB, II, DL, TII.get(V6CLANG::INX), V6CLANG::HL).addReg(V6CLANG::HL);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVMr))
          .addReg(SrcHi, getKillRegState(IsKill));
      MI.eraseFromParent();
      return true;
    }

    // Fallback for other instructions with frame indices in static mode:
    // replace with global address offset. This shouldn't normally happen.
    if (CommentMI)
      CommentMI->eraseFromParent();
    MI.getOperand(FIOperandNum)
        .ChangeToGA(GV, StaticOffset, MI.getOperand(FIOperandNum).getTargetFlags());
    return false;
  }
  // --- End static stack expansion ---

  unsigned Opc = MI.getOpcode();
  if (Opc == V6CLANG::V6CLANG_LEA_FI) {
    // DAD SP always writes the result into HL. If the RA selected HL as
    // the destination, that is the result. If it selected DE or BC, we
    // copy HL into the chosen pair afterwards. HL is always clobbered
    // (modeled in the pseudo's Defs list).
    Register DstReg = MI.getOperand(0).getReg();
    BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
        .addReg(V6CLANG::HL, RegState::Define)
        .addImm(Offset);
    BuildMI(MBB, II, DL, TII.get(V6CLANG::DAD))
        .addReg(V6CLANG::SP);
    if (DstReg == V6CLANG::DE) {
      // XCHG: HL <-> DE (4cc, 1B). The pseudo does not read DE, so the
      // old DE value is undef; mark XCHG's implicit DE use as Undef so
      // the machine verifier accepts it. New DE = old HL (the address).
      // Old HL goes into DE-input slot (undef, fine); HL is listed in
      // the pseudo's Defs so it may be clobbered.
      MachineInstr *MIB =
          BuildMI(MBB, II, DL, TII.get(V6CLANG::XCHG)).getInstr();
      markXchgUseUndef(MIB, V6CLANG::DE);
    } else if (DstReg == V6CLANG::BC) {
      // Copy HL → BC (HL is dead after this pseudo by virtue of being in Defs).
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
          .addReg(V6CLANG::B, RegState::Define).addReg(V6CLANG::H);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
          .addReg(V6CLANG::C, RegState::Define).addReg(V6CLANG::L);
    } else {
      assert(DstReg == V6CLANG::HL && "V6CLANG_LEA_FI dst must be HL, DE, or BC");
    }
    MI.eraseFromParent();
    return true;
  }

  if (Opc == V6CLANG::V6CLANG_LOAD8_FI) {
    Register DstReg = MI.getOperand(0).getReg();
    BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
        .addReg(V6CLANG::HL, RegState::Define).addImm(Offset);
    BuildMI(MBB, II, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
    BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM))
        .addReg(DstReg, RegState::Define);
    MI.eraseFromParent();
    return true;
  }

  if (Opc == V6CLANG::V6CLANG_LOAD16_FI) {
    Register DstReg = MI.getOperand(0).getReg();
    BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
        .addReg(V6CLANG::HL, RegState::Define).addImm(Offset);
    BuildMI(MBB, II, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
    if (DstReg == V6CLANG::HL) {
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM), V6CLANG::A);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::INX), V6CLANG::HL).addReg(V6CLANG::HL);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM), V6CLANG::H);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr), V6CLANG::L).addReg(V6CLANG::A);
    } else {
      Register DstLo = getSubReg(DstReg, V6CLANG::sub_lo);
      Register DstHi = getSubReg(DstReg, V6CLANG::sub_hi);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM))
          .addReg(DstLo, RegState::Define);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::INX), V6CLANG::HL).addReg(V6CLANG::HL);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM))
          .addReg(DstHi, RegState::Define);
    }
    MI.eraseFromParent();
    return true;
  }

  if (Opc == V6CLANG::V6CLANG_STORE8_FI) {
    Register SrcReg = MI.getOperand(0).getReg();
    BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
        .addReg(V6CLANG::HL, RegState::Define).addImm(Offset);
    BuildMI(MBB, II, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
    BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVMr))
        .addReg(SrcReg, getKillRegState(MI.getOperand(0).isKill()));
    MI.eraseFromParent();
    return true;
  }

  if (Opc == V6CLANG::V6CLANG_STORE16_FI) {
    Register SrcReg = MI.getOperand(0).getReg();
    Register SrcLo = getSubReg(SrcReg, V6CLANG::sub_lo);
    Register SrcHi = getSubReg(SrcReg, V6CLANG::sub_hi);
    BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
        .addReg(V6CLANG::HL, RegState::Define).addImm(Offset);
    BuildMI(MBB, II, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
    BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVMr))
        .addReg(SrcLo, getKillRegState(MI.getOperand(0).isKill()));
    BuildMI(MBB, II, DL, TII.get(V6CLANG::INX), V6CLANG::HL).addReg(V6CLANG::HL);
    BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVMr))
        .addReg(SrcHi, getKillRegState(MI.getOperand(0).isKill()));
    MI.eraseFromParent();
    return true;
  }

  if (Opc == V6CLANG::V6CLANG_SPILL8) {
    // Expand: PUSH HL; LXI HL, offset+2; DAD SP; MOV M, r; POP HL
    // PUSH/POP preserves HL so the RA doesn't see HL clobbered.
    Register SrcReg = MI.getOperand(0).getReg();
    bool SrcIsHorL = (SrcReg == V6CLANG::H || SrcReg == V6CLANG::L);
    if (SrcIsHorL) {
      // Spilling H or L: use DE as temp to avoid clobbering A.
      // Save DE, copy H/L pair into D/E, use HL for address, store, restore.
      bool SpillingH = (SrcReg == V6CLANG::H);
      Register ValReg = SpillingH ? V6CLANG::D : V6CLANG::E;
      Register OtherReg = SpillingH ? V6CLANG::E : V6CLANG::D;
      Register OtherHL = SpillingH ? V6CLANG::L : V6CLANG::H;
      // O42: skip PUSH/POP DE when DE is dead; adjust offset accordingly.
      bool DEDead = isPairDeadAfterMI(V6CLANG::DE, MI, MBB, this);
      int AdjOffset = DEDead ? Offset : Offset + 2;
      if (!DEDead)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::PUSH)).addReg(V6CLANG::DE);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
          .addReg(ValReg, RegState::Define).addReg(SrcReg);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
          .addReg(OtherReg, RegState::Define).addReg(OtherHL);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
          .addReg(V6CLANG::HL, RegState::Define).addImm(AdjOffset);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVMr)).addReg(ValReg);
      // Restore HL from D/E.
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
          .addReg(V6CLANG::H, RegState::Define).addReg(V6CLANG::D);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
          .addReg(V6CLANG::L, RegState::Define).addReg(V6CLANG::E);
      if (!DEDead)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::POP), V6CLANG::DE);
    } else {
      // O42: skip PUSH/POP HL when HL is dead; adjust offset accordingly.
      bool HLDead = isPairDeadAfterMI(V6CLANG::HL, MI, MBB, this);
      int AdjOffset = HLDead ? Offset : Offset + 2;
      if (!HLDead)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::PUSH)).addReg(V6CLANG::HL);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
          .addReg(V6CLANG::HL, RegState::Define).addImm(AdjOffset);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVMr))
          .addReg(SrcReg, getKillRegState(MI.getOperand(0).isKill()));
      if (!HLDead)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::POP), V6CLANG::HL);
    }
    MI.eraseFromParent();
    return true;
  }

  if (Opc == V6CLANG::V6CLANG_RELOAD8) {
    // Expand: PUSH HL; LXI HL, offset+2; DAD SP; MOV r, M; POP HL
    // PUSH/POP preserves HL so the RA doesn't see HL clobbered.
    Register DstReg = MI.getOperand(0).getReg();
    bool DstIsHorL = (DstReg == V6CLANG::H || DstReg == V6CLANG::L);
    if (DstIsHorL) {
      // Reloading into H or L: use DE as temp to preserve other half.
      bool LoadingH = (DstReg == V6CLANG::H);
      Register OtherHL = LoadingH ? V6CLANG::L : V6CLANG::H;
      // O49: skip saving/restoring the other half when it's dead.
      bool OtherHLDead = isRegDeadAfterMI(OtherHL, MI, MBB, this);
      if (OtherHLDead) {
        // Other half dead: just clobber entire HL.
        BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
            .addReg(V6CLANG::HL, RegState::Define).addImm(Offset);
        BuildMI(MBB, II, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
        // MOV H,M / MOV L,M: 8080 latches [HL] address before writing dst.
        BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM))
            .addReg(DstReg, RegState::Define);
      } else {
        // Other half live: save it in D, reload, restore.
        Register SaveOther = V6CLANG::D;
        // O42: skip PUSH/POP DE when DE is dead; adjust offset accordingly.
        bool DEDead = isPairDeadAfterMI(V6CLANG::DE, MI, MBB, this);
        int AdjOffset = DEDead ? Offset : Offset + 2;
        if (!DEDead)
          BuildMI(MBB, II, DL, TII.get(V6CLANG::PUSH)).addReg(V6CLANG::DE);
        BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
            .addReg(SaveOther, RegState::Define).addReg(OtherHL);
        BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
            .addReg(V6CLANG::HL, RegState::Define).addImm(AdjOffset);
        BuildMI(MBB, II, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
        // MOV H,M / MOV L,M: 8080 latches [HL] address before writing dst.
        BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM))
            .addReg(DstReg, RegState::Define);
        // Restore the non-target half.
        BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
            .addReg(OtherHL, RegState::Define).addReg(SaveOther);
        if (!DEDead)
          BuildMI(MBB, II, DL, TII.get(V6CLANG::POP), V6CLANG::DE);
      }
    } else {
      // O42: skip PUSH/POP HL when HL is dead; adjust offset accordingly.
      bool HLDead = isPairDeadAfterMI(V6CLANG::HL, MI, MBB, this);
      int AdjOffset = HLDead ? Offset : Offset + 2;
      if (!HLDead)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::PUSH)).addReg(V6CLANG::HL);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
          .addReg(V6CLANG::HL, RegState::Define).addImm(AdjOffset);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM))
          .addReg(DstReg, RegState::Define);
      if (!HLDead)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::POP), V6CLANG::HL);
    }
    MI.eraseFromParent();
    return true;
  }

  if (Opc == V6CLANG::V6CLANG_SPILL16) {
    // Expand: store 16-bit register to stack slot.
    // All paths preserve registers OTHER than the src (if killed) and FLAGS.
    Register SrcReg = MI.getOperand(0).getReg();
    bool IsKill = MI.getOperand(0).isKill();

    if (SrcReg == V6CLANG::HL) {
      // Spilling HL: save DE, copy HL→DE, use HL for addressing, restore.
      // O42: skip PUSH/POP DE when DE is dead; adjust offset accordingly.
      bool DEDead = isPairDeadAfterMI(V6CLANG::DE, MI, MBB, this);
      int AdjOffset = DEDead ? Offset : Offset + 2;
      if (!DEDead)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::PUSH)).addReg(V6CLANG::DE);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
          .addReg(V6CLANG::D, RegState::Define).addReg(V6CLANG::H);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
          .addReg(V6CLANG::E, RegState::Define).addReg(V6CLANG::L);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
          .addReg(V6CLANG::HL, RegState::Define).addImm(AdjOffset);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVMr)).addReg(V6CLANG::E);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::INX), V6CLANG::HL).addReg(V6CLANG::HL);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVMr)).addReg(V6CLANG::D);
      if (!IsKill) {
        // Restore HL from DE.
        BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
            .addReg(V6CLANG::H, RegState::Define).addReg(V6CLANG::D);
        BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
            .addReg(V6CLANG::L, RegState::Define).addReg(V6CLANG::E);
      }
      if (!DEDead)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::POP), V6CLANG::DE);
    } else {
      // Spilling DE or BC: save HL, use HL for addressing, restore.
      MCRegister SrcLo = getSubReg(SrcReg, V6CLANG::sub_lo);
      MCRegister SrcHi = getSubReg(SrcReg, V6CLANG::sub_hi);
      // O42: skip PUSH/POP HL when HL is dead; adjust offset accordingly.
      bool HLDead = isPairDeadAfterMI(V6CLANG::HL, MI, MBB, this);
      int AdjOffset = HLDead ? Offset : Offset + 2;
      if (!HLDead)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::PUSH)).addReg(V6CLANG::HL);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
          .addReg(V6CLANG::HL, RegState::Define).addImm(AdjOffset);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVMr))
          .addReg(SrcLo, getKillRegState(IsKill));
      BuildMI(MBB, II, DL, TII.get(V6CLANG::INX), V6CLANG::HL).addReg(V6CLANG::HL);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVMr))
          .addReg(SrcHi, getKillRegState(IsKill));
      if (!HLDead)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::POP), V6CLANG::HL);
    }
    MI.eraseFromParent();
    return true;
  }

  if (Opc == V6CLANG::V6CLANG_RELOAD16) {
    // Expand: load 16-bit register from stack slot.
    // All paths preserve registers OTHER than the dst and FLAGS.
    Register DstReg = MI.getOperand(0).getReg();

    if (DstReg == V6CLANG::HL) {
      // Reloading into HL: save DE, load via HL into DE, copy to HL, restore.
      // O42: skip PUSH/POP DE when DE is dead; adjust offset accordingly.
      bool DEDead = isPairDeadAfterMI(V6CLANG::DE, MI, MBB, this);
      int AdjOffset = DEDead ? Offset : Offset + 2;
      if (!DEDead)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::PUSH)).addReg(V6CLANG::DE);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
          .addReg(V6CLANG::HL, RegState::Define).addImm(AdjOffset);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM))
          .addReg(V6CLANG::E, RegState::Define);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::INX), V6CLANG::HL).addReg(V6CLANG::HL);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM))
          .addReg(V6CLANG::D, RegState::Define);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
          .addReg(V6CLANG::H, RegState::Define).addReg(V6CLANG::D);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrr))
          .addReg(V6CLANG::L, RegState::Define).addReg(V6CLANG::E);
      if (!DEDead)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::POP), V6CLANG::DE);
    } else {
      // Reloading into DE or BC: save HL, load, restore HL.
      MCRegister LoadLo = getSubReg(DstReg, V6CLANG::sub_lo);
      MCRegister LoadHi = getSubReg(DstReg, V6CLANG::sub_hi);
      // O42: skip PUSH/POP HL when HL is dead; adjust offset accordingly.
      bool HLDead = isPairDeadAfterMI(V6CLANG::HL, MI, MBB, this);
      int AdjOffset = HLDead ? Offset : Offset + 2;
      if (!HLDead)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::PUSH)).addReg(V6CLANG::HL);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
          .addReg(V6CLANG::HL, RegState::Define).addImm(AdjOffset);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM))
          .addReg(LoadLo, RegState::Define);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::INX), V6CLANG::HL).addReg(V6CLANG::HL);
      BuildMI(MBB, II, DL, TII.get(V6CLANG::MOVrM))
          .addReg(LoadHi, RegState::Define);
      if (!HLDead)
        BuildMI(MBB, II, DL, TII.get(V6CLANG::POP), V6CLANG::HL);
    }
    MI.eraseFromParent();
    return true;
  }

  // For other instructions with frame indices, replace the FI operand
  // with SP + offset. This is a fallback; specific pseudos are preferred.
  if (CommentMI)
    CommentMI->eraseFromParent();
  MI.getOperand(FIOperandNum).ChangeToImmediate(Offset);
  return false;
}

Register
V6ClangRegisterInfo::getFrameRegister(const MachineFunction &MF) const {
  const V6ClangFrameLowering *TFI = static_cast<const V6ClangFrameLowering *>(
      MF.getSubtarget().getFrameLowering());
  if (TFI->hasFP(MF))
    return V6CLANG::BC;
  return V6CLANG::SP;
}
