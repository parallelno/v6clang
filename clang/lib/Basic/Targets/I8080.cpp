//===--- I8080.cpp - Implement I8080/V6CLANG target feature support ------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file implements I8080 (Vector 06c) TargetInfo objects.
//
//===----------------------------------------------------------------------===//

#include "I8080.h"
#include "clang/Basic/MacroBuilder.h"
#include "clang/Basic/TargetBuiltins.h"

using namespace clang;
using namespace clang::targets;

static constexpr Builtin::Info BuiltinInfo[] = {
#define BUILTIN(ID, TYPE, ATTRS)                                               \
  {#ID, TYPE, ATTRS, nullptr, HeaderDesc::NO_HEADER, ALL_LANGUAGES},
#include "clang/Basic/BuiltinsV6CLANG.def"
};

void I8080TargetInfo::getTargetDefines(const LangOptions &Opts,
                                       MacroBuilder &Builder) const {
  Builder.defineMacro("__I8080__");
  Builder.defineMacro("__V6CLANG__");
}

ArrayRef<Builtin::Info> I8080TargetInfo::getTargetBuiltins() const {
  return llvm::ArrayRef(BuiltinInfo, clang::V6CLANG::LastTSBuiltin -
                                         Builtin::FirstTSBuiltin);
}

ArrayRef<const char *> I8080TargetInfo::getGCCRegNames() const {
  static const char *const GCCRegNames[] = {
      "A", "B", "C", "D", "E", "H", "L", "SP", "FLAGS",
      "BC", "DE", "HL", "PSW"};
  return llvm::ArrayRef(GCCRegNames);
}
