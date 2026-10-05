//===--- V6Clang.cpp - V6CLANG (Intel 8080) ToolChain Implementation -------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "CommonArgs.h"
#include "clang/Driver/Compilation.h"
#include "clang/Driver/Driver.h"
#include "clang/Driver/DriverDiagnostic.h"
#include "clang/Driver/InputInfo.h"
#include "clang/Driver/Options.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/Option/ArgList.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Path.h"

using namespace clang;
using namespace clang::driver;
using namespace clang::driver::toolchains;
using namespace clang::driver::tools;
using namespace llvm::opt;

/// Search a list of candidate paths for the first one that exists.
/// Returns empty string if none exist.
static std::string findFirstExisting(llvm::ArrayRef<std::string> Candidates) {
  for (const auto &P : Candidates)
    if (llvm::sys::fs::exists(P))
      return P;
  return std::string();
}

/// Locate a V6CLANG driver data file (linker script) by name.
/// Search order:
///   1. <bin>/../lib/clang/<ver>/v6clang/<filename>           (installed)
///   2. <bin>/../../clang/lib/Driver/ToolChains/V6CLANG/...   (workspace dev tree)
///   3. <bin>/../../llvm-project/clang/lib/...            (llvm-project mirror)
static std::string findV6ClangDriverFile(const ToolChain &TC, StringRef Filename) {
  StringRef Dir = TC.getDriver().Dir;
  llvm::SmallString<256> Installed(TC.getDriver().ResourceDir);
  llvm::sys::path::append(Installed, "v6clang", Filename);

  llvm::SmallString<256> DevTree(Dir);
  llvm::sys::path::append(DevTree, "..", "..", "clang", "lib");
  llvm::sys::path::append(DevTree, "Driver", "ToolChains", "V6CLANG", Filename);

  llvm::SmallString<256> MirrorTree(Dir);
  llvm::sys::path::append(MirrorTree, "..", "..", "llvm-project", "clang");
  llvm::sys::path::append(MirrorTree, "lib", "Driver", "ToolChains", "V6CLANG");
  llvm::sys::path::append(MirrorTree, Filename);

  return findFirstExisting({std::string(Installed), std::string(DevTree),
                            std::string(MirrorTree)});
}

/// Locate a V6CLANG runtime artifact (crt0.o) by name.
/// Search order:
///   1. <ResourceDir>/lib/v6clang/<filename>                    (installed)
///   2. <bin>/../../compiler-rt/lib/builtins/v6clang/<filename> (workspace dev tree)
/// Returns empty string if not found — caller should skip linking it.
static std::string findV6ClangRuntimeFile(const ToolChain &TC, StringRef Filename) {
  StringRef Dir = TC.getDriver().Dir;
  llvm::SmallString<256> Installed(TC.getDriver().ResourceDir);
  llvm::sys::path::append(Installed, "lib", "v6clang", Filename);

  llvm::SmallString<256> DevTree(Dir);
  llvm::sys::path::append(DevTree, "..", "..", "compiler-rt", "lib");
  llvm::sys::path::append(DevTree, "builtins", "v6clang", Filename);

  return findFirstExisting({std::string(Installed), std::string(DevTree)});
}

/// O70: locate a V6CLANG runtime header (v6clang_arith.h) by name.
/// Search order:
///   1. <ResourceDir>/lib/v6clang/include/<filename>                    (installed)
///   2. <bin>/../../compiler-rt/lib/builtins/v6clang/include/<filename> (workspace dev tree)
/// Returns empty string if not found — driver omits -include in that case.
static std::string findV6ClangHeader(const ToolChain &TC, StringRef Filename) {
  StringRef Dir = TC.getDriver().Dir;
  llvm::SmallString<256> Installed(TC.getDriver().ResourceDir);
  llvm::sys::path::append(Installed, "lib", "v6clang", "include", Filename);

  llvm::SmallString<256> DevTree(Dir);
  llvm::sys::path::append(DevTree, "..", "..", "compiler-rt", "lib");
  llvm::sys::path::append(DevTree, "builtins", "v6clang", "include", Filename);

  return findFirstExisting({std::string(Installed), std::string(DevTree)});
}

void v6clang::Linker::ConstructJob(Compilation &C, const JobAction &JA,
                                const InputInfo &Output,
                                const InputInfoList &Inputs,
                                const ArgList &Args,
                                const char *LinkingOutput) const {
  const ToolChain &TC = getToolChain();
  const Driver &D = TC.getDriver();

  // If the requested output is .elf or .o, the link result IS the final
  // product; otherwise produce a flat ROM via llvm-objcopy. Detect by
  // file extension (case-insensitive).
  StringRef OutName = Output.getFilename();
  StringRef Ext = llvm::sys::path::extension(OutName);
  bool ProduceFlat = !Ext.equals_insensitive(".elf") &&
                     !Ext.equals_insensitive(".o");

  // ----- ld.lld invocation -----
  ArgStringList CmdArgs;

  // ELF emulation — picks the V6CLANG lld backend.
  CmdArgs.push_back("-m");
  CmdArgs.push_back("elf32v6clang");

  // Default linker script (skipped when the user supplied -T <script>).
  if (!Args.hasArg(options::OPT_T)) {
    std::string Script = findV6ClangDriverFile(TC, "v6clang.ld");
    if (!Script.empty())
      CmdArgs.push_back(Args.MakeArgString(Twine("-T") + Script));
  }

  // Library search paths from -L and the toolchain.
  Args.AddAllArgs(CmdArgs, options::OPT_L);
  TC.AddFilePathLibArgs(Args, CmdArgs);

  // Forward user-supplied -T (in case both default and user scripts coexist;
  // ld.lld concatenates SECTIONS from multiple -T scripts).
  Args.AddAllArgs(CmdArgs, options::OPT_T);

  // Dead-strip unreferenced functions. addClangTargetOptions enables
  // -ffunction-sections by default so each function lives in its own
  // .text.<name> section, making this safe and effective. Lets the
  // O70 header-only runtime ship every libcall in every TU without
  // ROM bloat — only the ones actually referenced survive.
  CmdArgs.push_back("--gc-sections");

  // crt0.o (suppressed by -nostartfiles or -nostdlib).
  //
  // crt0.o is NOT built by ninja. It must be assembled out-of-band from
  // compiler-rt/lib/builtins/v6clang/crt0.s (see scripts/build_v6clang_runtime.ps1
  // and docs/V6ClangBuildGuide.md "V6CLANG runtime build"). If we silently skip it,
  // ld.lld --gc-sections has no _start root and drops *every* code section,
  // producing a zero-byte ROM. Make that a hard error so the failure is
  // obvious at link time; users who really mean to link without a startup
  // file must pass -nostartfiles (or -nostdlib).
  bool UseStartFiles = !Args.hasArg(options::OPT_nostartfiles,
                                    options::OPT_nostdlib, options::OPT_r);
  if (UseStartFiles) {
    std::string Crt0 = findV6ClangRuntimeFile(TC, "crt0.o");
    if (Crt0.empty()) {
      D.Diag(diag::err_drv_no_such_file)
          << "crt0.o (V6CLANG startup) — assemble crt0.s with "
             "scripts/build_v6clang_runtime.ps1, or pass -nostartfiles to opt out";
      return;
    }
    CmdArgs.push_back(Args.MakeArgString(Crt0));
  }

  // User input objects and -l libraries.
  // No default builtins archive: V6CLANG ships header-only inline-asm wrappers
  // (`<resource-dir>/lib/v6clang/include/`) plus per-routine `.o` files picked
  // up via the headers' `__asm__("CALL ...")` references and pruned by
  // ld.lld `--gc-sections`. See design/plan_asm_interop_overhaul.md.
  AddLinkerInputs(TC, Inputs, Args, CmdArgs, JA);

  // Forward -Wl,... and -Xlinker ... (covers --defsym, --gc-sections, etc.).
  // AddAllArgValues splits "-Wl,a,b,c" into individual tokens "a", "b", "c".
  Args.AddAllArgValues(CmdArgs, options::OPT_Wl_COMMA);
  Args.AddAllArgValues(CmdArgs, options::OPT_Xlinker);

  // Linker output: flat debug builds retain a deterministic sibling ELF as
  // their DWARF and symbol companion; non-debug ROM builds keep the existing
  // temporary ELF behavior.
  const char *LinkOutput;
  if (ProduceFlat) {
    if (Args.hasArg(options::OPT_g_Group)) {
      SmallString<256> DebugELF(OutName);
      llvm::sys::path::replace_extension(DebugELF, "elf");
      LinkOutput = Args.MakeArgString(DebugELF);
    } else {
      SmallString<128> Stem(llvm::sys::path::stem(OutName));
      std::string TmpPath = D.GetTemporaryPath(Stem, "elf");
      LinkOutput = C.addTempFile(Args.MakeArgString(TmpPath));
    }
  } else {
    LinkOutput = Output.getFilename();
  }
  CmdArgs.push_back("-o");
  CmdArgs.push_back(LinkOutput);

  std::string Linker = TC.GetProgramPath("ld.lld");
  C.addCommand(std::make_unique<Command>(
      JA, *this, ResponseFileSupport::AtFileCurCP(),
      Args.MakeArgString(Linker), CmdArgs, Inputs, Output));

  // ----- llvm-objcopy step (only when producing a flat ROM) -----
  if (ProduceFlat) {
    ArgStringList ObjArgs;
    ObjArgs.push_back("-O");
    ObjArgs.push_back("binary");
    ObjArgs.push_back(LinkOutput);
    ObjArgs.push_back(Output.getFilename());

    std::string ObjCopy = TC.GetProgramPath("llvm-objcopy");
    C.addCommand(std::make_unique<Command>(
        JA, *this, ResponseFileSupport::None(), Args.MakeArgString(ObjCopy),
        ObjArgs, Inputs, Output));
  }
}

V6ClangToolChain::V6ClangToolChain(const Driver &D, const llvm::Triple &Triple,
                            const ArgList &Args)
    : ToolChain(D, Triple, Args) {}

void V6ClangToolChain::addClangTargetOptions(
    const ArgList &DriverArgs, ArgStringList &CC1Args,
    Action::OffloadKind) const {
  // Force freestanding mode — no hosted C library.
  CC1Args.push_back("-ffreestanding");

  // Per-function ELF sections so ld.lld --gc-sections can prune
  // unreachable helpers transitively. User-passed -fno-function-sections
  // overrides.
  if (DriverArgs.hasFlag(options::OPT_ffunction_sections,
                         options::OPT_fno_function_sections,
                         /*Default=*/true))
    CC1Args.push_back("-ffunction-sections");

  // O70: auto-include v6clang_arith.h so libcall symbols (__mulhi3 etc.) are
  // defined in every TU. Suppressed by -fno-v6clang-auto-include for users
  // who want to supply their own runtime.
  if (!DriverArgs.hasArg(options::OPT_fno_v6clang_auto_include)) {
    std::string Hdr = findV6ClangHeader(*this, "v6clang_arith.h");
    if (!Hdr.empty()) {
      CC1Args.push_back("-include");
      CC1Args.push_back(DriverArgs.MakeArgString(Hdr));
    }
  }
}

/// O81: locate the V6CLANG runtime header directory — the single source of
/// truth for all V6CLANG runtime headers (<string.h>, <stdlib.h>, <v6clang.h>,
/// v6clang_arith.h, v6clang_rt_macros.h). Returns the *directory* for
/// `-internal-isystem`. Search order mirrors findV6ClangHeader.
static std::string findV6ClangRuntimeIncludeDir(const ToolChain &TC) {
  StringRef Dir = TC.getDriver().Dir;
  llvm::SmallString<256> Installed(TC.getDriver().ResourceDir);
  llvm::sys::path::append(Installed, "lib", "v6clang", "include");

  llvm::SmallString<256> DevTree(Dir);
  llvm::sys::path::append(DevTree, "..", "..", "compiler-rt", "lib");
  llvm::sys::path::append(DevTree, "builtins", "v6clang", "include");

  return findFirstExisting({std::string(Installed), std::string(DevTree)});
}

void V6ClangToolChain::AddClangSystemIncludeArgs(
    const ArgList &DriverArgs, ArgStringList &CC1Args) const {
  if (DriverArgs.hasArg(options::OPT_nostdinc))
    return;

  // O81: single runtime include path — compiler-rt/lib/builtins/v6clang/include/
  // (dev tree) or <ResourceDir>/lib/v6clang/include/ (installed). This directory
  // is the sole source for all V6CLANG runtime headers: <string.h>, <stdlib.h>,
  // <v6clang.h>, v6clang_arith.h, v6clang_rt_macros.h.
  if (!DriverArgs.hasArg(options::OPT_nostdlibinc)) {
    std::string RtIncDir = findV6ClangRuntimeIncludeDir(*this);
    if (!RtIncDir.empty()) {
      CC1Args.push_back("-internal-isystem");
      CC1Args.push_back(DriverArgs.MakeArgString(RtIncDir));
    }
  }

  // Standard freestanding headers (stdint.h, stddef.h, ...) under the
  // resource directory.
  if (!DriverArgs.hasArg(options::OPT_nobuiltininc)) {
    llvm::SmallString<128> Dir(getDriver().ResourceDir);
    llvm::sys::path::append(Dir, "include");
    CC1Args.push_back("-internal-isystem");
    CC1Args.push_back(DriverArgs.MakeArgString(Dir));
  }
}

Tool *V6ClangToolChain::buildLinker() const {
  return new tools::v6clang::Linker(*this);
}
