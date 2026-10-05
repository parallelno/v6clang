//===-- V6ClangMCInstLower.h - Lower MachineInstr to MCInst ---------*- C++ -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_V6CLANG_V6ClangMCINSTLOWER_H
#define LLVM_LIB_TARGET_V6CLANG_V6ClangMCINSTLOWER_H

#include "llvm/Support/Compiler.h"

namespace llvm {

class AsmPrinter;
class MachineInstr;
class MachineOperand;
class MCContext;
class MCInst;
class MCOperand;
class MCSymbol;

/// Lowers MachineInstr objects into MCInst objects.
class V6ClangMCInstLower {
public:
  V6ClangMCInstLower(MCContext &Ctx, AsmPrinter &Printer)
      : Ctx(Ctx), Printer(Printer) {}

  void lowerInstruction(const MachineInstr &MI, MCInst &OutMI) const;

private:
  MCContext &Ctx;
  AsmPrinter &Printer;

  MCOperand lowerSymbolOperand(const MachineOperand &MO,
                               MCSymbol *Sym) const;
};

} // namespace llvm

#endif // LLVM_LIB_TARGET_V6CLANG_V6ClangMCINSTLOWER_H
