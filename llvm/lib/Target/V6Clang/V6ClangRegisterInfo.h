//===-- V6ClangRegisterInfo.h - V6CLANG Register Information -----------*- C++ -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_V6CLANG_V6ClangREGISTERINFO_H
#define LLVM_LIB_TARGET_V6CLANG_V6ClangREGISTERINFO_H

#include "llvm/CodeGen/TargetRegisterInfo.h"

#define GET_REGINFO_HEADER
#include "V6ClangGenRegisterInfo.inc"

namespace llvm {

class V6ClangRegisterInfo : public V6ClangGenRegisterInfo {
public:
  V6ClangRegisterInfo();

  const MCPhysReg *getCalleeSavedRegs(const MachineFunction *MF) const override;
  const uint32_t *getCallPreservedMask(const MachineFunction &MF,
                                       CallingConv::ID CC) const override;
  BitVector getReservedRegs(const MachineFunction &MF) const override;
  bool eliminateFrameIndex(MachineBasicBlock::iterator MI, int SPAdj,
                           unsigned FIOperandNum,
                           RegScavenger *RS = nullptr) const override;
  Register getFrameRegister(const MachineFunction &MF) const override;
  const TargetRegisterClass *
  getLargestLegalSuperClass(const TargetRegisterClass *RC,
                            const MachineFunction &MF) const override;
};

} // namespace llvm

#endif // LLVM_LIB_TARGET_V6CLANG_V6ClangREGISTERINFO_H
