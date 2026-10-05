//===-- V6ClangSubtarget.h - Define Subtarget for V6CLANG ---------------*- C++ -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_V6CLANG_V6ClangSUBTARGET_H
#define LLVM_LIB_TARGET_V6CLANG_V6ClangSUBTARGET_H

#include "V6ClangFrameLowering.h"
#include "V6ClangISelLowering.h"
#include "V6ClangInstrInfo.h"
#include "V6ClangRegisterInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/Target/TargetMachine.h"

#include "MCTargetDesc/V6ClangMCTargetDesc.h"

#define GET_SUBTARGETINFO_HEADER
#include "V6ClangGenSubtargetInfo.inc"

namespace llvm {

class V6ClangTargetMachine;

class V6ClangSubtarget : public V6ClangGenSubtargetInfo {
  V6ClangFrameLowering FrameLowering;
  V6ClangInstrInfo InstrInfo;
  V6ClangRegisterInfo RegInfo;
  V6ClangTargetLowering TLInfo;

public:
  V6ClangSubtarget(const Triple &TT, const std::string &CPU,
                const std::string &FS, const V6ClangTargetMachine &TM);

  const V6ClangInstrInfo *getInstrInfo() const override { return &InstrInfo; }
  const V6ClangFrameLowering *getFrameLowering() const override {
    return &FrameLowering;
  }
  const V6ClangTargetLowering *getTargetLowering() const override {
    return &TLInfo;
  }
  const V6ClangRegisterInfo *getRegisterInfo() const override { return &RegInfo; }

  /// Disable MachineBlockPlacement loop rotation for i8080.
  /// Loop rotation trades an entry JMP and rearranged intra-loop branches
  /// for an exit fall-through. On a CPU with no instruction cache, branch
  /// predictor, or speculation, that trade is always a net loss in both
  /// bytes and cycles, so we keep loops in their natural top-tested form.
  bool enableLoopRotationInBlockPlacement() const override { return false; }

  void ParseSubtargetFeatures(StringRef CPU, StringRef TuneCPU, StringRef FS);
};

} // namespace llvm

#endif // LLVM_LIB_TARGET_V6CLANG_V6ClangSUBTARGET_H
