//===-- V6ClangMCAsmInfo.cpp - V6CLANG asm properties -----------------------------===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#include "V6ClangMCAsmInfo.h"
#include "llvm/TargetParser/Triple.h"

namespace llvm {

V6ClangMCAsmInfo::V6ClangMCAsmInfo(const Triple &TT, const MCTargetOptions &Options) {
  CodePointerSize = 2;
  CalleeSaveStackSlotSize = 2;
  CommentString = ";";
  PrivateGlobalPrefix = ".L";
  PrivateLabelPrefix = ".L";
  LabelSuffix = ":";
  SeparatorString = "\n";
  AlignmentIsInBytes = true;
  UsesELFSectionDirectiveForBSS = true;
  // 8080 assembly uses uppercase mnemonics matched by TableGen AsmString.
  // Data directives compatible with common 8080 assemblers.
  Data8bitsDirective = "\tDB\t";
  Data16bitsDirective = "\tDW\t";
  Data32bitsDirective = nullptr; // No native 32-bit data directive.
  Data64bitsDirective = nullptr;
  ZeroDirective = nullptr; // No .zero equivalent; use DB 0 sequences.
  AscizDirective = nullptr; // No null-terminated string directive.
  HasDotTypeDotSizeDirective = false;
  HasSingleParameterDotFile = false;
  SupportsDebugInformation = true;
  UsesCFIWithoutEH = true;
  IsLittleEndian = true;
}

} // namespace llvm
