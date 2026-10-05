//===-- V6ClangMCTargetDesc.cpp - V6CLANG Target Descriptions ---------------------===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#include "V6ClangMCTargetDesc.h"
#include "V6ClangInstPrinter.h"
#include "V6ClangMCAsmInfo.h"
#include "TargetInfo/V6ClangTargetInfo.h"

#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/TargetRegistry.h"

#define GET_INSTRINFO_MC_DESC
#define ENABLE_INSTR_PREDICATE_VERIFIER
#include "V6ClangGenInstrInfo.inc"

#define GET_SUBTARGETINFO_MC_DESC
#include "V6ClangGenSubtargetInfo.inc"

#define GET_REGINFO_MC_DESC
#include "V6ClangGenRegisterInfo.inc"

using namespace llvm;

MCInstrInfo *llvm::createV6ClangMCInstrInfo() {
  MCInstrInfo *X = new MCInstrInfo();
  InitV6ClangMCInstrInfo(X);
  return X;
}

static MCRegisterInfo *createV6ClangMCRegisterInfo(const Triple &TT) {
  MCRegisterInfo *X = new MCRegisterInfo();
  InitV6ClangMCRegisterInfo(X, V6CLANG::PC);
  return X;
}

static MCSubtargetInfo *createV6ClangMCSubtargetInfo(const Triple &TT,
                                                  StringRef CPU,
                                                  StringRef FS) {
  return createV6ClangMCSubtargetInfoImpl(TT, CPU, /*TuneCPU*/ CPU, FS);
}

static MCInstPrinter *createV6ClangMCInstPrinter(const Triple &T,
                                              unsigned SyntaxVariant,
                                              const MCAsmInfo &MAI,
                                              const MCInstrInfo &MII,
                                              const MCRegisterInfo &MRI) {
  if (SyntaxVariant == 0)
    return new V6ClangInstPrinter(MAI, MII, MRI);
  return nullptr;
}

extern "C" LLVM_EXTERNAL_VISIBILITY void LLVMInitializeV6ClangTargetMC() {
  RegisterMCAsmInfo<V6ClangMCAsmInfo> X(getTheV6ClangTarget());

  TargetRegistry::RegisterMCInstrInfo(getTheV6ClangTarget(), createV6ClangMCInstrInfo);
  TargetRegistry::RegisterMCRegInfo(getTheV6ClangTarget(),
                                    createV6ClangMCRegisterInfo);
  TargetRegistry::RegisterMCSubtargetInfo(getTheV6ClangTarget(),
                                          createV6ClangMCSubtargetInfo);
  TargetRegistry::RegisterMCInstPrinter(getTheV6ClangTarget(),
                                        createV6ClangMCInstPrinter);
  TargetRegistry::RegisterMCCodeEmitter(getTheV6ClangTarget(),
                                        createV6ClangMCCodeEmitter);
  TargetRegistry::RegisterMCAsmBackend(getTheV6ClangTarget(),
                                       createV6ClangAsmBackend);
}
