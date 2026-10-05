//===-- V6ClangFrameLowering.h - V6CLANG Frame Lowering ----------------*- C++ -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
// M5: Frame Lowering & Calling Convention.
//
// The 8080 has no frame pointer register and no base+offset addressing.
// SP is adjusted via LXI+DAD+SPHL. When a frame pointer is needed
// (alloca, -fno-omit-frame-pointer), BC is reserved as the FP.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_V6CLANG_V6ClangFRAMELOWERING_H
#define LLVM_LIB_TARGET_V6CLANG_V6ClangFRAMELOWERING_H

#include "llvm/CodeGen/TargetFrameLowering.h"

namespace llvm {

enum class V6ClangOptMode;

class V6ClangFrameLowering : public TargetFrameLowering {
public:
  V6ClangFrameLowering()
      : TargetFrameLowering(StackGrowsDown, /*StackAlign=*/Align(1),
                            /*LocalAreaOffset=*/0) {}

  void emitPrologue(MachineFunction &MF,
                    MachineBasicBlock &MBB) const override;
  void emitEpilogue(MachineFunction &MF,
                    MachineBasicBlock &MBB) const override;
  bool hasFP(const MachineFunction &MF) const override;
  DwarfFrameBase getDwarfFrameBase(const MachineFunction &MF) const override;

  MachineBasicBlock::iterator
  eliminateCallFramePseudoInstr(MachineFunction &MF, MachineBasicBlock &MBB,
                                MachineBasicBlock::iterator I) const override;

private:
  /// Pick a GR16All pair whose halves are dead at MBBI for use as
  /// PUSH/POP filler when adjusting SP. Returns V6CLANG::PSW when A+FLAGS
  /// are dead, otherwise BC/DE/HL in that fallback order, or
  /// V6CLANG::NoRegister when none qualifies.
  Register chooseDeadPair(const MachineBasicBlock &MBB,
                          MachineBasicBlock::iterator MBBI,
                          bool IsPrologue) const;

  /// Emit an SP adjustment of |Amount| bytes at MBBI. Negative Amount
  /// allocates (prologue), positive deallocates (epilogue). Chooses
  /// between PUSH/POP x n/2, DCX/INX SP x n, or LXI+DAD+SPHL based
  /// on the dual cost model (O11) and register liveness.
  void emitSPAdjustment(MachineBasicBlock &MBB,
                        MachineBasicBlock::iterator MBBI,
                        int64_t Amount, const DebugLoc &DL,
                        bool IsPrologue, V6ClangOptMode Mode) const;

  /// Predict whether emitSPAdjustment(|Amount|, MBBI, IsPrologue, Mode) will
  /// pick the LXI+DAD+SPHL tier (which clobbers HL). PUSH/POP and DCX/INX SP
  /// tiers leave HL untouched.
  bool spAdjustClobbersHL(const MachineBasicBlock &MBB,
                          MachineBasicBlock::iterator MBBI,
                          int64_t Amount, bool IsPrologue,
                          V6ClangOptMode Mode) const;
};

} // namespace llvm

#endif // LLVM_LIB_TARGET_V6CLANG_V6ClangFRAMELOWERING_H
