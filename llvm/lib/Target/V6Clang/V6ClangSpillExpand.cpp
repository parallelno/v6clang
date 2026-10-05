//===-- V6ClangSpillExpand.cpp - Shared i8 spill/reload expander --------------===//
//
// Part of the V6CLANG backend for LLVM.
//
// See V6ClangSpillExpand.h.
//
//===----------------------------------------------------------------------===//

#include "V6ClangSpillExpand.h"
#include "V6Clang.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetRegisterInfo.h"

using namespace llvm;

/// Return true if Reg has no non-undef overlapping use before an overlapping
/// def, and is not live into a successor.
///
/// Pair-register caveat: when called with HL/DE/BC this tracks liveness of the
/// old pair value, not independent liveness of both 8-bit halves. A later def
/// of L kills the old HL value even if H is still live as a separate byte. Any
/// expansion that wants to clobber a whole pair without restoring it must check
/// the halves explicitly instead of relying on a pair query here.
bool llvm::isRegDeadAfterMI(unsigned Reg, const MachineInstr &MI,
                            MachineBasicBlock &MBB,
                            const TargetRegisterInfo *TRI) {
  for (auto I = std::next(MI.getIterator()); I != MBB.end(); ++I) {
    bool usesReg = false, defsReg = false;
    for (const MachineOperand &MO : I->operands()) {
      if (!MO.isReg() || !TRI->regsOverlap(MO.getReg(), Reg))
        continue;
      if (MO.isUse() && !MO.isUndef())
        usesReg = true;
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

bool llvm::isPairDeadAfterMI(unsigned PairReg, const MachineInstr &MI,
                             MachineBasicBlock &MBB,
                             const TargetRegisterInfo *TRI) {
  // Determine the pair's two 8-bit sub-registers.  Hard-coded so we
  // don't need the V6CLANG-specific TRI; the helper lives in code that is
  // already V6CLANG-scoped via V6ClangMCTargetDesc.h.
  unsigned Lo = 0, Hi = 0;
  switch (PairReg) {
  case V6Clang::HL: Lo = V6Clang::L; Hi = V6Clang::H; break;
  case V6Clang::DE: Lo = V6Clang::E; Hi = V6Clang::D; break;
  case V6Clang::BC: Lo = V6Clang::C; Hi = V6Clang::B; break;
  default:
    // For non-pair registers fall back to the byte-wise query.
    return isRegDeadAfterMI(PairReg, MI, MBB, TRI);
  }
  return isRegDeadAfterMI(Lo, MI, MBB, TRI) &&
         isRegDeadAfterMI(Hi, MI, MBB, TRI);
}

Register llvm::findDeadSpareGPR8(Register Excluded, const MachineInstr &MI,
                                 MachineBasicBlock &MBB,
                                 const TargetRegisterInfo *TRI) {
  static const MCPhysReg Candidates[] = {V6Clang::B, V6Clang::C, V6Clang::D, V6Clang::E};
  BitVector Reserved = TRI->getReservedRegs(*MBB.getParent());
  for (MCPhysReg R : Candidates) {
    if (Reserved.test(R))
      continue;
    if (Excluded && TRI->regsOverlap(R, Excluded))
      continue;
    if (isRegDeadAfterMI(R, MI, MBB, TRI))
      return Register(R);
  }
  return Register();
}

void llvm::expandSpill8Static(MachineInstr &MI,
                              MachineBasicBlock::iterator InsertBefore,
                              Register SrcReg, bool SrcIsKill,
                              const TargetInstrInfo &TII,
                              const TargetRegisterInfo *TRI,
                              AppendAddrFn AppendAddr) {
  MachineBasicBlock &MBB = *MI.getParent();
  DebugLoc DL = MI.getDebugLoc();

  // Shape C: SrcReg is H or L. A is the only possible router.
  if (SrcReg == V6Clang::H || SrcReg == V6Clang::L) {
    bool ADead = isRegDeadAfterMI(V6Clang::A, MI, MBB, TRI);
    // Row 1: A dead -> MOV A, H|L ; STA addr
    if (ADead) {
      BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
          .addReg(V6Clang::A, RegState::Define)
          .addReg(SrcReg, getKillRegState(SrcIsKill));
      auto B = BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::STA))
                   .addReg(V6Clang::A);
      AppendAddr(B);
      return;
    }
    // Row 2: A live, Tmp in {B,C,D,E} dead -> save A in Tmp, route, restore.
    Register Tmp = findDeadSpareGPR8(/*Excluded=*/Register(), MI, MBB, TRI);
    if (Tmp) {
      BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
          .addReg(Tmp, RegState::Define)
          .addReg(V6Clang::A);
      BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
          .addReg(V6Clang::A, RegState::Define)
          .addReg(SrcReg, getKillRegState(SrcIsKill));
      auto B = BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::STA))
                   .addReg(V6Clang::A);
      AppendAddr(B);
      BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
          .addReg(V6Clang::A, RegState::Define)
          .addReg(Tmp, RegState::Kill);
      return;
    }
    // Row 3 (fallback): PUSH PSW ; MOV A, H|L ; STA addr ; POP PSW
    BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::PUSH)).addReg(V6Clang::PSW);
    BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
        .addReg(V6Clang::A, RegState::Define)
        .addReg(SrcReg, getKillRegState(SrcIsKill));
    auto B = BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::STA))
                 .addReg(V6Clang::A);
    AppendAddr(B);
    BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::POP), V6Clang::PSW);
    return;
  }

  // Shape B: SrcReg in {B, C, D, E}.
  assert((SrcReg == V6Clang::B || SrcReg == V6Clang::C ||
          SrcReg == V6Clang::D || SrcReg == V6Clang::E) &&
         "expandSpill8Static: expected GR8 src (A handled by caller)");

  bool HLDead = isPairDeadAfterMI(V6Clang::HL, MI, MBB, TRI);
  // Row 1: HL dead -> LXI HL, addr ; MOV M, r
  if (HLDead) {
    auto B = BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::LXI))
                 .addReg(V6Clang::HL, RegState::Define);
    AppendAddr(B);
    BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVMr))
        .addReg(SrcReg, getKillRegState(SrcIsKill));
    return;
  }
  bool ADead = isRegDeadAfterMI(V6Clang::A, MI, MBB, TRI);
  // Row 2: HL live, A dead -> MOV A, r ; STA addr
  if (ADead) {
    BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
        .addReg(V6Clang::A, RegState::Define)
        .addReg(SrcReg, getKillRegState(SrcIsKill));
    auto B = BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::STA))
                 .addReg(V6Clang::A);
    AppendAddr(B);
    return;
  }
  // Row 3: HL live, A live, Tmp in {B,C,D,E}\{r} dead
  Register Tmp = findDeadSpareGPR8(/*Excluded=*/SrcReg, MI, MBB, TRI);
  if (Tmp) {
    BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
        .addReg(Tmp, RegState::Define)
        .addReg(V6Clang::A);
    BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
        .addReg(V6Clang::A, RegState::Define)
        .addReg(SrcReg, getKillRegState(SrcIsKill));
    auto B = BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::STA))
                 .addReg(V6Clang::A);
    AppendAddr(B);
    BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
        .addReg(V6Clang::A, RegState::Define)
        .addReg(Tmp, RegState::Kill);
    return;
  }
  // Row 4 (fallback): PUSH HL ; LXI HL, addr ; MOV M, r ; POP HL
  BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::PUSH)).addReg(V6Clang::HL);
  auto B = BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::LXI))
               .addReg(V6Clang::HL, RegState::Define);
  AppendAddr(B);
  BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVMr))
      .addReg(SrcReg, getKillRegState(SrcIsKill));
  BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::POP), V6Clang::HL);
}

void llvm::expandReload8Static(MachineInstr &MI,
                               MachineBasicBlock::iterator InsertBefore,
                               Register DstReg,
                               const TargetInstrInfo &TII,
                               const TargetRegisterInfo *TRI,
                               AppendAddrFn AppendAddr) {
  MachineBasicBlock &MBB = *MI.getParent();
  DebugLoc DL = MI.getDebugLoc();

  // Shape C: DstReg is H or L. Need to set one half of HL without
  // clobbering the other (unless the other is dead).
  if (DstReg == V6Clang::H || DstReg == V6Clang::L) {
    Register OtherHL = (DstReg == V6Clang::H) ? V6Clang::L : V6Clang::H;
    bool OtherHLDead = isRegDeadAfterMI(OtherHL, MI, MBB, TRI);
    // Row 1: other half dead -> LXI HL, addr ; MOV Dst, M
    if (OtherHLDead) {
      auto B = BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::LXI))
                   .addReg(V6Clang::HL, RegState::Define);
      AppendAddr(B);
      BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrM))
          .addReg(DstReg, RegState::Define);
      return;
    }
    bool ADead = isRegDeadAfterMI(V6Clang::A, MI, MBB, TRI);
    // Row 2: A dead -> LDA addr ; MOV Dst, A
    if (ADead) {
      auto B = BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::LDA), V6Clang::A);
      AppendAddr(B);
      BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
          .addReg(DstReg, RegState::Define)
          .addReg(V6Clang::A, RegState::Kill);
      return;
    }
    // Row 3: A live, Tmp in {B,C,D,E} dead -> save A in Tmp, route, restore.
    Register Tmp = findDeadSpareGPR8(/*Excluded=*/Register(), MI, MBB, TRI);
    if (Tmp) {
      BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
          .addReg(Tmp, RegState::Define)
          .addReg(V6Clang::A);
      auto B = BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::LDA), V6Clang::A);
      AppendAddr(B);
      BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
          .addReg(DstReg, RegState::Define)
          .addReg(V6Clang::A);
      BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
          .addReg(V6Clang::A, RegState::Define)
          .addReg(Tmp, RegState::Kill);
      return;
    }
    // Row 4 (fallback): PUSH PSW ; LDA addr ; MOV Dst, A ; POP PSW
    BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::PUSH)).addReg(V6Clang::PSW);
    auto B = BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::LDA), V6Clang::A);
    AppendAddr(B);
    BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
        .addReg(DstReg, RegState::Define)
        .addReg(V6Clang::A);
    BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::POP), V6Clang::PSW);
    return;
  }

  // Shape B: DstReg in {B, C, D, E}.
  assert((DstReg == V6Clang::B || DstReg == V6Clang::C ||
          DstReg == V6Clang::D || DstReg == V6Clang::E) &&
         "expandReload8Static: expected GR8 dst (A handled by caller)");

  bool HLDead = isPairDeadAfterMI(V6Clang::HL, MI, MBB, TRI);
  // Row 1: HL dead -> LXI HL, addr ; MOV r, M
  if (HLDead) {
    auto B = BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::LXI))
                 .addReg(V6Clang::HL, RegState::Define);
    AppendAddr(B);
    BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrM))
        .addReg(DstReg, RegState::Define);
    return;
  }
  bool ADead = isRegDeadAfterMI(V6Clang::A, MI, MBB, TRI);
  // Row 2: HL live, A dead -> LDA addr ; MOV r, A
  if (ADead) {
    auto B = BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::LDA), V6Clang::A);
    AppendAddr(B);
    BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
        .addReg(DstReg, RegState::Define)
        .addReg(V6Clang::A, RegState::Kill);
    return;
  }
  // Row 3: HL live, A live, Tmp in {B,C,D,E}\{Dst} dead.
  Register Tmp = findDeadSpareGPR8(/*Excluded=*/DstReg, MI, MBB, TRI);
  if (Tmp) {
    BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
        .addReg(Tmp, RegState::Define)
        .addReg(V6Clang::A);
    auto B = BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::LDA), V6Clang::A);
    AppendAddr(B);
    BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
        .addReg(DstReg, RegState::Define)
        .addReg(V6Clang::A);
    BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrr))
        .addReg(V6Clang::A, RegState::Define)
        .addReg(Tmp, RegState::Kill);
    return;
  }
  // Row 4 (fallback): PUSH HL ; LXI HL, addr ; MOV r, M ; POP HL
  BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::PUSH)).addReg(V6Clang::HL);
  auto B = BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::LXI))
               .addReg(V6Clang::HL, RegState::Define);
  AppendAddr(B);
  BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::MOVrM))
      .addReg(DstReg, RegState::Define);
  BuildMI(MBB, InsertBefore, DL, TII.get(V6Clang::POP), V6Clang::HL);
}
