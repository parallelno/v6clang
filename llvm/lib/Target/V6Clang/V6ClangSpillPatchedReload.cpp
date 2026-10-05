//===-- V6ClangSpillPatchedReload.cpp - O61 rewrite ----------------*- C++ -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
// O61 (Stage 3 + Stage 4 + Stage 5): for static-stack-eligible
// functions, rewrite admissible V6CLANG_SPILL16/RELOAD16 (i16) and
// V6CLANG_SPILL8/RELOAD8 (i8) groups into patched LXI / MVI reloads
// whose imm bytes are written by SHLD / STA spills (self-modifying
// code).
//
// Filter (Stage 5):
//   * function has hasStaticStack(),
//   * i16 slot: spill src in {HL, DE, BC} (every spill); reload dst
//     in {HL, DE, BC} (every reload),
//   * i8  slot: spill src = A (Stage 4 scope; Stage 6 widens this);
//     reload dst in any GR8 (every reload).
//
// Stage 3 chooser:
//   * K <= 2 patched reloads per single-source spill,
//   * K <= 1 patched reload per multi-source spill,
//   * the 2nd-patch chooser must skip HL-target candidates (the
//     2nd-patch Delta for HL is -12 cc per the O61 design doc),
//   * score each reload as BlockFrequency(bb) * Delta(dst, HL-live-after)
//     using the per-reload cycle-saving table from the O61 design doc;
//   * pick the 1st winner from {HL, DE, BC}; pick the 2nd (if allowed)
//     from {DE, BC} only;
//   * rewrite each winner as `LXI <DstRP>, 0` with a pre-instr label
//     .Lo61_N: and MO_PATCH_IMM on the imm operand;
//   * rewrite every original spill as a sequence of one `SHLD
//     <Syms[i], MO_PATCH_IMM>` per winner (kill flag only on the last);
//   * rewrite every non-winner reload as the classical reload sequence
//     for its destination register, reading from <Syms[0], MO_PATCH_IMM>
//     instead of the BSS slot.
//
//===---------------------------------------------------------------------===//

#include "V6Clang.h"
#include "V6ClangInstrInfo.h"
#include "V6ClangMachineFunctionInfo.h"
#include "V6ClangSpillExpand.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallSet.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/CodeGen/MachineBlockFrequencyInfo.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetRegisterInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/Module.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCSymbol.h"
#include "llvm/Support/Debug.h"

#define DEBUG_TYPE "v6clang-spill-patched-reload"

using namespace llvm;

namespace {

/// Per-reload cycle saving when the reload is rewritten as a patched
/// `LXI <DstReg>, 0` (i16) or `MVI <DstReg>, 0` (i8).
///
/// Values mirror the O61 design doc "Reloads" table:
/// design/future_plans/O61_spill_in_reload_immediate.md
///
/// The i8 table uses V6CLANG's real classical-reload baseline (HL-routed
/// for non-A r8) rather than the design doc's A-routed assumption —
/// see plan_O61_spill_in_reload_immediate_stage4.md §1.
static int deltaForReload(unsigned DstReg, bool HLLive) {
  switch (DstReg) {
  // i16 (Stage 2/3).
  case V6Clang::HL: return 8;              // LHLD (20) -> LXI HL (12)
  case V6Clang::DE: return HLLive ? 16 : 12;
  case V6Clang::BC: return HLLive ? 52 : 24;
  // i8 (Stage 4).
  case V6Clang::A:  return 8;              // LDA (16) -> MVI A (8)
  case V6Clang::B:
  case V6Clang::C:
  case V6Clang::D:
  case V6Clang::E:
  case V6Clang::H:
  case V6Clang::L:  return HLLive ? 44 : 20;
  default:      return 0;
  }
}

/// True if Reg overlaps HL (either the pair itself or its 8-bit halves).
static bool isHLRelated(unsigned Reg) {
  return Reg == V6Clang::HL || Reg == V6Clang::H || Reg == V6Clang::L;
}

/// Return true when Reg can be read at I without an undef annotation. O61 uses
/// XCHG as a routing instruction; sometimes the swapped-in old HL/DE value is
/// intentionally discarded. In those cases, this helper decides whether the
/// implicit XCHG use needs an undef marker for the MIR verifier.
static bool isRegLiveBefore(MachineBasicBlock &MBB,
                            MachineBasicBlock::iterator I, unsigned Reg,
                            const TargetRegisterInfo *TRI) {
  while (I != MBB.begin()) {
    --I;
    bool FoundDef = false;
    bool FoundKilledUse = false;
    bool FoundClobber = false;
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

/// Return true if physical register Reg is dead after MI. Scans forward
/// to end of MBB, then checks successor live-ins.
///
/// Shared with V6ClangRegisterInfo.cpp via V6ClangSpillExpand.h (O64). Prior
/// Stages 2/3/4 of O61 inlined a copy of this helper; O64 consolidated
/// it into llvm::isRegDeadAfterMI.

/// Score a single reload candidate. Returns 0 if ineligible (dst not
/// in the permitted set for this slot's width, or Delta <= 0),
/// otherwise BlockFrequency * Delta.
///
/// Width selects i16 vs i8 dst set:
///   Width == 16: dst must be HL/DE/BC. AllowHL gates HL (2nd-patch
///                rule — Delta = -12 cc for HL on 2nd patch).
///   Width ==  8: dst must be any GR8. AllowHL=false forbids H/L
///                (they alias HL used in the unpatched-reload routing
///                path); AllowA=false forbids A (2nd-patch A Delta
///                = -8 cc).
static uint64_t scoreReload(const MachineInstr &R, unsigned Width,
                            bool AllowHL, bool AllowA,
                            const MachineBlockFrequencyInfo &MBFI,
                            const TargetRegisterInfo *TRI) {
  Register Dst = R.getOperand(0).getReg();
  if (Width == 16) {
    if (Dst == V6Clang::HL) {
      if (!AllowHL) return 0;
    } else if (Dst != V6Clang::DE && Dst != V6Clang::BC) {
      return 0;
    }
  } else {
    assert(Width == 8 && "Width must be 8 or 16");
    if (Dst == V6Clang::A) {
      if (!AllowA) return 0;
    } else if (Dst == V6Clang::H || Dst == V6Clang::L) {
      if (!AllowHL) return 0;
    } else if (Dst != V6Clang::B && Dst != V6Clang::C &&
               Dst != V6Clang::D && Dst != V6Clang::E) {
      return 0;
    }
  }
  MachineBasicBlock *MBB = const_cast<MachineBasicBlock *>(R.getParent());
  bool HLLive = !isPairDeadAfterMI(V6Clang::HL, R, *MBB, TRI);
  int D = deltaForReload(Dst, HLLive);
  if (D <= 0)
    return 0;
  uint64_t Freq = MBFI.getBlockFreq(MBB).getFrequency();
  return Freq * (uint64_t)D;
}

/// Return the index in `Reloads` of the best-scoring eligible
/// candidate, or -1 if no candidate is eligible. Ties keep the first
/// candidate (program order) — deterministic.
static int pickBestReload(ArrayRef<MachineInstr *> Reloads,
                          ArrayRef<int> Excluded, unsigned Width,
                          bool AllowHL, bool AllowA,
                          const MachineBlockFrequencyInfo &MBFI,
                          const TargetRegisterInfo *TRI) {
  int Best = -1;
  uint64_t BestScore = 0;
  for (size_t i = 0, n = Reloads.size(); i < n; ++i) {
    if (llvm::is_contained(Excluded, (int)i))
      continue;
    uint64_t Score =
        scoreReload(*Reloads[i], Width, AllowHL, AllowA, MBFI, TRI);
    if (Score == 0)
      continue;
    if (Best < 0 || Score > BestScore) {
      Best = (int)i;
      BestScore = Score;
    }
  }
  return Best;
}

class V6ClangSpillPatchedReload : public MachineFunctionPass {
public:
  static char ID;
  V6ClangSpillPatchedReload() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Spill Into Reload Immediate (O61)";
  }

  void getAnalysisUsage(AnalysisUsage &AU) const override {
    AU.addRequired<MachineBlockFrequencyInfo>();
    AU.setPreservesCFG();
    MachineFunctionPass::getAnalysisUsage(AU);
  }

  bool runOnMachineFunction(MachineFunction &MF) override;
};

} // end anonymous namespace

char V6ClangSpillPatchedReload::ID = 0;

bool V6ClangSpillPatchedReload::runOnMachineFunction(MachineFunction &MF) {
  if (!getV6ClangSpillPatchedReloadEnabled())
    return false;

  auto *MFI = MF.getInfo<V6ClangMachineFunctionInfo>();
  if (!MFI || !MFI->hasStaticStack())
    return false;

  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();
  const TargetRegisterInfo *TRI = MF.getSubtarget().getRegisterInfo();
  auto &MBFI = getAnalysis<MachineBlockFrequencyInfo>();

  // Group spills and reloads by frame index, preserving program order
  // via the per-FI push_back sequence.
  struct PerFI {
    SmallVector<MachineInstr *, 2> Spills;
    SmallVector<MachineInstr *, 4> Reloads;
  };
  DenseMap<int, PerFI> Slots16, Slots8;

  for (auto &MBB : MF) {
    for (auto &MI : MBB) {
      unsigned Opc = MI.getOpcode();
      if (Opc == V6Clang::V6CLANG_SPILL16)
        Slots16[MI.getOperand(1).getIndex()].Spills.push_back(&MI);
      else if (Opc == V6Clang::V6CLANG_RELOAD16)
        Slots16[MI.getOperand(1).getIndex()].Reloads.push_back(&MI);
      else if (Opc == V6Clang::V6CLANG_SPILL8)
        Slots8[MI.getOperand(1).getIndex()].Spills.push_back(&MI);
      else if (Opc == V6Clang::V6CLANG_RELOAD8)
        Slots8[MI.getOperand(1).getIndex()].Reloads.push_back(&MI);
    }
  }

  bool Changed = false;

  // Helper: emit a V6CLANG_PSEUDO_COMMENT carrying the original pseudo's
  // opcode so AsmPrinter can render `;--- <NAME> ---` headers above
  // sequences this pass injects. Only fires under -mv6clang-annotate-pseudos.
  auto annotate = [&](MachineBasicBlock &MBB,
                      MachineBasicBlock::iterator It,
                      const DebugLoc &DL, unsigned OrigOpc) {
    if (getV6ClangAnnotatePseudosEnabled())
      BuildMI(MBB, It, DL, TII.get(V6Clang::V6CLANG_PSEUDO_COMMENT))
          .addImm(OrigOpc);
  };

  // ---- i16 slots (Stages 1-3) ---------------------------------------
  for (auto &KV : Slots16) {
    PerFI &E = KV.second;

    // Stage 5 filter: >=1 spill from {HL,DE,BC}, reload dsts in {HL,DE,BC}.
    if (E.Spills.empty() || E.Reloads.empty())
      continue;
    bool AllAcceptedSources = llvm::all_of(E.Spills, [](MachineInstr *S) {
      Register Src = S->getOperand(0).getReg();
      return Src == V6Clang::HL || Src == V6Clang::DE || Src == V6Clang::BC;
    });
    if (!AllAcceptedSources)
      continue;
    bool AllSupported =
        llvm::all_of(E.Reloads, [](MachineInstr *R) {
          Register D = R->getOperand(0).getReg();
          return D == V6Clang::HL || D == V6Clang::DE || D == V6Clang::BC;
        });
    if (!AllSupported)
      continue;

    // Chooser: pick up to two reloads. K <= 2 for single-source spills,
    // K <= 1 for multi-source spills. The 2nd pick additionally
    // excludes HL-target reloads (Stage 3 2nd-patch rule).
    SmallVector<int, 2> Winners;
    int W1 = pickBestReload(E.Reloads, /*Excluded=*/{}, /*Width=*/16,
                            /*AllowHL=*/true, /*AllowA=*/true, MBFI, TRI);
    if (W1 < 0)
      continue;
    Winners.push_back(W1);

    if (E.Spills.size() == 1) {
      int Exc[] = {W1};
      int W2 = pickBestReload(E.Reloads, Exc, /*Width=*/16,
                              /*AllowHL=*/false, /*AllowA=*/true, MBFI, TRI);
      if (W2 >= 0)
        Winners.push_back(W2);
    }

    LLVM_DEBUG(dbgs() << "O61/i16: patching FI " << KV.first << " -- "
                      << E.Spills.size() << " spill(s), "
                      << E.Reloads.size() << " reload(s), K="
                      << Winners.size() << "\n");

    // Materialise one .Lo61_N label per winner.
    SmallVector<MCSymbol *, 2> Syms;
    for (size_t i = 0; i < Winners.size(); ++i)
      Syms.push_back(MF.getContext().createTempSymbol(
          "Lo61_", /*AlwaysAddSuffix=*/true));

    // The first patched reload's immediate bytes are the slot's surviving
    // storage for every spill/reload in this frame index.
    MFI->setO61PatchSymbol(KV.first, Syms.front());

    // Rewrite every original spill as a per-source ladder (HL/DE/BC)
    // ending in one SHLD per winner. Address operand on each SHLD is
    // <Syms[i], MO_PATCH_IMM>. The materialisation prefix
    // (XCHG for DE; MOV L,C; MOV H,B for BC) loads HL with the spilled
    // value once; SHLDs then store HL to each patched site. Trailing
    // fix-up (XCHG for DE; POP H for BC HL-live) is liveness-gated.
    for (MachineInstr *Spill : E.Spills) {
      MachineBasicBlock *MBB = Spill->getParent();
      DebugLoc DL = Spill->getDebugLoc();
      Register SrcReg = Spill->getOperand(0).getReg();
      bool IsKill = Spill->getOperand(0).isKill();
      bool HLDead = isPairDeadAfterMI(V6Clang::HL, *Spill, *MBB, TRI);
      annotate(*MBB, Spill, DL, V6Clang::V6CLANG_SPILL16);

      if (SrcReg == V6Clang::HL) {
        // SHLD <Sym[i], MO_PATCH_IMM> per winner. Kill HL only on the
        // last SHLD (HL must remain live across earlier SHLDs).
        for (size_t si = 0; si < Syms.size(); ++si) {
          BuildMI(*MBB, Spill, DL, TII.get(V6Clang::SHLD))
              .addReg(V6Clang::HL)
              .addSym(Syms[si], V6ClangII::MO_PATCH_IMM);
        }
      } else if (SrcReg == V6Clang::DE) {
        // XCHG; SHLD ... ; [XCHG]. Trailing XCHG is skipped iff DE is
        // killed by the spill AND HL is dead after — exactly the O42
        // rule used by the classical DE spill in
        // V6ClangRegisterInfo::eliminateFrameIndex.
        bool SkipTrailing = IsKill && HLDead;
        bool HLLiveBefore = isRegLiveBefore(*MBB, Spill->getIterator(),
                                            V6Clang::HL, TRI);
        MachineInstr *FirstXchg =
            BuildMI(*MBB, Spill, DL, TII.get(V6Clang::XCHG)).getInstr();
        if (!HLLiveBefore)
          markXchgUseUndef(FirstXchg, V6Clang::HL);
        for (size_t si = 0; si < Syms.size(); ++si) {
          BuildMI(*MBB, Spill, DL, TII.get(V6Clang::SHLD))
              .addReg(V6Clang::HL)
              .addSym(Syms[si], V6ClangII::MO_PATCH_IMM);
        }
        if (!SkipTrailing) {
          MachineInstr *SecondXchg =
              BuildMI(*MBB, Spill, DL, TII.get(V6Clang::XCHG)).getInstr();
          if (!HLLiveBefore)
            markXchgUseUndef(SecondXchg, V6Clang::DE);
        }
      } else {
        assert(SrcReg == V6Clang::BC && "Stage 5 src must be HL/DE/BC");
        // [PUSH H;] MOV L,C; MOV H,B; SHLD ... ; [POP H]. PUSH/POP HL
        // is gated by HL liveness across the spill — same rule the
        // classical BC spill in V6ClangRegisterInfo uses (O42).
        if (!HLDead)
          BuildMI(*MBB, Spill, DL, TII.get(V6Clang::PUSH)).addReg(V6Clang::HL);
        BuildMI(*MBB, Spill, DL, TII.get(V6Clang::MOVrr))
            .addReg(V6Clang::L, RegState::Define)
            .addReg(V6Clang::C, getKillRegState(IsKill));
        BuildMI(*MBB, Spill, DL, TII.get(V6Clang::MOVrr))
            .addReg(V6Clang::H, RegState::Define)
            .addReg(V6Clang::B, getKillRegState(IsKill));
        for (size_t si = 0; si < Syms.size(); ++si) {
          // HL is restored by the trailing POP H (when emitted) or
          // dead after the last SHLD (when HLDead skipped PUSH/POP).
          // Kill on the last SHLD only when no POP follows.
          BuildMI(*MBB, Spill, DL, TII.get(V6Clang::SHLD))
            .addReg(V6Clang::HL)
              .addSym(Syms[si], V6ClangII::MO_PATCH_IMM);
        }
        if (!HLDead)
          BuildMI(*MBB, Spill, DL, TII.get(V6Clang::POP), V6Clang::HL);
      }
      Spill->eraseFromParent();
    }

    // Each winner reload becomes the patched site: LXI <DstRP>, 0 with
    // a pre-instr label and MO_PATCH_IMM on the imm operand.
    for (size_t wi = 0; wi < Winners.size(); ++wi) {
      MachineInstr *PR = E.Reloads[Winners[wi]];
      MachineBasicBlock *MBB = PR->getParent();
      DebugLoc DL = PR->getDebugLoc();
      Register WinnerDst = PR->getOperand(0).getReg();
      annotate(*MBB, PR, DL, V6Clang::V6CLANG_RELOAD16);
      MachineInstrBuilder NewLxi =
          BuildMI(*MBB, PR, DL, TII.get(V6Clang::LXI))
              .addReg(WinnerDst, RegState::Define)
              .addImm(0);
      NewLxi->getOperand(1).setTargetFlags(V6ClangII::MO_PATCH_IMM);
      NewLxi->setPreInstrSymbol(MF, Syms[wi]);
      PR->eraseFromParent();
    }

    // Every non-winner reload becomes the classical reload sequence for
    // its destination register, reading from Syms[0]+1 (the first
    // patched site's imm bytes serve as the shared slot storage). These
    // sequences mirror the static-stack expansion in
    // V6ClangRegisterInfo::eliminateFrameIndex.
    auto isWinner = [&](size_t i) {
      return llvm::is_contained(Winners, (int)i);
    };
    for (size_t i = 0, n = E.Reloads.size(); i < n; ++i) {
      if (isWinner(i))
        continue;
      MachineInstr *R = E.Reloads[i];
      MachineBasicBlock *MBB = R->getParent();
      DebugLoc DL = R->getDebugLoc();
      Register Dst = R->getOperand(0).getReg();
      // Check H and L independently: isRegDeadAfterMI(HL,...) stops at the
      // first def of *either* half, which is too conservative when only one
      // half is live as an individual byte after the reload.  If LHLD is used
      // without PUSH/POP, it clobbers both H and L, so we must preserve HL
      // whenever either sub-register is still live.
      bool HLLive = !isRegDeadAfterMI(V6Clang::H, *R, *MBB, TRI) ||
                    !isRegDeadAfterMI(V6Clang::L, *R, *MBB, TRI);
      annotate(*MBB, R, DL, V6Clang::V6CLANG_RELOAD16);

      if (Dst == V6Clang::HL) {
        // LHLD <Syms[0], MO_PATCH_IMM>   (20cc, 3B)
        BuildMI(*MBB, R, DL, TII.get(V6Clang::LHLD), V6Clang::HL)
            .addSym(Syms[0], V6ClangII::MO_PATCH_IMM);
      } else if (Dst == V6Clang::DE) {
        if (HLLive) {
          // XCHG; LHLD ... ; XCHG  (28cc, 5B)
          MachineInstr *FirstXchg =
              BuildMI(*MBB, R, DL, TII.get(V6Clang::XCHG)).getInstr();
          BuildMI(*MBB, R, DL, TII.get(V6Clang::LHLD), V6Clang::HL)
              .addSym(Syms[0], V6ClangII::MO_PATCH_IMM);
          BuildMI(*MBB, R, DL, TII.get(V6Clang::XCHG));
          if (MachineOperand *MO = FirstXchg->findRegisterUseOperand(
                  V6Clang::DE, /*isKill=*/false))
            MO->setIsUndef(true);
        } else {
          // LHLD ... ; XCHG        (24cc, 4B)
          BuildMI(*MBB, R, DL, TII.get(V6Clang::LHLD), V6Clang::HL)
              .addSym(Syms[0], V6ClangII::MO_PATCH_IMM);
          MachineInstr *XchgMI =
            BuildMI(*MBB, R, DL, TII.get(V6Clang::XCHG)).getInstr();
          if (MachineOperand *MO = XchgMI->findRegisterUseOperand(
              V6Clang::DE, /*isKill=*/false))
          MO->setIsUndef(true);
        }
      } else {
        assert(Dst == V6Clang::BC && "Stage 3 reload dst must be HL/DE/BC");
        if (HLLive) {
          // PUSH HL; LHLD ... ; MOV C,L; MOV B,H; POP HL  (64cc, 7B)
          BuildMI(*MBB, R, DL, TII.get(V6Clang::PUSH)).addReg(V6Clang::HL);
          BuildMI(*MBB, R, DL, TII.get(V6Clang::LHLD), V6Clang::HL)
              .addSym(Syms[0], V6ClangII::MO_PATCH_IMM);
          BuildMI(*MBB, R, DL, TII.get(V6Clang::MOVrr))
              .addReg(V6Clang::C, RegState::Define).addReg(V6Clang::L);
          BuildMI(*MBB, R, DL, TII.get(V6Clang::MOVrr))
              .addReg(V6Clang::B, RegState::Define).addReg(V6Clang::H);
          BuildMI(*MBB, R, DL, TII.get(V6Clang::POP), V6Clang::HL);
        } else {
          // LHLD ... ; MOV C,L; MOV B,H  (36cc, 5B)
          BuildMI(*MBB, R, DL, TII.get(V6Clang::LHLD), V6Clang::HL)
              .addSym(Syms[0], V6ClangII::MO_PATCH_IMM);
          BuildMI(*MBB, R, DL, TII.get(V6Clang::MOVrr))
              .addReg(V6Clang::C, RegState::Define).addReg(V6Clang::L);
          BuildMI(*MBB, R, DL, TII.get(V6Clang::MOVrr))
              .addReg(V6Clang::B, RegState::Define).addReg(V6Clang::H);
        }
      }
      R->eraseFromParent();
    }

    Changed = true;
  }

  // ---- i8 slots (Stage 4 + Stage 6) ---------------------------------
  for (auto &KV : Slots8) {
    PerFI &E = KV.second;

    // Stage 6 filter: accept any GR8 spill source (A-sourced and
    // non-A sourced slots use different emitters in the rewrite
    // loop below). Reload dsts must be any GR8 (unchanged).
    if (E.Spills.empty() || E.Reloads.empty())
      continue;
    bool AllASources = llvm::all_of(E.Spills, [](MachineInstr *S) {
      return S->getOperand(0).getReg() == V6Clang::A;
    });
    bool AllSupportedR8 =
        llvm::all_of(E.Reloads, [](MachineInstr *R) {
          Register D = R->getOperand(0).getReg();
          return D == V6Clang::A || D == V6Clang::B || D == V6Clang::C ||
                 D == V6Clang::D || D == V6Clang::E || D == V6Clang::H ||
                 D == V6Clang::L;
        });
    if (!AllSupportedR8)
      continue;

    // Chooser: same K caps as i16. 2nd-patch skips A (Delta = -8 cc)
    // and H/L (aliases HL used in unpatched-reload routing).
    // Stage 6 additionally caps K=1 when any spill source is non-A:
    // the shared O64 ladder would have to repeat its terminal store
    // for a 2nd patched site, which the design doc defers.
    SmallVector<int, 2> Winners;
    int W1 = pickBestReload(E.Reloads, /*Excluded=*/{}, /*Width=*/8,
                            /*AllowHL=*/true, /*AllowA=*/true, MBFI, TRI);
    if (W1 < 0)
      continue;
    Winners.push_back(W1);

    if (AllASources && E.Spills.size() == 1) {
      int Exc[] = {W1};
      int W2 = pickBestReload(E.Reloads, Exc, /*Width=*/8,
                              /*AllowHL=*/false, /*AllowA=*/false, MBFI, TRI);
      if (W2 >= 0)
        Winners.push_back(W2);
    }

    LLVM_DEBUG(dbgs() << "O61/i8: patching FI " << KV.first << " -- "
                      << E.Spills.size() << " spill(s), "
                      << E.Reloads.size() << " reload(s), K="
                      << Winners.size() << "\n");

    SmallVector<MCSymbol *, 2> Syms;
    for (size_t i = 0; i < Winners.size(); ++i)
      Syms.push_back(MF.getContext().createTempSymbol(
          "Lo61_", /*AlwaysAddSuffix=*/true));

    // Spill rewrite: per-source switch.
    //   A source      -> one STA <Sym[i]+1> per winner (kill on last).
    //   non-A source  -> expandSpill8Static (O64 shared ladder) with
    //                    an appender that supplies <Syms[0]+MO_PATCH_IMM>.
    //                    Stage 6 hard-caps K=1 for non-A sources.
    for (MachineInstr *Spill : E.Spills) {
      MachineBasicBlock *MBB = Spill->getParent();
      DebugLoc DL = Spill->getDebugLoc();
      Register SrcReg = Spill->getOperand(0).getReg();
      bool IsKill = Spill->getOperand(0).isKill();
      annotate(*MBB, Spill, DL, V6Clang::V6CLANG_SPILL8);

      if (SrcReg == V6Clang::A) {
        for (size_t si = 0; si < Syms.size(); ++si) {
          bool Kill = IsKill && (si + 1 == Syms.size());
          BuildMI(*MBB, Spill, DL, TII.get(V6Clang::STA))
              .addReg(V6Clang::A, getKillRegState(Kill))
              .addSym(Syms[si], V6ClangII::MO_PATCH_IMM);
        }
      } else {
        assert(Syms.size() == 1 &&
               "Stage 6 caps K=1 for non-A i8 spills");
        expandSpill8Static(*Spill, Spill, SrcReg, IsKill, TII, TRI,
            [&](MachineInstrBuilder &B) {
              B.addSym(Syms[0], V6ClangII::MO_PATCH_IMM);
            });
      }
      Spill->eraseFromParent();
    }

    // Each winner reload becomes MVI <DstReg>, 0 at .Lo61_N.
    for (size_t wi = 0; wi < Winners.size(); ++wi) {
      MachineInstr *PR = E.Reloads[Winners[wi]];
      MachineBasicBlock *MBB = PR->getParent();
      DebugLoc DL = PR->getDebugLoc();
      Register WinnerDst = PR->getOperand(0).getReg();
      annotate(*MBB, PR, DL, V6Clang::V6CLANG_RELOAD8);
      MachineInstrBuilder NewMvi =
          BuildMI(*MBB, PR, DL, TII.get(V6Clang::MVIr))
              .addReg(WinnerDst, RegState::Define)
              .addImm(0);
      NewMvi->getOperand(1).setTargetFlags(V6ClangII::MO_PATCH_IMM);
      NewMvi->setPreInstrSymbol(MF, Syms[wi]);
      PR->eraseFromParent();
    }

    // Unpatched i8 reloads: share the O64 decision ladder with
    // V6ClangRegisterInfo::eliminateFrameIndex, but with the address
    // operand supplied as <Syms[0], MO_PATCH_IMM> instead of a
    // GlobalAddress+offset.
    auto isWinner = [&](size_t i) {
      return llvm::is_contained(Winners, (int)i);
    };
    for (size_t i = 0, n = E.Reloads.size(); i < n; ++i) {
      if (isWinner(i))
        continue;
      MachineInstr *R = E.Reloads[i];
      MachineBasicBlock *MBB = R->getParent();
      DebugLoc DL = R->getDebugLoc();
      Register Dst = R->getOperand(0).getReg();
      annotate(*MBB, R, DL, V6Clang::V6CLANG_RELOAD8);

      if (Dst == V6Clang::A) {
        // LDA <Syms[0], MO_PATCH_IMM>   (16cc, 3B)
        BuildMI(*MBB, R, DL, TII.get(V6Clang::LDA), V6Clang::A)
            .addSym(Syms[0], V6ClangII::MO_PATCH_IMM);
      } else {
        // O64 ladder handles Shape B and Shape C.
        expandReload8Static(*R, R, Dst, TII, TRI,
            [&](MachineInstrBuilder &B) {
              B.addSym(Syms[0], V6ClangII::MO_PATCH_IMM);
            });
      }
      R->eraseFromParent();
    }

    Changed = true;
  }

  // ---- Dead-BSS compaction ----------------------------------------
  // After rewriting, slots whose spills/reloads were all redirected to
  // the patched `.Lo61_N+1` code-symbol addresses no longer reference
  // the backing `__v6clang_ss.<func>` global.  Drop dead FIs from the
  // static-slot map, repack surviving offsets contiguously, and resize
  // (or erase) the backing GlobalVariable so AsmPrinter emits a smaller
  // `.comm` — or none at all.
  if (Changed) {
    // Collect the set of frame indices still referenced by any
    // MachineOperand in the function.
    SmallSet<int, 8> LiveFIs;
    for (auto &MBB : MF) {
      for (auto &MI : MBB) {
        for (const MachineOperand &MO : MI.operands()) {
          if (MO.isFI())
            LiveFIs.insert(MO.getIndex());
        }
      }
    }

    // Walk the existing static-slot map and drop dead entries.
    SmallVector<int, 8> DeadFIs;
    for (auto &KV : MFI->getStaticSlotMap()) {
      if (!LiveFIs.contains(KV.first))
        DeadFIs.push_back(KV.first);
    }

    if (!DeadFIs.empty()) {
      for (int FI : DeadFIs)
        MFI->eraseStaticSlot(FI);

      // Repack: reassign offsets monotonically by ascending FI order
      // (matching the original V6ClangStaticStackAlloc layout policy).
      SmallVector<std::pair<int, int64_t>, 8> Live;
      for (auto &KV : MFI->getStaticSlotMap())
        Live.emplace_back(KV.first, MFI->getStaticSize(KV.first));
      llvm::sort(Live, [](const auto &A, const auto &B) {
        return A.first < B.first;
      });

      int64_t NewTotal = 0;
      for (auto &P : Live) {
        MFI->setStaticOffset(P.first, NewTotal);
        NewTotal += P.second;
      }

      GlobalVariable *OldGV = MFI->getStaticStackGV();
      Module *M = MF.getFunction().getParent();
      LLVMContext &Ctx = M->getContext();

      if (NewTotal == 0) {
        // Every slot was patched away.  Drop the GV entirely.
        LLVM_DEBUG(dbgs() << "V6ClangSpillPatchedReload: all static slots "
                             "eliminated in "
                          << MF.getName() << ", erasing "
                          << OldGV->getName() << "\n");
        MFI->replaceStaticStackGV(nullptr);
        if (OldGV->use_empty())
          OldGV->eraseFromParent();
      } else if (NewTotal != (int64_t)cast<ArrayType>(
                                 OldGV->getValueType())->getNumElements()) {
        // Shrunk.  Replace with a new, smaller GV (type cannot be
        // mutated in place).  No IR-level users reference it before
        // PEI runs, so RAUW is a no-op; we just rename+erase.
        auto *NewArrTy = ArrayType::get(Type::getInt8Ty(Ctx), NewTotal);
        std::string Name = OldGV->getName().str();
        // Temporarily rename the old GV so the new one can reuse the
        // canonical `__v6clang_ss.<func>` name expected by downstream
        // consumers and lit tests.
        OldGV->setName(Name + ".dead");
        auto *NewGV = new GlobalVariable(
            *M, NewArrTy, /*isConstant=*/false,
            GlobalValue::InternalLinkage,
            ConstantAggregateZero::get(NewArrTy), Name);
        NewGV->setAlignment(Align(1));
        MFI->replaceStaticStackGV(NewGV);
        if (OldGV->use_empty())
          OldGV->eraseFromParent();
        LLVM_DEBUG(dbgs() << "V6ClangSpillPatchedReload: shrunk "
                          << NewGV->getName() << " to " << NewTotal
                          << " bytes in " << MF.getName() << "\n");
      }
    }
  }

  return Changed;
}

namespace llvm {
FunctionPass *createV6ClangSpillPatchedReloadPass() {
  return new V6ClangSpillPatchedReload();
}
} // namespace llvm
