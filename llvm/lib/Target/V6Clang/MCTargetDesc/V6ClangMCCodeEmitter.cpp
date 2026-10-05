//===-- V6ClangMCCodeEmitter.cpp - Encode V6CLANG MCInst to binary ----------------===//
//
// Part of the V6CLANG backend for LLVM.
//
// Encodes MCInst instructions into their binary representation for the
// Intel 8080 instruction set.
//
//===----------------------------------------------------------------------===//

#include "V6ClangFixupKinds.h"
#include "V6ClangMCExpr.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"

#include "llvm/ADT/Statistic.h"
#include "llvm/MC/MCCodeEmitter.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCFixup.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstrDesc.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/Support/Endian.h"
#include "llvm/Support/EndianStream.h"
#include "llvm/Support/Casting.h"
#include "llvm/Support/raw_ostream.h"

#define DEBUG_TYPE "v6clang-mccodeemitter"

STATISTIC(MCNumEmitted, "Number of MC instructions emitted");

namespace llvm {

class V6ClangMCCodeEmitter : public MCCodeEmitter {
  const MCInstrInfo &MCII;
  MCContext &Ctx;

public:
  V6ClangMCCodeEmitter(const MCInstrInfo &MCII, MCContext &Ctx)
      : MCII(MCII), Ctx(Ctx) {}

  void encodeInstruction(const MCInst &MI, SmallVectorImpl<char> &CB,
                         SmallVectorImpl<MCFixup> &Fixups,
                         const MCSubtargetInfo &STI) const override;

  /// TableGen-generated function to get the binary encoding for an
  /// instruction.
  uint64_t getBinaryCodeForInstr(const MCInst &MI,
                                 SmallVectorImpl<MCFixup> &Fixups,
                                 const MCSubtargetInfo &STI) const;

  /// Called by the TableGen-generated encoder for each operand.
  uint64_t getMachineOpValue(const MCInst &MI, const MCOperand &MO,
                             SmallVectorImpl<MCFixup> &Fixups,
                             const MCSubtargetInfo &STI) const;
};

void V6ClangMCCodeEmitter::encodeInstruction(const MCInst &MI,
                                          SmallVectorImpl<char> &CB,
                                          SmallVectorImpl<MCFixup> &Fixups,
                                          const MCSubtargetInfo &STI) const {
  const MCInstrDesc &Desc = MCII.get(MI.getOpcode());
  unsigned Size = Desc.getSize();

  // Pseudo-instructions should have been expanded before reaching the emitter.
  if (Desc.isPseudo()) {
    llvm_unreachable("Pseudo instruction reached the code emitter!");
    return;
  }

  assert(Size > 0 && Size <= 3 && "Invalid V6CLANG instruction size");

  uint64_t Binary = getBinaryCodeForInstr(MI, Fixups, STI);

  // Emit bytes from most significant to least significant.
  // For the V6CLANG encoding layout:
  //   1-byte: Inst{7-0}   → byte 0
  //   2-byte: Inst{15-8}  → byte 0 (opcode), Inst{7-0} → byte 1 (imm8)
  //   3-byte: Inst{23-16} → byte 0 (opcode), Inst{15-8} → byte 1 (lo),
  //           Inst{7-0}   → byte 2 (hi)
  for (unsigned i = 0; i < Size; ++i) {
    unsigned Shift = (Size - 1 - i) * 8;
    CB.push_back(static_cast<char>((Binary >> Shift) & 0xFF));
  }

  ++MCNumEmitted;
}

uint64_t V6ClangMCCodeEmitter::getMachineOpValue(const MCInst &MI,
                                              const MCOperand &MO,
                                              SmallVectorImpl<MCFixup> &Fixups,
                                              const MCSubtargetInfo &STI) const {
  if (MO.isReg()) {
    unsigned Encoding = Ctx.getRegisterInfo()->getEncodingValue(MO.getReg());
    return Encoding;
  }

  if (MO.isImm())
    return static_cast<uint64_t>(MO.getImm());

  assert(MO.isExpr() && "Expected expression operand");

  const MCExpr *Expr = MO.getExpr();
  const MCInstrDesc &Desc = MCII.get(MI.getOpcode());
  unsigned Size = Desc.getSize();

  MCFixupKind Kind;
  unsigned Offset;

  // Check for V6CLANG lo8/hi8 expressions first.
  if (auto *V6ClangExpr = dyn_cast<V6ClangMCExpr>(Expr)) {
    assert(Size == 2 && "V6ClangMCExpr in non-MVI instruction");
    Kind = static_cast<MCFixupKind>(
        V6ClangExpr->getKind() == V6ClangMCExpr::VK_V6CLANG_LO8 ? V6Clang::fixup_v6clang_lo8
                                                      : V6Clang::fixup_v6clang_hi8);
    Offset = 1;
  } else if (Size == 3) {
    Kind = FK_Data_2;
    Offset = 1;
  } else if (Size == 2) {
    Kind = FK_Data_1;
    Offset = 1;
  } else {
    llvm_unreachable("Expression operand in 1-byte instruction");
  }

  Fixups.push_back(MCFixup::create(Offset, Expr, Kind, MI.getLoc()));
  return 0;
}

#include "V6ClangGenMCCodeEmitter.inc"

MCCodeEmitter *createV6ClangMCCodeEmitter(const MCInstrInfo &MCII,
                                       MCContext &Ctx) {
  return new V6ClangMCCodeEmitter(MCII, Ctx);
}

} // namespace llvm
