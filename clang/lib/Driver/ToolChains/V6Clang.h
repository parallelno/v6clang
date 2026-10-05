//===--- V6Clang.h - V6CLANG (Intel 8080) Tool and ToolChain ------------*- C++-*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_CLANG_LIB_DRIVER_TOOLCHAINS_V6CLANG_H
#define LLVM_CLANG_LIB_DRIVER_TOOLCHAINS_V6CLANG_H

#include "clang/Driver/Tool.h"
#include "clang/Driver/ToolChain.h"

namespace clang {
namespace driver {
namespace tools {
namespace v6clang {

class LLVM_LIBRARY_VISIBILITY Linker final : public Tool {
public:
  Linker(const ToolChain &TC) : Tool("v6clang::Linker", "ld.lld", TC) {}
  bool isLinkJob() const override { return true; }
  bool hasIntegratedCPP() const override { return false; }
  void ConstructJob(Compilation &C, const JobAction &JA,
                    const InputInfo &Output, const InputInfoList &Inputs,
                    const llvm::opt::ArgList &TCArgs,
                    const char *LinkingOutput) const override;
};

} // namespace v6clang
} // namespace tools
namespace toolchains {

class LLVM_LIBRARY_VISIBILITY V6ClangToolChain : public ToolChain {
public:
  V6ClangToolChain(const Driver &D, const llvm::Triple &Triple,
               const llvm::opt::ArgList &Args);

  bool useIntegratedAs() const override { return true; }
  bool isBareMetal() const override { return true; }
  bool isCrossCompiling() const override { return true; }
  bool isPICDefault() const override { return false; }
  bool isPIEDefault(const llvm::opt::ArgList &Args) const override {
    return false;
  }
  bool isPICDefaultForced() const override { return true; }
  bool SupportsProfiling() const override { return false; }
  bool HasNativeLLVMSupport() const override { return true; }

  UnwindLibType
  GetUnwindLibType(const llvm::opt::ArgList &Args) const override {
    return UNW_None;
  }

  void addClangTargetOptions(const llvm::opt::ArgList &DriverArgs,
                             llvm::opt::ArgStringList &CC1Args,
                             Action::OffloadKind) const override;

  void AddClangSystemIncludeArgs(
      const llvm::opt::ArgList &DriverArgs,
      llvm::opt::ArgStringList &CC1Args) const override;

protected:
  Tool *buildLinker() const override;
};

} // namespace toolchains
} // namespace driver
} // namespace clang

#endif // LLVM_CLANG_LIB_DRIVER_TOOLCHAINS_V6CLANG_H
