//===-- V6ClangMCTargetDesc.h - V6CLANG Target Descriptions -------------*- C++ -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_V6CLANG_MCTARGETDESC_V6ClangMCTARGETDESC_H
#define LLVM_LIB_TARGET_V6CLANG_MCTARGETDESC_V6ClangMCTARGETDESC_H

#include "llvm/Support/DataTypes.h"
#include <memory>

namespace llvm {

class MCAsmBackend;
class MCCodeEmitter;
class MCContext;
class MCInstrInfo;
class MCRegisterInfo;
class MCSubtargetInfo;
class MCTargetOptions;
class Target;

MCInstrInfo *createV6ClangMCInstrInfo();
MCCodeEmitter *createV6ClangMCCodeEmitter(const MCInstrInfo &MCII,
                                       MCContext &Ctx);
MCAsmBackend *createV6ClangAsmBackend(const Target &T,
                                   const MCSubtargetInfo &STI,
                                   const MCRegisterInfo &MRI,
                                   const MCTargetOptions &Options);

} // namespace llvm

#define GET_REGINFO_ENUM
#include "V6ClangGenRegisterInfo.inc"

#define GET_INSTRINFO_ENUM
#define GET_INSTRINFO_MC_HELPER_DECLS
#include "V6ClangGenInstrInfo.inc"

#define GET_SUBTARGETINFO_ENUM
#include "V6ClangGenSubtargetInfo.inc"

#endif // LLVM_LIB_TARGET_V6CLANG_MCTARGETDESC_V6ClangMCTARGETDESC_H
