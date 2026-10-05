//===-- V6ClangMCInstLower.cpp - Convert V6CLANG MachineInstr to MCInst -----------===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#include "V6ClangMCInstLower.h"
#include "V6ClangInstrInfo.h"
#include "MCTargetDesc/V6ClangMCExpr.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "llvm/CodeGen/AsmPrinter.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/CodeGen/MachineOperand.h"
#include "llvm/IR/Mangler.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCInst.h"
#include "llvm/Support/ErrorHandling.h"

using namespace llvm;

MCOperand V6ClangMCInstLower::lowerSymbolOperand(const MachineOperand &MO,
                                              MCSymbol *Sym) const {
  const MCExpr *Expr = MCSymbolRefExpr::create(Sym, Ctx);

  if (!MO.isJTI() && MO.getOffset())
    Expr = MCBinaryExpr::createAdd(
        Expr, MCConstantExpr::create(MO.getOffset(), Ctx), Ctx);

  // Wrap in V6ClangMCExpr for lo8/hi8 byte extraction if target flags request it.
  unsigned TF = MO.getTargetFlags();
  if (TF & V6ClangII::MO_LO8)
    Expr = V6ClangMCExpr::create(V6ClangMCExpr::VK_V6CLANG_LO8, Expr, Ctx);
  else if (TF & V6ClangII::MO_HI8)
    Expr = V6ClangMCExpr::create(V6ClangMCExpr::VK_V6CLANG_HI8, Expr, Ctx);

  return MCOperand::createExpr(Expr);
}

void V6ClangMCInstLower::lowerInstruction(const MachineInstr &MI,
                                       MCInst &OutMI) const {
  OutMI.setOpcode(MI.getOpcode());

  for (const MachineOperand &MO : MI.operands()) {
    MCOperand MCOp;

    switch (MO.getType()) {
    default:
      MI.print(errs());
      llvm_unreachable("unknown operand type");
    case MachineOperand::MO_Register:
      // Skip implicit register operands.
      if (MO.isImplicit())
        continue;
      MCOp = MCOperand::createReg(MO.getReg());
      break;
    case MachineOperand::MO_Immediate:
      MCOp = MCOperand::createImm(MO.getImm());
      break;
    case MachineOperand::MO_GlobalAddress:
      MCOp = lowerSymbolOperand(MO, Printer.getSymbol(MO.getGlobal()));
      break;
    case MachineOperand::MO_ExternalSymbol:
      MCOp = lowerSymbolOperand(
          MO, Printer.GetExternalSymbolSymbol(MO.getSymbolName()));
      break;
    case MachineOperand::MO_MachineBasicBlock:
      MCOp = MCOperand::createExpr(
          MCSymbolRefExpr::create(MO.getMBB()->getSymbol(), Ctx));
      break;
    case MachineOperand::MO_RegisterMask:
      continue;
    case MachineOperand::MO_BlockAddress:
      MCOp = lowerSymbolOperand(
          MO, Printer.GetBlockAddressSymbol(MO.getBlockAddress()));
      break;
    case MachineOperand::MO_MCSymbol: {
      // O61: patched-reload site reference. Operand is an MCSymbol;
      // MO_PATCH_IMM means we want `Sym + 1` (the imm field of the LXI).
      MCSymbol *Sym = MO.getMCSymbol();
      const MCExpr *Expr = MCSymbolRefExpr::create(Sym, Ctx);
      unsigned TF = MO.getTargetFlags();
      if (TF & V6ClangII::MO_PATCH_IMM)
        Expr = MCBinaryExpr::createAdd(
            Expr, MCConstantExpr::create(1, Ctx), Ctx);
      MCOp = MCOperand::createExpr(Expr);
      break;
    }
    }

    OutMI.addOperand(MCOp);
  }
}
