//===-- V6ClangTargetMachine.h - Define TargetMachine for V6CLANG -------*- C++ -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_V6CLANG_V6ClangTARGETMACHINE_H
#define LLVM_LIB_TARGET_V6CLANG_V6ClangTARGETMACHINE_H

#include "V6ClangSubtarget.h"
#include "V6ClangMachineFunctionInfo.h"
#include "llvm/Target/TargetMachine.h"
#include <memory>
#include <optional>

namespace llvm {

class TargetLoweringObjectFile;

class V6ClangTargetMachine : public LLVMTargetMachine {
public:
  V6ClangTargetMachine(const Target &T, const Triple &TT, StringRef CPU,
                    StringRef FS, const TargetOptions &Options,
                    std::optional<Reloc::Model> RM,
                    std::optional<CodeModel::Model> CM, CodeGenOptLevel OL,
                    bool JIT);

  ~V6ClangTargetMachine() override;

  const V6ClangSubtarget *getSubtargetImpl() const;
  const V6ClangSubtarget *getSubtargetImpl(const Function &) const override;

  TargetPassConfig *createPassConfig(PassManagerBase &PM) override;

  bool useIPRA() const override { return true; }

  TargetTransformInfo getTargetTransformInfo(const Function &F) const override;

  TargetLoweringObjectFile *getObjFileLowering() const override {
    return TLOF.get();
  }

  MachineFunctionInfo *
  createMachineFunctionInfo(BumpPtrAllocator &Allocator, const Function &F,
                            const TargetSubtargetInfo *STI) const override {
    return new (Allocator.Allocate<V6ClangMachineFunctionInfo>())
        V6ClangMachineFunctionInfo(F, STI);
  }

private:
  V6ClangSubtarget SubTarget;
  std::unique_ptr<TargetLoweringObjectFile> TLOF;
};

} // namespace llvm

#endif // LLVM_LIB_TARGET_V6CLANG_V6ClangTARGETMACHINE_H
