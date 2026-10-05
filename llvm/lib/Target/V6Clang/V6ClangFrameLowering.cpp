//===-- V6ClangFrameLowering.cpp - V6CLANG Frame Lowering -------------------------===//
//
// Part of the V6CLANG backend for LLVM.
//
// M5: Frame Lowering & Calling Convention.
//
// 8080 stack frame lowering. The 8080 has no frame pointer or
// stack-relative addressing, so we adjust SP via LXI+DAD sequences.
//
// When a frame pointer is needed (alloca, -fno-omit-frame-pointer),
// BC is reserved as the FP and saved/restored in prologue/epilogue.
//
//===----------------------------------------------------------------------===//

#include "V6ClangFrameLowering.h"
#include "V6Clang.h"
#include "V6ClangInstrCost.h"
#include "V6ClangMachineFunctionInfo.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/IR/Function.h"

using namespace llvm;

bool V6ClangFrameLowering::hasFP(const MachineFunction &MF) const {
  const MachineFrameInfo &MFI = MF.getFrameInfo();
  return MF.getTarget().Options.DisableFramePointerElim(MF) ||
         MFI.hasVarSizedObjects() ||
         MFI.isFrameAddressTaken();
}

TargetFrameLowering::DwarfFrameBase
V6ClangFrameLowering::getDwarfFrameBase(const MachineFunction &MF) const {
  int64_t CFAOffset = 2 + static_cast<int64_t>(MF.getFrameInfo().getStackSize());
  if (hasFP(MF))
    CFAOffset = MF.getInfo<V6ClangMachineFunctionInfo>()->getFrameCFAOffset();
  DwarfFrameBase Result;
  Result.Kind = DwarfFrameBase::CFA;
  Result.Location.Offset = static_cast<int>(-CFAOffset);
  return Result;
}

// Pick a GR16All pair whose halves are dead at MBBI. PSW (A+FLAGS) is
// preferred — at function boundaries A is typically dead unless it is
// the i8 arg-1 / i8 return register, and FLAGS is always dead.
Register V6ClangFrameLowering::chooseDeadPair(const MachineBasicBlock &MBB,
                                          MachineBasicBlock::iterator MBBI,
                                          bool IsPrologue) const {
  if (IsPrologue) {
    // At entry: a half is "live" iff it appears in the MBB live-in set.
    auto IsLive = [&](unsigned R) { return MBB.isLiveIn(R); };
    bool ALive = IsLive(V6CLANG::A);
    bool BLive = IsLive(V6CLANG::B) || IsLive(V6CLANG::BC);
    bool CLive = IsLive(V6CLANG::C) || IsLive(V6CLANG::BC);
    bool DLive = IsLive(V6CLANG::D) || IsLive(V6CLANG::DE);
    bool ELive = IsLive(V6CLANG::E) || IsLive(V6CLANG::DE);
    bool HLive = IsLive(V6CLANG::H) || IsLive(V6CLANG::HL);
    bool LLive = IsLive(V6CLANG::L) || IsLive(V6CLANG::HL);
    if (!ALive)               return V6CLANG::PSW;
    if (!BLive && !CLive)     return V6CLANG::BC;
    if (!DLive && !ELive)     return V6CLANG::DE;
    if (!HLive && !LLive)     return V6CLANG::HL;
    return V6CLANG::NoRegister;
  }

  // Epilogue: a half is "live" iff it is used by the terminating RET.
  bool AUsed = false, BUsed = false, CUsed = false;
  bool DUsed = false, EUsed = false, HUsed = false, LUsed = false;
  if (MBBI != MBB.end() && MBBI->isReturn()) {
    for (const MachineOperand &MO : MBBI->operands()) {
      if (!MO.isReg()) continue;
      Register R = MO.getReg();
      if (R == V6CLANG::A)                          AUsed = true;
      if (R == V6CLANG::B  || R == V6CLANG::BC)         BUsed = true;
      if (R == V6CLANG::C  || R == V6CLANG::BC)         CUsed = true;
      if (R == V6CLANG::D  || R == V6CLANG::DE)         DUsed = true;
      if (R == V6CLANG::E  || R == V6CLANG::DE)         EUsed = true;
      if (R == V6CLANG::H  || R == V6CLANG::HL)         HUsed = true;
      if (R == V6CLANG::L  || R == V6CLANG::HL)         LUsed = true;
    }
  }
  if (!AUsed)               return V6CLANG::PSW;
  if (!BUsed && !CUsed)     return V6CLANG::BC;
  if (!DUsed && !EUsed)     return V6CLANG::DE;
  if (!HUsed && !LUsed)     return V6CLANG::HL;
  return V6CLANG::NoRegister;
}

void V6ClangFrameLowering::emitSPAdjustment(MachineBasicBlock &MBB,
                                        MachineBasicBlock::iterator MBBI,
                                        int64_t Amount, const DebugLoc &DL,
                                        bool IsPrologue,
                                        V6ClangOptMode Mode) const {
  if (Amount == 0)
    return;

  const TargetInstrInfo &TII = *MBB.getParent()->getSubtarget().getInstrInfo();
  const uint64_t AbsN = static_cast<uint64_t>(Amount < 0 ? -Amount : Amount);

  // Tier 1 — PUSH/POP x (AbsN/2) when a dead GR16All pair is available
  // and the PUSH/POP cost beats LXI+DAD+SPHL under Mode.
  bool PushPopEligible =
      (AbsN % 2 == 0) && AbsN >= 2 &&
      (AbsN == 2 || AbsN == 4 ||
       (AbsN == 6 && Mode == V6ClangOptMode::Size));
  if (PushPopEligible) {
    Register Pair = chooseDeadPair(MBB, MBBI, IsPrologue);
    if (Pair != V6CLANG::NoRegister) {
      unsigned N = static_cast<unsigned>(AbsN / 2);
      for (unsigned I = 0; I < N; ++I) {
        if (IsPrologue) {
          // PUSH reads Pair; the value is undef (we just want SP-=2).
          BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::PUSH))
              .addReg(Pair, RegState::Undef);
        } else {
          // POP defines Pair; mark the def Dead.
          BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::POP))
              .addReg(Pair, RegState::Define | RegState::Dead);
        }
      }
      return;
    }
  }

  // Tier 2 — DCX SP / INX SP x AbsN. Wins over LXI on bytes and cycles
  // for AbsN in {2, 4}; ties on bytes and loses on cycles at AbsN=6.
  // Used when PUSH/POP wasn't eligible OR no dead pair was available.
  if (AbsN == 2 || AbsN == 4) {
    unsigned Op = IsPrologue ? V6CLANG::DCX : V6CLANG::INX;
    for (unsigned I = 0; I < AbsN; ++I) {
      // INX/DCX have a tied $rp = $src constraint: pass SP as both
      // def and use.
      BuildMI(MBB, MBBI, DL, TII.get(Op), V6CLANG::SP).addReg(V6CLANG::SP);
    }
    return;
  }

  // Tier 3 — LXI HL, ±N; DAD SP; SPHL. Used for AbsN >= 6 (non-Size at
  // n=6), AbsN >= 8, and any odd size. Clobbers HL and FLAGS — caller
  // is responsible for HL save/restore around this site if needed.
  int64_t LxiImm = IsPrologue ? -static_cast<int64_t>(AbsN)
                              :  static_cast<int64_t>(AbsN);
  BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::LXI))
      .addReg(V6CLANG::HL, RegState::Define)
      .addImm(LxiImm);
  BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
  BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::SPHL));
}

bool V6ClangFrameLowering::spAdjustClobbersHL(const MachineBasicBlock &MBB,
                                          MachineBasicBlock::iterator MBBI,
                                          int64_t Amount, bool IsPrologue,
                                          V6ClangOptMode Mode) const {
  if (Amount == 0)
    return false;
  const uint64_t AbsN = static_cast<uint64_t>(Amount < 0 ? -Amount : Amount);

  // Tier 1 — PUSH/POP x (AbsN/2): does not touch HL.
  bool PushPopEligible =
      (AbsN % 2 == 0) && AbsN >= 2 &&
      (AbsN == 2 || AbsN == 4 ||
       (AbsN == 6 && Mode == V6ClangOptMode::Size));
  if (PushPopEligible &&
      chooseDeadPair(MBB, MBBI, IsPrologue) != V6CLANG::NoRegister)
    return false;

  // Tier 2 — DCX/INX SP x AbsN for AbsN in {2, 4}: does not touch HL.
  if (AbsN == 2 || AbsN == 4)
    return false;

  // Tier 3 — LXI HL, ±N; DAD SP; SPHL: clobbers HL.
  return true;
}

// Emit prologue: subtract the stack frame size from SP.
// On 8080 there is no SUB SP,imm, so we use:
//   LXI HL, -FrameSize
//   DAD SP
//   SPHL
//
// With frame pointer (BC):
//   PUSH BC           ; save old FP
//   LXI HL, 0
//   DAD SP
//   MOV B, H
//   MOV C, L          ; BC = SP (new frame pointer)
//   LXI HL, -FrameSize
//   DAD SP
//   SPHL
void V6ClangFrameLowering::emitPrologue(MachineFunction &MF,
                                     MachineBasicBlock &MBB) const {
  MachineFrameInfo &MFI = MF.getFrameInfo();
  auto *FuncInfo = MF.getInfo<V6ClangMachineFunctionInfo>();
  uint64_t StackSize = MFI.getStackSize();
  bool UseFP = hasFP(MF);
  V6ClangOptMode Mode = getV6ClangOptMode(MF);

  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();
  MachineBasicBlock::iterator MBBI = MBB.begin();
  DebugLoc DL;
  if (MBBI != MBB.end())
    DL = MBBI->getDebugLoc();

  // The prologue uses HL as scratch (LXI+DAD+SPHL) to adjust SP.
  // Determine which argument registers need saving.
  bool HLIsLiveIn = MBB.isLiveIn(V6CLANG::HL) || MBB.isLiveIn(V6CLANG::H) ||
                    MBB.isLiveIn(V6CLANG::L);
  bool DEIsLiveIn = MBB.isLiveIn(V6CLANG::DE) || MBB.isLiveIn(V6CLANG::D) ||
                    MBB.isLiveIn(V6CLANG::E);
  bool NeedSPAdjust = UseFP || StackSize > 0;

  // Case 1: Both HL and DE are live-in. Save via PUSH, reload after frame setup.
  if (HLIsLiveIn && DEIsLiveIn && NeedSPAdjust) {
    // Save both arg register pairs on the stack.
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::PUSH)).addReg(V6CLANG::HL);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::PUSH)).addReg(V6CLANG::DE);
    // Account for the 4 extra bytes in the total stack size so that
    // eliminateFrameIndex computes correct SP-relative offsets.
    uint64_t OrigStackSize = StackSize;
    StackSize += 4;
    MFI.setStackSize(StackSize);
    FuncInfo->setPrologueArgSaveSize(4);

    if (UseFP) {
      FuncInfo->setFrameCFAOffset(8);
      BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::PUSH)).addReg(V6CLANG::BC);
      BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::LXI))
          .addReg(V6CLANG::HL, RegState::Define).addImm(0);
      BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
      BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
          .addReg(V6CLANG::B, RegState::Define).addReg(V6CLANG::H);
      BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
          .addReg(V6CLANG::C, RegState::Define).addReg(V6CLANG::L);
    }

    if (OrigStackSize > 0) {
      emitSPAdjustment(MBB, MBBI, -static_cast<int64_t>(OrigStackSize), DL,
                       /*IsPrologue=*/true, Mode);
    }

    // Reload saved DE from stack: at SP + OrigStackSize.
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::LXI))
        .addReg(V6CLANG::HL, RegState::Define)
        .addImm(static_cast<int64_t>(OrigStackSize));
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrM))
        .addReg(V6CLANG::E, RegState::Define);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::INX), V6CLANG::HL).addReg(V6CLANG::HL);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrM))
        .addReg(V6CLANG::D, RegState::Define);
    // Reload saved HL: at SP + OrigStackSize + 2 (next 2 bytes on stack).
    // We need a byte scratch register to hold the L byte while loading H
    // (because the MOVrM instruction uses HL itself as the address pointer).
    //
    // Every byte register that's not H/L is either potentially live-in as
    // an argument (A, B, C, D, E) or reserved (FP). Rather than try to
    // pick a "safe" scratch via liveness analysis (which is fragile —
    // e.g. when DE is live-in as a pair, isLiveIn(E) returns false even
    // though E is semantically live), we unconditionally save/restore A
    // around the scratch use via PUSH/POP PSW. Cost is +1 byte / +21 cc,
    // only on functions hitting this Case 1 (rare).
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::PUSH))
        .addReg(V6CLANG::PSW, RegState::Undef);  // preserve A (FLAGS undef at entry)
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::INX), V6CLANG::HL).addReg(V6CLANG::HL);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrM))
        .addReg(V6CLANG::A, RegState::Define);   // A = saved L
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::INX), V6CLANG::HL).addReg(V6CLANG::HL);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrM))
        .addReg(V6CLANG::H, RegState::Define);   // H = saved H (from [HL])
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
        .addReg(V6CLANG::L, RegState::Define)
        .addReg(V6CLANG::A);                     // L = saved L (from A)
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::POP))
        .addReg(V6CLANG::PSW, RegState::Define | RegState::Dead);  // restore A
    return;
  }

  // Case 2: Only HL is live-in (DE is free). Save HL to DE via MOV pairs.
  // The save is only needed if HL will actually be clobbered by either the
  // FP setup (LXI 0; DAD SP) or the SP-adjust tier picked below.
  bool NeedHLSave = HLIsLiveIn && !DEIsLiveIn && NeedSPAdjust;
  bool HLClobberedByAdjust =
      StackSize > 0 &&
      spAdjustClobbersHL(MBB, MBBI, -static_cast<int64_t>(StackSize),
                         /*IsPrologue=*/true, Mode);
  bool DoSave = NeedHLSave && (UseFP || HLClobberedByAdjust);
  if (DoSave) {
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
        .addReg(V6CLANG::D, RegState::Define).addReg(V6CLANG::H);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
        .addReg(V6CLANG::E, RegState::Define).addReg(V6CLANG::L);
  }

  if (UseFP) {
    FuncInfo->setFrameCFAOffset(4);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::PUSH)).addReg(V6CLANG::BC);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::LXI))
        .addReg(V6CLANG::HL, RegState::Define).addImm(0);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
        .addReg(V6CLANG::B, RegState::Define).addReg(V6CLANG::H);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
        .addReg(V6CLANG::C, RegState::Define).addReg(V6CLANG::L);
  }

  if (StackSize == 0) {
    if (DoSave) {
      BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
          .addReg(V6CLANG::H, RegState::Define).addReg(V6CLANG::D);
      BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
          .addReg(V6CLANG::L, RegState::Define).addReg(V6CLANG::E);
    }
    return;
  }

  emitSPAdjustment(MBB, MBBI, -static_cast<int64_t>(StackSize), DL,
                   /*IsPrologue=*/true, Mode);

  if (DoSave) {
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
        .addReg(V6CLANG::H, RegState::Define).addReg(V6CLANG::D);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
        .addReg(V6CLANG::L, RegState::Define).addReg(V6CLANG::E);
  }
}

// Emit epilogue: add the stack frame size back to SP.
// Same approach: LXI HL, FrameSize; DAD SP; SPHL
//
// With frame pointer:
//   MOV H, B
//   MOV L, C          ; HL = BC (frame pointer = original SP)
//   SPHL              ; SP = HL (restore SP)
//   POP BC            ; restore old FP
//
// If HL carries a return value (i16/ptr), the epilogue must preserve it
// by saving to DE (MOV D,H; MOV E,L) and restoring after SP adjustment.
void V6ClangFrameLowering::emitEpilogue(MachineFunction &MF,
                                     MachineBasicBlock &MBB) const {
  MachineFrameInfo &MFI = MF.getFrameInfo();
  auto *FuncInfo = MF.getInfo<V6ClangMachineFunctionInfo>();
  uint64_t StackSize = MFI.getStackSize();
  bool UseFP = hasFP(MF);
  V6ClangOptMode Mode = getV6ClangOptMode(MF);

  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();
  MachineBasicBlock::iterator MBBI = MBB.getLastNonDebugInstr();
  DebugLoc DL;
  if (MBBI != MBB.end())
    DL = MBBI->getDebugLoc();

  // Check if HL carries a return value by inspecting the RET instruction.
  // Also check DE — if both carry return values (i32), we can't use DE as
  // scratch and must skip the save (TODO: handle i32 returns).
  bool HLUsedByRet = false;
  bool DEUsedByRet = false;
  if (MBBI != MBB.end() && MBBI->isReturn()) {
    for (const MachineOperand &MO : MBBI->operands()) {
      if (!MO.isReg()) continue;
      if (MO.getReg() == V6CLANG::HL || MO.getReg() == V6CLANG::H ||
          MO.getReg() == V6CLANG::L)
        HLUsedByRet = true;
      if (MO.getReg() == V6CLANG::DE || MO.getReg() == V6CLANG::D ||
          MO.getReg() == V6CLANG::E)
        DEUsedByRet = true;
    }
  }
  bool NeedHLSave = HLUsedByRet && !DEUsedByRet;

  if (UseFP) {
    if (NeedHLSave) {
      BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
          .addReg(V6CLANG::D, RegState::Define)
          .addReg(V6CLANG::H);
      BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
          .addReg(V6CLANG::E, RegState::Define)
          .addReg(V6CLANG::L);
    }
    // Restore SP from frame pointer: HL = BC; SPHL; POP BC
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
        .addReg(V6CLANG::H, RegState::Define)
        .addReg(V6CLANG::B);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
        .addReg(V6CLANG::L, RegState::Define)
        .addReg(V6CLANG::C);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::SPHL));
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::POP))
        .addReg(V6CLANG::BC, RegState::Define);
    if (unsigned ArgSaveSize = FuncInfo->getPrologueArgSaveSize())
      emitSPAdjustment(MBB, MBBI, static_cast<int64_t>(ArgSaveSize), DL,
                       /*IsPrologue=*/false, Mode);
    if (NeedHLSave) {
      BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
          .addReg(V6CLANG::H, RegState::Define)
          .addReg(V6CLANG::D);
      BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
          .addReg(V6CLANG::L, RegState::Define)
          .addReg(V6CLANG::E);
    }
    return;
  }

  if (StackSize == 0)
    return;

  // Only save HL if the SP-adjust tier we'll pick actually clobbers it.
  // Tier 1 (PUSH/POP PSW/...) and Tier 2 (DCX/INX SP) leave HL alone.
  bool ClobbersHL = spAdjustClobbersHL(MBB, MBBI,
                                       static_cast<int64_t>(StackSize),
                                       /*IsPrologue=*/false, Mode);
  bool DoSave = NeedHLSave && ClobbersHL;
  if (DoSave) {
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
        .addReg(V6CLANG::D, RegState::Define)
        .addReg(V6CLANG::H);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
        .addReg(V6CLANG::E, RegState::Define)
        .addReg(V6CLANG::L);
  }
  // Adjust SP back: SP += StackSize. Helper picks PUSH/POP, DCX/INX SP,
  // or LXI+DAD+SPHL based on size, opt mode, and register pressure.
  emitSPAdjustment(MBB, MBBI, static_cast<int64_t>(StackSize), DL,
                   /*IsPrologue=*/false, Mode);
  if (DoSave) {
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
        .addReg(V6CLANG::H, RegState::Define)
        .addReg(V6CLANG::D);
    BuildMI(MBB, MBBI, DL, TII.get(V6CLANG::MOVrr))
        .addReg(V6CLANG::L, RegState::Define)
        .addReg(V6CLANG::E);
  }
}

MachineBasicBlock::iterator V6ClangFrameLowering::eliminateCallFramePseudoInstr(
    MachineFunction &MF, MachineBasicBlock &MBB,
    MachineBasicBlock::iterator I) const {
  // ADJCALLSTACKDOWN / ADJCALLSTACKUP are markers.
  // On V6CLANG, stack arguments are pushed via explicit PUSH / store instructions
  // generated during call lowering. The pseudo-instructions are simply erased.
  // If the call frame is not reserved in the local frame (has calls and no FP),
  // we would need to adjust SP here. For now, callers manage SP explicitly.
  return MBB.erase(I);
}
