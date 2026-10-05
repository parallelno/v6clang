//===--- I8080.h - Declare I8080/V6Clang target feature support -------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file declares I8080 (Vector 06c) TargetInfo objects.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_CLANG_LIB_BASIC_TARGETS_I8080_H
#define LLVM_CLANG_LIB_BASIC_TARGETS_I8080_H

#include "clang/Basic/TargetBuiltins.h"
#include "clang/Basic/TargetInfo.h"
#include "clang/Basic/TargetOptions.h"
#include "llvm/Support/Compiler.h"
#include "llvm/TargetParser/Triple.h"

namespace clang {
namespace targets {


// Intel 8080 / Vector 06c Target
class LLVM_LIBRARY_VISIBILITY I8080TargetInfo : public TargetInfo {
public:
  I8080TargetInfo(const llvm::Triple &Triple, const TargetOptions &)
      : TargetInfo(Triple) {
    // No TLS on bare-metal single-threaded system.
    TLSSupported = false;

    // 16-bit pointers (64 KB flat address space).
    PointerWidth = 16;
    PointerAlign = 8;

    // int = 16 bits (matches pointer width per design §2.3).
    IntWidth = 16;
    IntAlign = 8;

    // long = 32 bits (synthesized via register pair sequences).
    LongWidth = 32;
    LongAlign = 8;

    // long long = 64 bits (supported but expensive).
    LongLongWidth = 64;
    LongLongAlign = 8;

    // No alignment requirements on 8080.
    SuitableAlign = 8;
    DefaultAlignForAttributeAligned = 8;

    // Float/double — no FPU, software only; use IEEE single for both.
    HalfWidth = 16;
    HalfAlign = 8;
    FloatWidth = 32;
    FloatAlign = 8;
    DoubleWidth = 32;
    DoubleAlign = 8;
    DoubleFormat = &llvm::APFloat::IEEEsingle();
    LongDoubleWidth = 32;
    LongDoubleAlign = 8;
    LongDoubleFormat = &llvm::APFloat::IEEEsingle();

    // Type mappings for stdint/stddef.
    SizeType = UnsignedInt;
    PtrDiffType = SignedInt;
    IntPtrType = SignedInt;
    Char16Type = UnsignedInt;
    WIntType = SignedInt;
    Int16Type = SignedInt;
    Char32Type = UnsignedLong;
    SigAtomicType = SignedChar;

    // Data layout: little-endian, 16-bit pointers, 8-bit aligned everything,
    // native i8/i16.
    resetDataLayout("e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8");
  }

  void getTargetDefines(const LangOptions &Opts,
                        MacroBuilder &Builder) const override;

  ArrayRef<Builtin::Info> getTargetBuiltins() const override;

  BuiltinVaListKind getBuiltinVaListKind() const override {
    return TargetInfo::VoidPtrBuiltinVaList;
  }

  std::string_view getClobbers() const override { return ""; }

  ArrayRef<const char *> getGCCRegNames() const override;

  ArrayRef<TargetInfo::GCCRegAlias> getGCCRegAliases() const override {
    return std::nullopt;
  }

  bool validateAsmConstraint(const char *&Name,
                             TargetInfo::ConstraintInfo &Info) const override {
    switch (*Name) {
    default:
      return false;
    case 'a': // Accumulator (A register)
      Info.setAllowsRegister();
      return true;
    case 'r': // Any 8-bit general register
      Info.setAllowsRegister();
      return true;
    case 'p': // Any 16-bit register pair (BC, DE, HL)
      Info.setAllowsRegister();
      return true;
    case 'I': // 8-bit unsigned immediate (0-255)
      Info.setRequiresImmediate(0, 255);
      return true;
    case 'J': // 16-bit unsigned immediate (0-65535)
      Info.setRequiresImmediate(0, 65535);
      return true;
    }
  }

  IntType getIntTypeByWidth(unsigned BitWidth, bool IsSigned) const final {
    // Prefer int for 16-bit integers.
    return BitWidth == 16 ? (IsSigned ? SignedInt : UnsignedInt)
                          : TargetInfo::getIntTypeByWidth(BitWidth, IsSigned);
  }

  IntType getLeastIntTypeByWidth(unsigned BitWidth,
                                 bool IsSigned) const final {
    return BitWidth == 16
               ? (IsSigned ? SignedInt : UnsignedInt)
               : TargetInfo::getLeastIntTypeByWidth(BitWidth, IsSigned);
  }

  bool isValidCPUName(StringRef Name) const override {
    return Name == "i8080";
  }

  void fillValidCPUList(SmallVectorImpl<StringRef> &Values) const override {
    Values.push_back("i8080");
  }

  bool setCPU(const std::string &Name) override {
    return Name == "i8080";
  }
};

} // namespace targets
} // namespace clang

#endif // LLVM_CLANG_LIB_BASIC_TARGETS_I8080_H
