//===-- V6ClangSubtarget.cpp - V6CLANG Subtarget Information ----------------------===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#include "V6ClangSubtarget.h"
#include "V6ClangTargetMachine.h"

#define DEBUG_TYPE "v6clang-subtarget"

#define GET_SUBTARGETINFO_TARGET_DESC
#define GET_SUBTARGETINFO_CTOR
#include "V6ClangGenSubtargetInfo.inc"

namespace llvm {

V6ClangSubtarget::V6ClangSubtarget(const Triple &TT, const std::string &CPU,
                             const std::string &FS,
                             const V6ClangTargetMachine &TM)
    : V6ClangGenSubtargetInfo(TT, CPU, /*TuneCPU*/ CPU, FS),
      TLInfo(TM, *this) {
  ParseSubtargetFeatures(CPU, /*TuneCPU*/ CPU, FS);
}

} // namespace llvm
