//===-- V6ClangLoadImmCombine.cpp - Combine redundant MVI instructions --------===//
//
// Part of the V6CLANG backend for LLVM.
//
// Post-RA peephole: Replace redundant MVI r, imm instructions when the
// value is already available in another register (→ MOV r, r') or the
// target register holds imm±1 (→ INR r / DCR r).
//
// Algorithm (per basic block, with cross-BB propagation for single-predecessor blocks):
//   KnownVal[r] = nullopt for all r
//   for each MI:
//     if MI is MVI r, imm:
//       if ∃ r' ≠ r with KnownVal[r'] == imm: replace with MOV r, r'
//       else if KnownVal[r] == imm - 1: replace with INR r
//       else if KnownVal[r] == imm + 1: replace with DCR r
//       KnownVal[r] = imm
//     else: update tracking (invalidate when register modified)
//
// Savings: 1 byte per MVI→MOV, 1 byte per MVI→INR/DCR (same cycle cost).
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
// Note: we only need the numeric value of V6ClangII::MO_PATCH_IMM, and
// deliberately avoid including V6ClangInstrInfo.h to keep this pass's
// dependency surface small. Keep this constant in sync with
// V6ClangInstrInfo.h.
static constexpr unsigned V6CLANG_MO_PATCH_IMM = 4;

/// A MachineOperand counts as a "plain" immediate (trackable by this
/// pass) iff it is an immediate AND carries no target flags. O61's
/// MO_PATCH_IMM marks an MVI/LXI whose imm bytes are overwritten at
/// runtime by a spill — the compile-time value is not a reliable
/// constant, so such operands must be treated as opaque.
static bool isPlainImm(const llvm::MachineOperand &MO) {
  return MO.isImm() && MO.getTargetFlags() == 0;
}

#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/Support/CommandLine.h"

#include <optional>

using namespace llvm;

#define DEBUG_TYPE "v6clang-load-imm-combine"

static cl::opt<bool> DisableLoadImmCombine(
    "v6clang-disable-load-imm-combine",
    cl::desc("Disable V6CLANG load-immediate combining"),
    cl::init(false), cl::Hidden);

namespace {

class V6ClangLoadImmCombine : public MachineFunctionPass {
public:
  static char ID;
  V6ClangLoadImmCombine() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Load-Immediate Combining";
  }

  bool runOnMachineFunction(MachineFunction &MF) override;

private:
  // Tracked registers: A, B, C, D, E, H, L (indices 0-6).
  static constexpr unsigned NumTracked = 7;
  static constexpr MCRegister TrackedRegs[NumTracked] = {
      V6CLANG::A, V6CLANG::B, V6CLANG::C, V6CLANG::D, V6CLANG::E, V6CLANG::H, V6CLANG::L};

  std::optional<int64_t> KnownVal[NumTracked];

  /// Map physical register to tracking index, or -1 if not tracked.
  static int regIndex(MCRegister Reg) {
    for (unsigned I = 0; I < NumTracked; ++I)
      if (TrackedRegs[I] == Reg)
        return I;
    return -1;
  }

  /// Invalidate a single register.
  void invalidate(MCRegister Reg) {
    int Idx = regIndex(Reg);
    if (Idx >= 0)
      KnownVal[Idx] = std::nullopt;
  }

  /// Invalidate all tracked registers.
  void invalidateAll() {
    for (unsigned I = 0; I < NumTracked; ++I)
      KnownVal[I] = std::nullopt;
  }

  /// Seed known register values at BB entry from a single predecessor's
  /// terminator.  Only applicable when MBB has exactly one predecessor
  /// and is that predecessor's layout-fallthrough successor.
  ///
  /// Recognized patterns (NZ-branch terminators only — fallthrough = Z):
  ///   Pattern A: MOV A,rHi; ORA rLo; RNZ/JNZ  → H=0,L=0,A=0 (or D,E,A)
  ///   Pattern B: ORA A / ANA A; RNZ/JNZ        → A=0
  ///   Pattern C: CPI imm; JNZ                  → A=imm
  bool seedPredecessorValues(MachineBasicBlock &MBB);

  /// O29: For blocks with a single predecessor, forward-scan the
  /// predecessor's instructions to compute register exit state and use
  /// it as initial KnownVal[].  Falls back to invalidateAll() when the
  /// block has multiple predecessors.
  void initFromPredecessor(MachineBasicBlock &MBB);

  /// Invalidate register and its sub/super-registers relevant to tracking.
  void invalidateWithSubSuper(MCRegister Reg) {
    invalidate(Reg);
    // If a 16-bit pair is written, invalidate both halves.
    if (Reg == V6CLANG::BC) { invalidate(V6CLANG::B); invalidate(V6CLANG::C); }
    if (Reg == V6CLANG::DE) { invalidate(V6CLANG::D); invalidate(V6CLANG::E); }
    if (Reg == V6CLANG::HL) { invalidate(V6CLANG::H); invalidate(V6CLANG::L); }
    // If an 8-bit register is written, no pair invalidation needed
    // (the pair "value" is just both halves).
  }

  void invalidateUndefUses(const MachineInstr &MI) {
    for (const MachineOperand &MO : MI.operands()) {
      if (MO.isReg() && MO.isUse() && MO.isUndef() && MO.getReg().isPhysical())
        invalidateWithSubSuper(MO.getReg());
    }
  }

  void invalidateKilledUses(const MachineInstr &MI) {
    for (const MachineOperand &MO : MI.operands()) {
      if (MO.isReg() && MO.isUse() && MO.isKill() && MO.getReg().isPhysical())
        invalidateWithSubSuper(MO.getReg());
    }
  }

  /// Find a tracked register (other than Exclude) that holds Val.
  /// Prefer non-A registers to avoid accumulator contention.
  MCRegister findRegWithValue(int64_t Val, MCRegister Exclude) const {
    // First pass: non-A registers.
    for (unsigned I = 1; I < NumTracked; ++I) {
      if (TrackedRegs[I] == Exclude)
        continue;
      if (KnownVal[I] && *KnownVal[I] == Val)
        return TrackedRegs[I];
    }
    // Second pass: A register.
    if (TrackedRegs[0] != Exclude && KnownVal[0] && *KnownVal[0] == Val)
      return TrackedRegs[0];
    return MCRegister();
  }

  void dropEntryValuesNotLiveIn(MachineBasicBlock &MBB,
                                const TargetRegisterInfo *TRI) {
    for (unsigned I = 0; I < NumTracked; ++I) {
      bool LiveIn = false;
      for (MCRegAliasIterator AI(TrackedRegs[I], TRI, /*IncludeSelf=*/true);
           AI.isValid(); ++AI) {
        if (MBB.isLiveIn(*AI)) {
          LiveIn = true;
          break;
        }
      }
      if (!LiveIn)
        KnownVal[I] = std::nullopt;
    }
  }

  bool processBlock(MachineBasicBlock &MBB);
};

} // end anonymous namespace

char V6ClangLoadImmCombine::ID = 0;

/// Check whether Opc is a NZ-branch terminator (JNZ or RNZ).
/// Fallthrough of an NZ-branch means the Z flag was set (zero/equal).
static bool isNZBranchTerminator(unsigned Opc) {
  return Opc == V6CLANG::JNZ || Opc == V6CLANG::RNZ;
}

/// Check whether Opc is a Z-branch terminator (JZ only — RZ has no target).
/// The taken path of a Z-branch receives the Z=1 (zero/equal) condition.
static bool isZBranchTerminator(unsigned Opc) {
  return Opc == V6CLANG::JZ;
}

bool V6ClangLoadImmCombine::seedPredecessorValues(MachineBasicBlock &MBB) {
  // Require exactly one predecessor.
  if (MBB.pred_size() != 1)
    return false;

  MachineBasicBlock *Pred = *MBB.pred_begin();

  // Scan backwards from the end of the predecessor to find the terminator
  // sequence.  We need at least 2 instructions (flag-setter + branch).
  auto It = Pred->end();
  if (It == Pred->begin())
    return false;
  --It; // Last instruction (should be a branch terminator)

  MachineInstr &Term = *It;
  unsigned TermOpc = Term.getOpcode();

  // --- Pattern D: XRA A; CMP r; branch — A=0 on ALL paths (XRA sets A=0,
  //     CMP doesn't modify A). No need for ZeroProvenPath check. ---
  if (TermOpc == V6CLANG::JZ || TermOpc == V6CLANG::JNZ) {
    // Look at the two instructions before the terminator.
    auto It2 = It;  // points at terminator
    if (It2 != Pred->begin()) {
      --It2; // instruction before terminator (CMP?)
      MachineInstr &PreTerm = *It2;
      if (PreTerm.getOpcode() == V6CLANG::CMPr && It2 != Pred->begin()) {
        --It2; // instruction before CMP (XRA?)
        MachineInstr &PreCmp = *It2;
        if (PreCmp.getOpcode() == V6CLANG::XRAr &&
            PreCmp.getOperand(0).getReg() == V6CLANG::A &&
            PreCmp.getOperand(2).getReg() == V6CLANG::A) {
          int AIdx = regIndex(V6CLANG::A);
          KnownVal[AIdx] = 0;
          return true;
        }
      }
    }
  }

  // Determine if MBB receives the "zero proven" path:
  //   Case 1: NZ-branch (JNZ/RNZ) + MBB is layout fallthrough → Z path
  //   Case 2: Z-branch (JZ) + MBB is the branch target → Z path
  bool ZeroProvenPath = false;
  if (isNZBranchTerminator(TermOpc) && Pred->isLayoutSuccessor(&MBB)) {
    ZeroProvenPath = true;
  } else if (isZBranchTerminator(TermOpc) &&
             Term.getOperand(0).isMBB() &&
             Term.getOperand(0).getMBB() == &MBB) {
    ZeroProvenPath = true;
  }

  if (!ZeroProvenPath)
    return false;

  // Look at the instruction immediately before the terminator.
  if (It == Pred->begin())
    return false;
  --It;
  MachineInstr &FlagSetter = *It;
  unsigned FSOpc = FlagSetter.getOpcode();

  // --- Pattern B: ORA A / ANA A; Z-path proves A=0 ---
  if ((FSOpc == V6CLANG::ORAr || FSOpc == V6CLANG::ANAr) &&
      FlagSetter.getOperand(2).getReg() == V6CLANG::A) {
    // ORA A with $rs == A → testing A itself.
    int AIdx = regIndex(V6CLANG::A);
    KnownVal[AIdx] = 0;
    return true;
  }

  // --- Pattern A: MOV A,rHi; ORA rLo; Z-path proves rHi=0,rLo=0,A=0 ---
  if (FSOpc == V6CLANG::ORAr) {
    MCRegister LoReg = FlagSetter.getOperand(2).getReg();
    // ORA rLo with rLo != A  — check for preceding MOV A, rHi.
    if (It == Pred->begin())
      return false;
    --It;
    MachineInstr &MovInstr = *It;
    if (MovInstr.getOpcode() == V6CLANG::MOVrr &&
        MovInstr.getOperand(0).getReg() == V6CLANG::A) {
      MCRegister HiReg = MovInstr.getOperand(1).getReg();
      // Verify it forms a valid register pair (H/L or D/E).
      if ((HiReg == V6CLANG::H && LoReg == V6CLANG::L) ||
          (HiReg == V6CLANG::D && LoReg == V6CLANG::E) ||
          (HiReg == V6CLANG::B && LoReg == V6CLANG::C)) {
        int HiIdx = regIndex(HiReg);
        int LoIdx = regIndex(LoReg);
        int AIdx = regIndex(V6CLANG::A);
        if (HiIdx >= 0) KnownVal[HiIdx] = 0;
        if (LoIdx >= 0) KnownVal[LoIdx] = 0;
        KnownVal[AIdx] = 0;
        return true;
      }
    }
    return false;
  }

  // --- Pattern C: CPI imm; Z-path proves A=imm ---
  if (FSOpc == V6CLANG::CPI) {
    if (FlagSetter.getOperand(1).isImm()) {
      int64_t Imm = FlagSetter.getOperand(1).getImm() & 0xFF;
      int AIdx = regIndex(V6CLANG::A);
      KnownVal[AIdx] = Imm;
      return true;
    }
  }

  return false;
}

void V6ClangLoadImmCombine::initFromPredecessor(MachineBasicBlock &MBB) {
  invalidateAll();

  if (MBB.pred_size() != 1)
    return;

  MachineBasicBlock *Pred = *MBB.pred_begin();

  // Forward-scan the predecessor to compute register exit state.
  for (const MachineInstr &MI : *Pred) {
    invalidateUndefUses(MI);
    unsigned Opc = MI.getOpcode();

    if (Opc == V6CLANG::MVIr) {
      MCRegister DstReg = MI.getOperand(0).getReg();
      if (isPlainImm(MI.getOperand(1))) {
        int Idx = regIndex(DstReg);
        if (Idx >= 0)
          KnownVal[Idx] = MI.getOperand(1).getImm() & 0xFF;
      } else {
        invalidate(DstReg);
      }
      invalidateKilledUses(MI);
      continue;
    }
    if (Opc == V6CLANG::MOVrr) {
      MCRegister DstReg = MI.getOperand(0).getReg();
      MCRegister SrcReg = MI.getOperand(1).getReg();
      int DstIdx = regIndex(DstReg);
      int SrcIdx = regIndex(SrcReg);
      if (DstIdx >= 0) {
        KnownVal[DstIdx] = (SrcIdx >= 0 && KnownVal[SrcIdx])
                               ? KnownVal[SrcIdx]
                               : std::nullopt;
      }
                        invalidateKilledUses(MI);
      continue;
    }
    if (Opc == V6CLANG::MOVrM) {
      invalidate(MI.getOperand(0).getReg());
                        invalidateKilledUses(MI);
      continue;
    }
    if (Opc == V6CLANG::LXI) {
      MCRegister PairReg = MI.getOperand(0).getReg();
      if (isPlainImm(MI.getOperand(1))) {
        int64_t Imm16 = MI.getOperand(1).getImm() & 0xFFFF;
        int HiIdx = -1, LoIdx = -1;
        if (PairReg == V6CLANG::BC) {
          HiIdx = regIndex(V6CLANG::B); LoIdx = regIndex(V6CLANG::C);
        } else if (PairReg == V6CLANG::DE) {
          HiIdx = regIndex(V6CLANG::D); LoIdx = regIndex(V6CLANG::E);
        } else if (PairReg == V6CLANG::HL) {
          HiIdx = regIndex(V6CLANG::H); LoIdx = regIndex(V6CLANG::L);
        }
        if (HiIdx >= 0) KnownVal[HiIdx] = (Imm16 >> 8) & 0xFF;
        if (LoIdx >= 0) KnownVal[LoIdx] = Imm16 & 0xFF;
      } else {
        invalidateWithSubSuper(PairReg);
      }
      invalidateKilledUses(MI);
      continue;
    }
    if (Opc == V6CLANG::INRr) {
      int Idx = regIndex(MI.getOperand(0).getReg());
      if (Idx >= 0) {
        if (KnownVal[Idx])
          KnownVal[Idx] = (*KnownVal[Idx] + 1) & 0xFF;
        else
          KnownVal[Idx] = std::nullopt;
      }
      invalidateKilledUses(MI);
      continue;
    }
    if (Opc == V6CLANG::DCRr) {
      int Idx = regIndex(MI.getOperand(0).getReg());
      if (Idx >= 0) {
        if (KnownVal[Idx])
          KnownVal[Idx] = (*KnownVal[Idx] - 1) & 0xFF;
        else
          KnownVal[Idx] = std::nullopt;
      }
      invalidateKilledUses(MI);
      continue;
    }
    if (Opc == V6CLANG::XRAr && MI.getOperand(2).getReg() == V6CLANG::A) {
      KnownVal[regIndex(V6CLANG::A)] = 0;
      invalidateKilledUses(MI);
      continue;
    }
    switch (Opc) {
    case V6CLANG::ADDr: case V6CLANG::ADCr: case V6CLANG::SUBr: case V6CLANG::SBBr:
    case V6CLANG::ANAr: case V6CLANG::XRAr: case V6CLANG::ORAr:
    case V6CLANG::ADDM: case V6CLANG::ADCM: case V6CLANG::SUBM: case V6CLANG::SBBM:
    case V6CLANG::ANAM: case V6CLANG::XRAM: case V6CLANG::ORAM:
    case V6CLANG::ADI: case V6CLANG::ACI: case V6CLANG::SUI: case V6CLANG::SBI:
    case V6CLANG::ANI: case V6CLANG::XRI: case V6CLANG::ORI:
    case V6CLANG::RLC: case V6CLANG::RRC: case V6CLANG::RAL: case V6CLANG::RAR:
    case V6CLANG::CMA: case V6CLANG::DAA:
      invalidate(V6CLANG::A);
      invalidateKilledUses(MI);
      continue;
    default:
      break;
    }
    if (Opc == V6CLANG::LDA || Opc == V6CLANG::LDAX) {
      invalidate(V6CLANG::A);
      invalidateKilledUses(MI);
      continue;
    }
    if (Opc == V6CLANG::POP) {
      MCRegister Reg = MI.getOperand(0).getReg();
      invalidateWithSubSuper(Reg);
      if (Reg == V6CLANG::PSW) invalidate(V6CLANG::A);
      invalidateKilledUses(MI);
      continue;
    }
    if (Opc == V6CLANG::INX || Opc == V6CLANG::DCX) {
      invalidateWithSubSuper(MI.getOperand(0).getReg());
      invalidateKilledUses(MI);
      continue;
    }
    if (Opc == V6CLANG::XCHG) {
      int DIdx = regIndex(V6CLANG::D), EIdx = regIndex(V6CLANG::E);
      int HIdx = regIndex(V6CLANG::H), LIdx = regIndex(V6CLANG::L);
      std::swap(KnownVal[DIdx], KnownVal[HIdx]);
      std::swap(KnownVal[EIdx], KnownVal[LIdx]);
      invalidateKilledUses(MI);
      continue;
    }
    if (MI.isCall()) {
      invalidateAll();
      invalidateKilledUses(MI);
      continue;
    }
    for (const MachineOperand &MO : MI.operands()) {
      if (MO.isReg() && MO.isDef() && MO.getReg().isPhysical())
        invalidateWithSubSuper(MO.getReg());
    }
    if (const MCInstrDesc &Desc = MI.getDesc();
        Desc.hasImplicitDefOfPhysReg(V6CLANG::A))
      invalidate(V6CLANG::A);
    invalidateKilledUses(MI);
  }
}

bool V6ClangLoadImmCombine::processBlock(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetInstrInfo &TII = *MBB.getParent()->getSubtarget().getInstrInfo();
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();

  initFromPredecessor(MBB);
  dropEntryValuesNotLiveIn(MBB, TRI);
  seedPredecessorValues(MBB);

  for (MachineInstr &MI : llvm::make_early_inc_range(MBB)) {
    invalidateUndefUses(MI);
    unsigned Opc = MI.getOpcode();

    // --- MVI r, imm: main optimization target ---
    if (Opc == V6CLANG::MVIr) {
      MCRegister DstReg = MI.getOperand(0).getReg();
      // MVI can have non-immediate operands (e.g., global lo8/hi8 exprs)
      // or carry MO_PATCH_IMM (O61: runtime-patched imm byte). Both
      // must be treated as opaque constant definers.
      if (!isPlainImm(MI.getOperand(1))) {
        invalidate(DstReg);
        continue;
      }
      int64_t Imm = MI.getOperand(1).getImm() & 0xFF;
      int DstIdx = regIndex(DstReg);

      // Try 0: Same register already holds the value → remove MVI entirely.
      if (DstIdx >= 0 && KnownVal[DstIdx] &&
          ((*KnownVal[DstIdx]) & 0xFF) == (Imm & 0xFF)) {
        MI.eraseFromParent();
        Changed = true;
        continue;
      }

      // Try 1: Another register holds the same value → MOV r, r'
      MCRegister SrcReg = findRegWithValue(Imm, DstReg);
      if (SrcReg.isValid()) {
        BuildMI(MBB, MI, MI.getDebugLoc(), TII.get(V6CLANG::MOVrr), DstReg)
            .addReg(SrcReg);
        MI.eraseFromParent();
        if (DstIdx >= 0)
          KnownVal[DstIdx] = Imm;
        Changed = true;
        continue;
      }

      // Try 2: Same register holds imm-1 → INR r
      if (DstIdx >= 0 && KnownVal[DstIdx] &&
          ((*KnownVal[DstIdx]) & 0xFF) == ((Imm - 1) & 0xFF)) {
        BuildMI(MBB, MI, MI.getDebugLoc(), TII.get(V6CLANG::INRr), DstReg)
            .addReg(DstReg);
        MI.eraseFromParent();
        KnownVal[DstIdx] = Imm;
        Changed = true;
        continue;
      }

      // Try 3: Same register holds imm+1 → DCR r
      if (DstIdx >= 0 && KnownVal[DstIdx] &&
          ((*KnownVal[DstIdx]) & 0xFF) == ((Imm + 1) & 0xFF)) {
        BuildMI(MBB, MI, MI.getDebugLoc(), TII.get(V6CLANG::DCRr), DstReg)
            .addReg(DstReg);
        MI.eraseFromParent();
        KnownVal[DstIdx] = Imm;
        Changed = true;
        continue;
      }

      // No optimization — keep MVI and record value.
      if (DstIdx >= 0)
        KnownVal[DstIdx] = Imm;
      continue;
    }

    // --- MOV r, r': propagate known value ---
    if (Opc == V6CLANG::MOVrr) {
      MCRegister DstReg = MI.getOperand(0).getReg();
      MCRegister SrcReg = MI.getOperand(1).getReg();
      int DstIdx = regIndex(DstReg);
      int SrcIdx = regIndex(SrcReg);
      if (DstIdx >= 0) {
        if (SrcIdx >= 0 && KnownVal[SrcIdx])
          KnownVal[DstIdx] = *KnownVal[SrcIdx];
        else
          KnownVal[DstIdx] = std::nullopt;
      }
      continue;
    }

    // --- MOV r, M: load from memory invalidates dst ---
    if (Opc == V6CLANG::MOVrM) {
      MCRegister DstReg = MI.getOperand(0).getReg();
      invalidate(DstReg);
      continue;
    }

    // --- LXI rp, imm16: eliminate if both halves already hold the value ---
    if (Opc == V6CLANG::LXI) {
      MCRegister PairReg = MI.getOperand(0).getReg();
      if (isPlainImm(MI.getOperand(1))) {
        int64_t Imm16 = MI.getOperand(1).getImm() & 0xFFFF;
        int64_t Lo = Imm16 & 0xFF;
        int64_t Hi = (Imm16 >> 8) & 0xFF;
        int HiIdx = -1, LoIdx = -1;
        if (PairReg == V6CLANG::BC) {
          HiIdx = regIndex(V6CLANG::B); LoIdx = regIndex(V6CLANG::C);
        } else if (PairReg == V6CLANG::DE) {
          HiIdx = regIndex(V6CLANG::D); LoIdx = regIndex(V6CLANG::E);
        } else if (PairReg == V6CLANG::HL) {
          HiIdx = regIndex(V6CLANG::H); LoIdx = regIndex(V6CLANG::L);
        }
        // If both halves already hold the correct values, eliminate LXI.
        if (HiIdx >= 0 && LoIdx >= 0 &&
            KnownVal[HiIdx] && *KnownVal[HiIdx] == Hi &&
            KnownVal[LoIdx] && *KnownVal[LoIdx] == Lo) {
          MI.eraseFromParent();
          Changed = true;
          continue;
        }
        // Otherwise, record the new values.
        if (HiIdx >= 0) KnownVal[HiIdx] = Hi;
        if (LoIdx >= 0) KnownVal[LoIdx] = Lo;
        // SP: not tracked.
      } else {
        // Non-immediate LXI (global address) — invalidate pair.
        invalidateWithSubSuper(PairReg);
      }
      continue;
    }

    // --- INR/DCR r: update tracked value if known ---
    if (Opc == V6CLANG::INRr) {
      MCRegister Reg = MI.getOperand(0).getReg();
      int Idx = regIndex(Reg);
      if (Idx >= 0 && KnownVal[Idx])
        KnownVal[Idx] = ((*KnownVal[Idx]) + 1) & 0xFF;
      else if (Idx >= 0)
        KnownVal[Idx] = std::nullopt;
      continue;
    }
    if (Opc == V6CLANG::DCRr) {
      MCRegister Reg = MI.getOperand(0).getReg();
      int Idx = regIndex(Reg);
      if (Idx >= 0 && KnownVal[Idx])
        KnownVal[Idx] = ((*KnownVal[Idx]) - 1) & 0xFF;
      else if (Idx >= 0)
        KnownVal[Idx] = std::nullopt;
      continue;
    }

    // --- XRA A: A = A ^ A = 0 → track A as holding 0 ---
    if (Opc == V6CLANG::XRAr && MI.getOperand(2).getReg() == V6CLANG::A) {
      int AIdx = regIndex(V6CLANG::A);
      KnownVal[AIdx] = 0;
      continue;
    }

    // --- ALU ops that write A: invalidate A ---
    switch (Opc) {
    case V6CLANG::ADDr: case V6CLANG::ADCr: case V6CLANG::SUBr: case V6CLANG::SBBr:
    case V6CLANG::ANAr: case V6CLANG::XRAr: case V6CLANG::ORAr:
    case V6CLANG::ADDM: case V6CLANG::ADCM: case V6CLANG::SUBM: case V6CLANG::SBBM:
    case V6CLANG::ANAM: case V6CLANG::XRAM: case V6CLANG::ORAM:
    case V6CLANG::ADI: case V6CLANG::ACI: case V6CLANG::SUI: case V6CLANG::SBI:
    case V6CLANG::ANI: case V6CLANG::XRI: case V6CLANG::ORI:
    case V6CLANG::RLC: case V6CLANG::RRC: case V6CLANG::RAL: case V6CLANG::RAR:
    case V6CLANG::CMA: case V6CLANG::DAA:
      invalidate(V6CLANG::A);
      continue;
    default:
      break;
    }

    // --- LDA / LDAX: write A ---
    if (Opc == V6CLANG::LDA || Opc == V6CLANG::LDAX) {
      invalidate(V6CLANG::A);
      continue;
    }

    // --- POP: invalidate the pair's sub-registers ---
    if (Opc == V6CLANG::POP) {
      MCRegister Reg = MI.getOperand(0).getReg();
      invalidateWithSubSuper(Reg);
      // PSW writes A too.
      if (Reg == V6CLANG::PSW)
        invalidate(V6CLANG::A);
      continue;
    }

    // --- INX/DCX: invalidate pair sub-registers (no simple ±1 on halves) ---
    if (Opc == V6CLANG::INX || Opc == V6CLANG::DCX) {
      MCRegister Reg = MI.getOperand(0).getReg();
      invalidateWithSubSuper(Reg);
      continue;
    }

    // --- XCHG: swap DE and HL known values ---
    if (Opc == V6CLANG::XCHG) {
      int DIdx = regIndex(V6CLANG::D), EIdx = regIndex(V6CLANG::E);
      int HIdx = regIndex(V6CLANG::H), LIdx = regIndex(V6CLANG::L);
      std::swap(KnownVal[DIdx], KnownVal[HIdx]);
      std::swap(KnownVal[EIdx], KnownVal[LIdx]);
      continue;
    }

    // --- CALL: invalidate all (callee may clobber everything) ---
    if (MI.isCall()) {
      invalidateAll();
      continue;
    }

    // --- Any other instruction that defines a tracked register ---
    for (const MachineOperand &MO : MI.operands()) {
      if (MO.isReg() && MO.isDef() && MO.getReg().isPhysical())
        invalidateWithSubSuper(MO.getReg());
    }
    // Implicit defs.
    if (const MCInstrDesc &Desc = MI.getDesc();
        Desc.hasImplicitDefOfPhysReg(V6CLANG::A))
      invalidate(V6CLANG::A);
  }

  return Changed;
}

bool V6ClangLoadImmCombine::runOnMachineFunction(MachineFunction &MF) {
  if (DisableLoadImmCombine)
    return false;

  bool Changed = false;
  for (MachineBasicBlock &MBB : MF)
    Changed |= processBlock(MBB);
  return Changed;
}

FunctionPass *llvm::createV6ClangLoadImmCombinePass() {
  return new V6ClangLoadImmCombine();
}
