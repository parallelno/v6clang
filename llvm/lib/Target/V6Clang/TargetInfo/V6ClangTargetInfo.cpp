//===-- V6ClangTargetInfo.cpp - V6CLANG Target Implementation ---------------------===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#include "TargetInfo/V6ClangTargetInfo.h"
#include "llvm/MC/TargetRegistry.h"

namespace llvm {
Target &getTheV6ClangTarget() {
  static Target TheV6ClangTarget;
  return TheV6ClangTarget;
}
} // namespace llvm

extern "C" LLVM_EXTERNAL_VISIBILITY void LLVMInitializeV6ClangTargetInfo() {
  llvm::RegisterTarget<llvm::Triple::i8080> X(
      llvm::getTheV6ClangTarget(), "v6clang", "Vector 06c (Intel 8080)", "V6Clang");
}

// LLVMInitializeV6ClangAsmParser is defined in AsmParser/V6ClangAsmParser.cpp.
