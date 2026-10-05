//===-- V6ClangInstPrinter.cpp - Convert V6CLANG MCInst to assembly ---------------===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#include "V6ClangInstPrinter.h"
#include "V6ClangMCTargetDesc.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/Support/FormattedStream.h"

using namespace llvm;

#define DEBUG_TYPE "asm-printer"

// Include the auto-generated portion of the assembly writer.
#include "V6ClangGenAsmWriter.inc"

void V6ClangInstPrinter::printInst(const MCInst *MI, uint64_t Address,
                                StringRef Annot, const MCSubtargetInfo &STI,
                                raw_ostream &O) {
  printInstruction(MI, Address, O);
  printAnnotation(O, Annot);
}

void V6ClangInstPrinter::printOperand(const MCInst *MI, unsigned OpNo,
                                   raw_ostream &O) {
  const MCOperand &Op = MI->getOperand(OpNo);

  if (Op.isReg()) {
    O << getRegisterName(Op.getReg(), V6CLANG::NoRegAltName);
  } else if (Op.isImm()) {
    // Print immediates as hex with 0x prefix for v6asm compatibility.
    // Mask to 16 bits — the widest immediate the 8080 supports.
    int64_t Val = Op.getImm();
    uint64_t UVal = static_cast<uint64_t>(Val) & 0xFFFF;
    if (UVal <= 9)
      O << UVal;
    else
      O << formatHex(UVal);
  } else if (Op.isExpr()) {
    Op.getExpr()->print(O, &MAI);
  }
}

void V6ClangInstPrinter::printImm8Operand(const MCInst *MI, unsigned OpNo,
                                       raw_ostream &O) {
  const MCOperand &Op = MI->getOperand(OpNo);

  if (Op.isImm()) {
    uint64_t UVal = static_cast<uint64_t>(Op.getImm()) & 0xFF;
    if (UVal <= 9)
      O << UVal;
    else
      O << formatHex(UVal);
  } else if (Op.isExpr()) {
    Op.getExpr()->print(O, &MAI);
  }
}

void V6ClangInstPrinter::printBrTarget(const MCInst *MI, unsigned OpNo,
                                    raw_ostream &O) {
  const MCOperand &Op = MI->getOperand(OpNo);

  if (Op.isImm()) {
    O << formatHex(static_cast<uint64_t>(Op.getImm()));
  } else if (Op.isExpr()) {
    Op.getExpr()->print(O, &MAI);
  }
}

// Print a register operand using the i8080-canonical pair-form spelling
// (BC->"B", DE->"D", HL->"H", SP->"SP", PSW->"PSW"). Used by every
// instruction that takes a register-pair operand.
void V6ClangInstPrinter::printRegPair8080(const MCInst *MI, unsigned OpNo,
                                       raw_ostream &O) {
  const MCOperand &Op = MI->getOperand(OpNo);
  if (Op.isReg())
    O << getRegisterName(Op.getReg(), V6CLANG::Pair8080);
  else
    printOperand(MI, OpNo, O);
}
