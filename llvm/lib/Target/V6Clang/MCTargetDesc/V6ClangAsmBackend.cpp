//===-- V6ClangAsmBackend.cpp - V6CLANG Assembler Backend -------------------------===//
//
// Part of the V6CLANG backend for LLVM.
//
// Implements the MCAsmBackend for the V6CLANG target, handling fixups (address
// and immediate patching) and creating the ELF object writer.
//
//===----------------------------------------------------------------------===//

#include "V6ClangFixupKinds.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"

#include "llvm/MC/MCAsmBackend.h"
#include "llvm/MC/MCAssembler.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCELFObjectWriter.h"
#include "llvm/MC/MCFixupKindInfo.h"
#include "llvm/MC/MCObjectWriter.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/MCValue.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/ErrorHandling.h"

using namespace llvm;

namespace {

class V6ClangAsmBackend : public MCAsmBackend {
public:
  V6ClangAsmBackend() : MCAsmBackend(llvm::endianness::little) {}

  std::optional<MCFixupKind> getFixupKind(StringRef Name) const override {
    if (Name == "R_V6CLANG_8")
      return FK_Data_1;
    if (Name == "R_V6CLANG_16")
      return FK_Data_2;
    if (Name == "R_V6CLANG_32")
      return FK_Data_4;
    if (Name == "R_V6CLANG_LO8")
      return static_cast<MCFixupKind>(V6CLANG::fixup_v6clang_lo8);
    if (Name == "R_V6CLANG_HI8")
      return static_cast<MCFixupKind>(V6CLANG::fixup_v6clang_hi8);
    return std::nullopt;
  }

  unsigned getNumFixupKinds() const override {
    return V6CLANG::NumTargetFixupKinds;
  }

  const MCFixupKindInfo &getFixupKindInfo(MCFixupKind Kind) const override {
    const static MCFixupKindInfo Infos[V6CLANG::NumTargetFixupKinds] = {
        // name              offset  size  flags
        {"fixup_v6clang_8",   0, 8, 0},
        {"fixup_v6clang_16",  0, 16, 0},
        {"fixup_v6clang_lo8", 0, 8, 0},
        {"fixup_v6clang_hi8", 0, 8, 0},
    };

    if (Kind < FirstTargetFixupKind)
      return MCAsmBackend::getFixupKindInfo(Kind);

    assert(unsigned(Kind - FirstTargetFixupKind) < getNumFixupKinds() &&
           "Invalid kind!");
    return Infos[Kind - FirstTargetFixupKind];
  }

  void applyFixup(const MCAssembler &Asm, const MCFixup &Fixup,
                  const MCValue &Target, MutableArrayRef<char> Data,
                  uint64_t Value, bool IsResolved,
                  const MCSubtargetInfo *STI) const override {
    unsigned Offset = Fixup.getOffset();
    MCFixupKind Kind = Fixup.getKind();

    if (Kind == FK_Data_1 ||
        Kind == static_cast<MCFixupKind>(V6CLANG::fixup_v6clang_8)) {
      // 8-bit value, single byte.
      assert(Offset < Data.size() && "Fixup offset out of range");
      Data[Offset] = static_cast<char>(Value & 0xFF);
      return;
    }

    if (Kind == static_cast<MCFixupKind>(V6CLANG::fixup_v6clang_lo8)) {
      // Low byte of 16-bit value.
      assert(Offset < Data.size() && "Fixup offset out of range");
      Data[Offset] = static_cast<char>(Value & 0xFF);
      return;
    }

    if (Kind == static_cast<MCFixupKind>(V6CLANG::fixup_v6clang_hi8)) {
      // High byte of 16-bit value.
      assert(Offset < Data.size() && "Fixup offset out of range");
      Data[Offset] = static_cast<char>((Value >> 8) & 0xFF);
      return;
    }

    if (Kind == FK_Data_2 ||
        Kind == static_cast<MCFixupKind>(V6CLANG::fixup_v6clang_16)) {
      // 16-bit value, little-endian.
      assert(Offset + 1 < Data.size() && "Fixup offset out of range");
      Data[Offset] = static_cast<char>(Value & 0xFF);         // low byte
      Data[Offset + 1] = static_cast<char>((Value >> 8) & 0xFF); // high byte
      return;
    }

    if (Kind == FK_Data_4) {
      assert(Offset + 3 < Data.size() && "Fixup offset out of range");
      Data[Offset] = static_cast<char>(Value & 0xFF);
      Data[Offset + 1] = static_cast<char>((Value >> 8) & 0xFF);
      Data[Offset + 2] = static_cast<char>((Value >> 16) & 0xFF);
      Data[Offset + 3] = static_cast<char>((Value >> 24) & 0xFF);
      return;
    }

    llvm_unreachable("Unknown fixup kind!");
  }

  bool fixupNeedsRelaxation(const MCFixup &Fixup, uint64_t Value,
                            const MCRelaxableFragment *DF,
                            const MCAsmLayout &Layout) const override {
    // 8080 has no relaxable instructions.
    return false;
  }

  bool writeNopData(raw_ostream &OS, uint64_t Count,
                    const MCSubtargetInfo *STI) const override {
    // NOP on 8080 is 0x00.
    for (uint64_t i = 0; i < Count; ++i)
      OS.write('\0');
    return true;
  }

  std::unique_ptr<MCObjectTargetWriter>
  createObjectTargetWriter() const override;
};

} // anonymous namespace

// ===== ELF Object Writer ===== //

namespace {

class V6ClangELFObjectWriter : public MCELFObjectTargetWriter {
public:
  V6ClangELFObjectWriter()
      : MCELFObjectTargetWriter(/*Is64Bit=*/false, /*OSABI=*/0,
                                /*EMachine=*/ELF::EM_V6Clang,
                                /*HasRelocationAddend=*/true) {}

  unsigned getRelocType(MCContext &Ctx, const MCValue &Target,
                        const MCFixup &Fixup,
                        bool IsPCRel) const override {
    MCFixupKind Kind = Fixup.getKind();
    switch (static_cast<unsigned>(Kind)) {
    case FK_Data_1:
    case V6CLANG::fixup_v6clang_8:
      return V6CLANG::R_V6CLANG_8;
    case FK_Data_2:
    case V6CLANG::fixup_v6clang_16:
      return V6CLANG::R_V6CLANG_16;
    case FK_Data_4:
      return V6CLANG::R_V6CLANG_32;
    case V6CLANG::fixup_v6clang_lo8:
      return V6CLANG::R_V6CLANG_LO8;
    case V6CLANG::fixup_v6clang_hi8:
      return V6CLANG::R_V6CLANG_HI8;
    default:
      return V6CLANG::R_V6CLANG_NONE;
    }
  }
};

} // anonymous namespace

std::unique_ptr<MCObjectTargetWriter>
V6ClangAsmBackend::createObjectTargetWriter() const {
  return std::make_unique<V6ClangELFObjectWriter>();
}

namespace llvm {

MCAsmBackend *createV6ClangAsmBackend(const Target &T,
                                   const MCSubtargetInfo &STI,
                                   const MCRegisterInfo &MRI,
                                   const MCTargetOptions &Options) {
  return new V6ClangAsmBackend();
}

} // namespace llvm
