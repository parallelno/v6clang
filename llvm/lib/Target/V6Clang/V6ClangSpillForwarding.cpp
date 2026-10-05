//===-- V6ClangSpillForwarding.cpp - Post-RA spill/reload forwarding ----------===//
//
// Part of the V6CLANG backend for LLVM.
//
// Post-RA pass (runs in addPostRegAlloc, before PEI):
// Tracks which physical register holds each stack-slot value via
// DenseMap<int, MCPhysReg> keyed by frame index.  When a RELOAD pseudo
// references a slot whose value is still in a register, the RELOAD is
// replaced with a MOV (or erased if dest == source).
//
// Special case: when a SPILL has isKill=true and the very next instruction
// is a RELOAD of the same slot, clear isKill so PEI emits an in-place
// restore instead of the full reload sequence.
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetRegisterInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/Support/CommandLine.h"

#define DEBUG_TYPE "v6clang-spill-forwarding"

using namespace llvm;

static cl::opt<bool> DisableSpillForwarding(
    "v6clang-disable-spill-forwarding",
    cl::desc("Disable V6CLANG post-RA spill/reload forwarding"),
    cl::init(false), cl::Hidden);

namespace {

class V6ClangSpillForwarding : public MachineFunctionPass {
public:
  static char ID;
  V6ClangSpillForwarding() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Spill/Reload Forwarding";
  }

  bool runOnMachineFunction(MachineFunction &MF) override;

private:
  const TargetInstrInfo *TII = nullptr;
  const TargetRegisterInfo *TRI = nullptr;

  /// Map frame-index → physical register that currently holds the slot value.
  DenseMap<int, MCPhysReg> Avail;

  /// Remove all Avail entries where the tracked register overlaps Reg.
  void invalidateReg(MCPhysReg Reg) {
    SmallVector<int, 4> ToErase;
    for (auto &KV : Avail) {
      MCPhysReg Tracked = KV.second;
      if (Tracked == Reg || TRI->regsOverlap(Tracked, Reg))
        ToErase.push_back(KV.first);
    }
    for (int FI : ToErase)
      Avail.erase(FI);
  }

  /// Check if Opc is a SPILL pseudo.
  static bool isSpill(unsigned Opc) {
    return Opc == V6CLANG::V6CLANG_SPILL8 || Opc == V6CLANG::V6CLANG_SPILL16;
  }

  /// Check if Opc is a RELOAD pseudo.
  static bool isReload(unsigned Opc) {
    return Opc == V6CLANG::V6CLANG_RELOAD8 || Opc == V6CLANG::V6CLANG_RELOAD16;
  }

  /// Check if Opc is 16-bit (SPILL16 or RELOAD16).
  static bool is16Bit(unsigned Opc) {
    return Opc == V6CLANG::V6CLANG_SPILL16 || Opc == V6CLANG::V6CLANG_RELOAD16;
  }

  bool processBlock(MachineBasicBlock &MBB);
};

} // end anonymous namespace

char V6ClangSpillForwarding::ID = 0;

bool V6ClangSpillForwarding::processBlock(MachineBasicBlock &MBB) {
  bool Changed = false;
  Avail.clear();

  for (MachineBasicBlock::iterator MII = MBB.begin(), MIE = MBB.end();
       MII != MIE; /* advanced below */) {
    MachineInstr &MI = *MII;
    unsigned Opc = MI.getOpcode();

    // --- SPILL ---
    if (isSpill(Opc)) {
      Register SrcReg = MI.getOperand(0).getReg();
      int FI = MI.getOperand(1).getIndex();
      bool IsKill = MI.getOperand(0).isKill();

      // Redundant store: slot already holds this register's value.
      if (!IsKill) {
        auto It = Avail.find(FI);
        if (It != Avail.end() && It->second == SrcReg) {
          // Slot already contains this value — erase the SPILL.
          MII = MBB.erase(&MI);
          Changed = true;
          continue;
        }
      }

      if (IsKill) {
        // Peek ahead: if next MI is a RELOAD of the same frame index,
        // clear isKill and forward.
        auto NextIt = std::next(MII);
        if (NextIt != MIE && isReload(NextIt->getOpcode())) {
          int ReloadFI = NextIt->getOperand(1).getIndex();
          if (ReloadFI == FI) {
            Register DstReg = NextIt->getOperand(0).getReg();
            // Clear isKill so PEI emits in-place restore for SPILL.
            MI.getOperand(0).setIsKill(false);

            if (DstReg == SrcReg) {
              // Same register — just erase the RELOAD.
              MBB.erase(&*NextIt);
            } else if (is16Bit(Opc)) {
              // 16-bit cross-register: replace RELOAD with 2 MOVs.
              MCPhysReg SrcLo = TRI->getSubReg(SrcReg, V6CLANG::sub_lo);
              MCPhysReg SrcHi = TRI->getSubReg(SrcReg, V6CLANG::sub_hi);
              MCPhysReg DstLo = TRI->getSubReg(DstReg, V6CLANG::sub_lo);
              MCPhysReg DstHi = TRI->getSubReg(DstReg, V6CLANG::sub_hi);
              DebugLoc DL = NextIt->getDebugLoc();
              BuildMI(MBB, NextIt, DL, TII->get(V6CLANG::MOVrr))
                  .addReg(DstLo, RegState::Define)
                  .addReg(SrcLo);
              BuildMI(MBB, NextIt, DL, TII->get(V6CLANG::MOVrr))
                  .addReg(DstHi, RegState::Define)
                  .addReg(SrcHi);
              MBB.erase(&*NextIt);
              // MOVs clobber DstReg's prior contents — drop stale entries.
              invalidateReg(DstReg);
            } else {
              // 8-bit cross-register: replace RELOAD with 1 MOV.
              DebugLoc DL = NextIt->getDebugLoc();
              BuildMI(MBB, NextIt, DL, TII->get(V6CLANG::MOVrr))
                  .addReg(DstReg, RegState::Define)
                  .addReg(SrcReg);
              MBB.erase(&*NextIt);
              invalidateReg(DstReg);
            }

            Avail[FI] = SrcReg;
            Changed = true;
            ++MII; // advance past the SPILL (RELOAD already erased)
            continue;
          }
        }

        // Kill with no adjacent reload — register dead, slot orphaned.
        Avail.erase(FI);
        ++MII;
        continue;
      }

      // Normal spill (not kill): record mapping.
      Avail[FI] = SrcReg;
      ++MII;
      continue;
    }

    // --- RELOAD ---
    if (isReload(Opc)) {
      Register DstReg = MI.getOperand(0).getReg();
      int FI = MI.getOperand(1).getIndex();

      // Dead reload elimination: if the destination operand is marked dead,
      // the reloaded value is unused.  The pseudo's only other effect is an
      // implicit-def of FLAGS (from the DAD SP used to address the slot),
      // but that effect is purely an artifact of how stack access is
      // implemented on V6CLANG — semantically a reload is flag-preserving.
      // Erasing dead reloads is critical for correctness: if a dead reload
      // is left between a flag-setting compare and a conditional branch,
      // the DAD SP in its post-PEI expansion clobbers CY and the branch
      // reads the wrong flag.
      if (MI.getOperand(0).isDead()) {
        MII = MBB.erase(&MI);
        Changed = true;
        continue;
      }

      auto It = Avail.find(FI);
      if (It != Avail.end()) {
        MCPhysReg SrcReg = It->second;

        if (SrcReg == DstReg) {
          // Same register — erase the RELOAD entirely.
          MII = MBB.erase(&MI);
          Changed = true;
          continue;
        }

        if (is16Bit(Opc)) {
          // 16-bit forwarding: replace with 2 MOVs.
          MCPhysReg SrcLo = TRI->getSubReg(SrcReg, V6CLANG::sub_lo);
          MCPhysReg SrcHi = TRI->getSubReg(SrcReg, V6CLANG::sub_hi);
          MCPhysReg DstLo = TRI->getSubReg(DstReg, V6CLANG::sub_lo);
          MCPhysReg DstHi = TRI->getSubReg(DstReg, V6CLANG::sub_hi);
          DebugLoc DL = MI.getDebugLoc();
          BuildMI(MBB, MII, DL, TII->get(V6CLANG::MOVrr))
              .addReg(DstLo, RegState::Define)
              .addReg(SrcLo);
          BuildMI(MBB, MII, DL, TII->get(V6CLANG::MOVrr))
              .addReg(DstHi, RegState::Define)
              .addReg(SrcHi);
          MII = MBB.erase(&MI);
          Changed = true;

          // Writing to DstReg invalidates any stale Avail entry that
          // mapped some other slot to DstReg (or an overlapping reg).
          invalidateReg(DstReg);
          // Now DstReg also holds the slot value.
          Avail[FI] = SrcReg; // keep original source as canonical
          continue;
        }

        // 8-bit forwarding: replace with 1 MOV.
        DebugLoc DL = MI.getDebugLoc();
        BuildMI(MBB, MII, DL, TII->get(V6CLANG::MOVrr))
            .addReg(DstReg, RegState::Define)
            .addReg(SrcReg);
        MII = MBB.erase(&MI);
        Changed = true;
        invalidateReg(DstReg);
        continue;
      }

      // No forwarding possible — the RELOAD stays, but now DstReg
      // holds the slot value. The original RELOAD writes DstReg, so
      // any stale Avail entry tracking DstReg must be cleared first.
      invalidateReg(DstReg);
      Avail[FI] = DstReg;
      ++MII;
      continue;
    }

    // --- CALL ---
    if (MI.isCall()) {
      Avail.clear();
      ++MII;
      continue;
    }

    // --- Other instructions: invalidate on register defs ---
    for (const MachineOperand &MO : MI.operands()) {
      if (MO.isReg() && MO.isDef() && MO.getReg().isPhysical())
        invalidateReg(MO.getReg());
    }

    ++MII;
  }

  return Changed;
}

bool V6ClangSpillForwarding::runOnMachineFunction(MachineFunction &MF) {
  if (DisableSpillForwarding)
    return false;

  TII = MF.getSubtarget().getInstrInfo();
  TRI = MF.getSubtarget().getRegisterInfo();

  bool Changed = false;
  for (MachineBasicBlock &MBB : MF)
    Changed |= processBlock(MBB);

  return Changed;
}

FunctionPass *llvm::createV6ClangSpillForwardingPass() {
  return new V6ClangSpillForwarding();
}
