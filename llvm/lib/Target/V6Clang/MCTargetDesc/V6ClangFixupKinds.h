//===-- V6ClangFixupKinds.h - V6CLANG Specific Fixup Entries ------------*- C++ -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_V6CLANG_MCTARGETDESC_V6ClangFIXUPKINDS_H
#define LLVM_LIB_TARGET_V6CLANG_MCTARGETDESC_V6ClangFIXUPKINDS_H

#include "llvm/MC/MCFixup.h"

namespace llvm {
namespace V6Clang {

enum Fixups {
  /// 8-bit absolute value (immediate operand at byte offset 1).
  fixup_v6clang_8 = FirstTargetFixupKind,

  /// 16-bit absolute address (at byte offset 1, little-endian).
  fixup_v6clang_16,

  /// Low byte of 16-bit address (for MVI in V6CLANG_BR_CC16_IMM).
  fixup_v6clang_lo8,

  /// High byte of 16-bit address (for MVI in V6CLANG_BR_CC16_IMM).
  fixup_v6clang_hi8,

  // Marker
  fixup_v6clang_invalid,
  NumTargetFixupKinds = fixup_v6clang_invalid - FirstTargetFixupKind
};

/// V6CLANG ELF relocation types.
/// Used by both V6ClangELFObjectWriter (emitter) and lld/ELF/Arch/V6Clang.cpp
/// (consumer). The e_machine value is ELF::EM_V6Clang (0x8080).
enum RelocType {
  R_V6CLANG_NONE = 0,
  R_V6CLANG_8    = 1,   ///< 8-bit absolute value
  R_V6CLANG_16   = 2,   ///< 16-bit absolute address (little-endian)
  R_V6CLANG_LO8  = 3,   ///< Low byte of 16-bit address
  R_V6CLANG_HI8  = 4,   ///< High byte of 16-bit address
  R_V6CLANG_32   = 5,   ///< 32-bit absolute value (little-endian)
};

} // namespace V6Clang
} // namespace llvm

#endif // LLVM_LIB_TARGET_V6CLANG_MCTARGETDESC_V6ClangFIXUPKINDS_H
