//===-- V6ClangLoadStoreOpt.cpp - V6CLANG Load/Store Optimizations ----------------===//
//
// Part of the V6CLANG backend for LLVM.
//
// Post-RA pass for load/store optimizations:
//
// 1. Sequential HL Address Reuse (LXI -> INX/DCX folding):
//    Track the abstract value held by HL across each MBB. When a new
//    LXI H, X is seen and HL already holds X +/- Delta, replace the LXI
//    with |Delta| copies of INX H / DCX H (or drop entirely on Delta=0).
//    The tracker recognizes plain immediates, GlobalAddress + offset,
//    ExternalSymbol + offset, and BlockAddress + offset.
//    Permitted "gap" instructions (LDA, STA, MVI A, immediate ALU, IN,
//    OUT, MOV between non-H/L registers, etc.) leave HL untouched, so
//    they do not reset the tracker; any def of H/L/HL or call clobber
//    resets it. Delta threshold is gated by the dual cost model:
//      Speed (-O2/-O3): Delta=1 only      (8cc < 12cc, strict win)
//      Balanced (-O1):  Delta<=2          (16cc/2B vs 12cc/3B, neutral)
//      Size (-Os/-Oz):  Delta<=3          (24cc/3B vs 12cc/3B, size tie)
//
// 2. Dead LXI elimination: if HL is loaded (LXI HL, X) and then
//    immediately overwritten without use, remove the first LXI.
//    Kept as a belt-and-braces pass for cross-pattern leftovers.
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "V6ClangInstrCost.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/MathExtras.h"

#include <cstdlib>

using namespace llvm;

#define DEBUG_TYPE "v6clang-loadstore-opt"

static cl::opt<bool> DisableLoadStoreOpt(
    "v6clang-disable-loadstore-opt",
    cl::desc("Disable V6CLANG load/store merge optimizations"),
    cl::init(false), cl::Hidden);

namespace {

/// Abstract value of HL within a single basic block.
struct HLAddr {
  enum class Kind : uint8_t { Unknown, Imm, GA, ES, BA };
  Kind K = Kind::Unknown;
  int64_t Offset = 0;
  const GlobalValue *GV = nullptr;
  const char *Sym = nullptr;          // for ES (interned)
  const BlockAddress *BAv = nullptr;  // for BA
  unsigned char TF = 0;               // target flags

  bool isKnown() const { return K != Kind::Unknown; }
  void reset() { *this = HLAddr(); }

  /// Build from an LXI HL, X instruction (returns Unknown if it cannot
  /// be tracked, e.g. unsupported operand kind or non-HL destination).
  static HLAddr fromLXI(const MachineInstr &MI);

  /// Two HLAddrs share the same symbolic base (kind + symbol identity +
  /// target-flags). Both must be known.
  bool sameBase(const HLAddr &O) const {
    if (K != O.K || TF != O.TF) return false;
    switch (K) {
    case Kind::Imm: return true;
    case Kind::GA:  return GV == O.GV;
    case Kind::ES:  return Sym == O.Sym;
    case Kind::BA:  return BAv == O.BAv;
    case Kind::Unknown: return false;
    }
    return false;
  }

  /// If known and same base as O (also known), set Delta = O.Offset - this.Offset.
  bool tryDelta(const HLAddr &O, int64_t &Delta) const {
    if (!isKnown() || !O.isKnown() || !sameBase(O)) return false;
    Delta = O.Offset - Offset;
    return true;
  }

  /// Saturating bump (clears to Unknown on extreme magnitudes).
  void bump(int64_t D) {
    if (!isKnown()) return;
    // Conservative guard — INX/DCX delta is always +/-1, so overflow
    // is not a real concern; this just avoids wraparound surprises if
    // a caller passes something larger.
    if (Offset > (INT64_MAX >> 1) || Offset < (INT64_MIN >> 1)) {
      reset();
      return;
    }
    Offset += D;
  }
};

class V6ClangLoadStoreOpt : public MachineFunctionPass {
public:
  static char ID;
  V6ClangLoadStoreOpt() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Load/Store Optimization";
  }

  bool runOnMachineFunction(MachineFunction &MF) override;

private:
  bool foldHLChain(MachineBasicBlock &MBB, unsigned MaxDelta);
  bool eliminateDeadLXI(MachineBasicBlock &MBB);

  /// Compute the maximum |Delta| for which an LXI replacement is
  /// considered profitable, based on optimization mode.
  static unsigned getMaxDelta(const MachineFunction &MF) {
    switch (getV6ClangOptMode(MF)) {
    case V6ClangOptMode::Speed:    return 1;
    case V6ClangOptMode::Balanced: return 2;
    case V6ClangOptMode::Size:     return 3;
    }
    return 1;
  }

  /// True if MI defines or clobbers any part of HL — explicit defs,
  /// implicit defs, sub-register defs (H/L), or a RegMask covering HL.
  static bool clobbersHL(const MachineInstr &MI);

  /// True if MI is INX HL.
  static bool isINX_HL(const MachineInstr &MI) {
    return MI.getOpcode() == V6CLANG::INX && MI.getNumOperands() >= 1 &&
           MI.getOperand(0).isReg() && MI.getOperand(0).getReg() == V6CLANG::HL;
  }

  /// True if MI is DCX HL.
  static bool isDCX_HL(const MachineInstr &MI) {
    return MI.getOpcode() == V6CLANG::DCX && MI.getNumOperands() >= 1 &&
           MI.getOperand(0).isReg() && MI.getOperand(0).getReg() == V6CLANG::HL;
  }

  /// True if MI uses any part of HL.
  static bool usesHL(const MachineInstr &MI) {
    for (const MachineOperand &MO : MI.operands()) {
      if (!MO.isReg() || !MO.isUse()) continue;
      Register R = MO.getReg();
      if (R == V6CLANG::HL || R == V6CLANG::H || R == V6CLANG::L) return true;
    }
    return false;
  }
};

} // end anonymous namespace

char V6ClangLoadStoreOpt::ID = 0;

HLAddr HLAddr::fromLXI(const MachineInstr &MI) {
  HLAddr A;
  if (MI.getOpcode() != V6CLANG::LXI) return A;
  if (MI.getNumOperands() < 2) return A;
  if (!MI.getOperand(0).isReg() || MI.getOperand(0).getReg() != V6CLANG::HL)
    return A;
  const MachineOperand &Op = MI.getOperand(1);
  A.TF = Op.getTargetFlags();
  if (Op.isImm()) {
    A.K = Kind::Imm;
    A.Offset = Op.getImm();
    return A;
  }
  if (Op.isGlobal()) {
    A.K = Kind::GA;
    A.GV = Op.getGlobal();
    A.Offset = Op.getOffset();
    return A;
  }
  if (Op.isSymbol()) {
    A.K = Kind::ES;
    A.Sym = Op.getSymbolName();
    A.Offset = Op.getOffset();
    return A;
  }
  if (Op.isBlockAddress()) {
    A.K = Kind::BA;
    A.BAv = Op.getBlockAddress();
    A.Offset = Op.getOffset();
    return A;
  }
  return A; // Unknown for MCSymbol, JumpTableIndex, etc.
}

bool V6ClangLoadStoreOpt::clobbersHL(const MachineInstr &MI) {
  for (const MachineOperand &MO : MI.operands()) {
    if (MO.isRegMask()) {
      if (MO.clobbersPhysReg(V6CLANG::HL) ||
          MO.clobbersPhysReg(V6CLANG::H)  ||
          MO.clobbersPhysReg(V6CLANG::L))
        return true;
      continue;
    }
    if (!MO.isReg() || !MO.isDef()) continue;
    Register R = MO.getReg();
    if (R == V6CLANG::HL || R == V6CLANG::H || R == V6CLANG::L) return true;
  }
  return false;
}

bool V6ClangLoadStoreOpt::foldHLChain(MachineBasicBlock &MBB, unsigned MaxDelta) {
  bool Changed = false;
  const TargetInstrInfo &TII = *MBB.getParent()->getSubtarget().getInstrInfo();

  HLAddr State;

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ) {
    MachineInstr &MI = *I;

    // INX HL / DCX HL — bump tracker, leave instruction.
    if (isINX_HL(MI)) {
      if (State.isKnown()) State.bump(+1);
      ++I;
      continue;
    }
    if (isDCX_HL(MI)) {
      if (State.isKnown()) State.bump(-1);
      ++I;
      continue;
    }

    // LXI HL, X — try to fold against the running State.
    if (MI.getOpcode() == V6CLANG::LXI && MI.getOperand(0).isReg() &&
        MI.getOperand(0).getReg() == V6CLANG::HL && !MI.isBundled()) {
      HLAddr New = HLAddr::fromLXI(MI);
      int64_t Delta = 0;
      if (State.isKnown() && New.isKnown() && State.tryDelta(New, Delta)) {
        if (Delta == 0) {
          // HL already holds the desired value — drop the LXI entirely.
          auto ToErase = I++;
          ToErase->eraseFromParent();
          Changed = true;
          continue;
        }
        uint64_t Abs = (uint64_t)std::abs(Delta);
        if (Abs <= (uint64_t)MaxDelta) {
          unsigned Opc = Delta > 0 ? V6CLANG::INX : V6CLANG::DCX;
          DebugLoc DL = MI.getDebugLoc();
          for (uint64_t k = 0; k < Abs; ++k) {
            BuildMI(MBB, MI, DL, TII.get(Opc), V6CLANG::HL).addReg(V6CLANG::HL);
          }
          auto ToErase = I++;
          ToErase->eraseFromParent();
          State = New;
          Changed = true;
          continue;
        }
      }
      State = New;
      ++I;
      continue;
    }

    if (clobbersHL(MI))
      State.reset();

    ++I;
  }

  return Changed;
}

/// Remove LXI HL, X when HL is immediately overwritten without being used.
bool V6ClangLoadStoreOpt::eliminateDeadLXI(MachineBasicBlock &MBB) {
  bool Changed = false;

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ) {
    if (!(I->getOpcode() == V6CLANG::LXI && I->getNumOperands() >= 1 &&
          I->getOperand(0).isReg() && I->getOperand(0).getReg() == V6CLANG::HL)) {
      ++I;
      continue;
    }

    auto Next = std::next(I);
    bool Dead = false;
    while (Next != MBB.end()) {
      if (usesHL(*Next))
        break;
      if (clobbersHL(*Next)) {
        Dead = true;
        break;
      }
      ++Next;
    }

    if (Dead) {
      auto ToErase = I++;
      ToErase->eraseFromParent();
      Changed = true;
    } else {
      ++I;
    }
  }

  return Changed;
}

bool V6ClangLoadStoreOpt::runOnMachineFunction(MachineFunction &MF) {
  if (DisableLoadStoreOpt)
    return false;

  unsigned MaxDelta = getMaxDelta(MF);
  bool Changed = false;
  for (MachineBasicBlock &MBB : MF) {
    Changed |= foldHLChain(MBB, MaxDelta);
    Changed |= eliminateDeadLXI(MBB);
  }
  return Changed;
}

FunctionPass *llvm::createV6ClangLoadStoreOptPass() {
  return new V6ClangLoadStoreOpt();
}
