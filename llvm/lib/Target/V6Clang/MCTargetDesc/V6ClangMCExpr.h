//===-- V6ClangMCExpr.h - V6CLANG specific MC expression classes --------*- C++ -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
// Defines V6ClangMCExpr for lo8/hi8 byte extraction of 16-bit values,
// used by MVI instructions in the V6CLANG_BR_CC16_IMM expansion.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_V6CLANG_MCTARGETDESC_V6ClangMCEXPR_H
#define LLVM_LIB_TARGET_V6CLANG_MCTARGETDESC_V6ClangMCEXPR_H

#include "llvm/MC/MCExpr.h"

namespace llvm {

class V6ClangMCExpr : public MCTargetExpr {
public:
  enum VariantKind {
    VK_V6CLANG_LO8, // Low byte of 16-bit value: <(expr)
    VK_V6CLANG_HI8, // High byte of 16-bit value: >(expr)
  };

private:
  const VariantKind Kind;
  const MCExpr *Expr;

  explicit V6ClangMCExpr(VariantKind K, const MCExpr *E) : Kind(K), Expr(E) {}

public:
  static const V6ClangMCExpr *create(VariantKind K, const MCExpr *E,
                                 MCContext &Ctx);

  VariantKind getKind() const { return Kind; }
  const MCExpr *getSubExpr() const { return Expr; }

  void printImpl(raw_ostream &OS, const MCAsmInfo *MAI) const override;
  bool evaluateAsRelocatableImpl(MCValue &Res, const MCAsmLayout *Layout,
                                 const MCFixup *Fixup) const override;
  void visitUsedExpr(MCStreamer &S) const override;
  MCFragment *findAssociatedFragment() const override;
  void fixELFSymbolsInTLSFixups(MCAssembler &) const override {}
};

} // namespace llvm

#endif // LLVM_LIB_TARGET_V6CLANG_MCTARGETDESC_V6ClangMCEXPR_H
