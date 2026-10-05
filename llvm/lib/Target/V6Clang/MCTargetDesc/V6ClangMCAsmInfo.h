//===-- V6ClangMCAsmInfo.h - V6CLANG asm properties ---------------------*- C++ -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_V6CLANG_MCTARGETDESC_V6ClangMCASMINFO_H
#define LLVM_LIB_TARGET_V6CLANG_MCTARGETDESC_V6ClangMCASMINFO_H

#include "llvm/MC/MCAsmInfo.h"

namespace llvm {

class Triple;

class V6ClangMCAsmInfo : public MCAsmInfo {
public:
  explicit V6ClangMCAsmInfo(const Triple &TT, const MCTargetOptions &Options);
};

} // namespace llvm

#endif // LLVM_LIB_TARGET_V6CLANG_MCTARGETDESC_V6ClangMCASMINFO_H
