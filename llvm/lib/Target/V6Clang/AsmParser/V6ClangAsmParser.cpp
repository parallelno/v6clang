//===-- V6ClangAsmParser.cpp - Parse V6CLANG (i8080) assembly to MCInst -----------===//
//
// Part of the V6CLANG backend for LLVM.
//
// V6CLANG assembly parser. Accepts only the i8080-canonical assembly dialect
// emitted by V6ClangInstPrinter:
//
//   * 8-bit register names: A B C D E H L
//   * 16-bit register names: SP, PSW
//   * Pair-letter forms used by every pair-taking mnemonic
//     (PUSH/POP/DAD/INX/DCX/LXI/LDAX/STAX): "B" -> BC, "D" -> DE, "H" -> HL.
//   * The literal "M" token used by MOV r,M / MOV M,r / ADD M / etc.
//
// Long pair forms ("HL", "DE", "BC") are NOT accepted; using them in any
// context produces a parse error. This is a deliberate choice so that the
// parser can never disagree with the printer — there is exactly one spelling
// for every pair operand.
//
//===----------------------------------------------------------------------===//

#include "MCTargetDesc/V6ClangMCExpr.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "TargetInfo/V6ClangTargetInfo.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCParser/MCAsmLexer.h"
#include "llvm/MC/MCParser/MCParsedAsmOperand.h"
#include "llvm/MC/MCParser/MCTargetAsmParser.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCStreamer.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Casting.h"

#define DEBUG_TYPE "v6clang-asm-parser"

using namespace llvm;

namespace {

class V6ClangOperand;

class V6ClangAsmParser : public MCTargetAsmParser {
  const MCSubtargetInfo &STI;
  MCAsmParser &Parser;

  MCAsmParser &getParser() const { return Parser; }
  MCAsmLexer  &getLexer()  const { return Parser.getLexer(); }

  // MCTargetAsmParser overrides.
  bool MatchAndEmitInstruction(SMLoc IDLoc, unsigned &Opcode,
                               OperandVector &Operands, MCStreamer &Out,
                               uint64_t &ErrorInfo,
                               bool MatchingInlineAsm) override;

  bool parseRegister(MCRegister &Reg, SMLoc &StartLoc, SMLoc &EndLoc) override;
  ParseStatus tryParseRegister(MCRegister &Reg, SMLoc &StartLoc,
                               SMLoc &EndLoc) override;

  bool ParseInstruction(ParseInstructionInfo &Info, StringRef Name,
                        SMLoc NameLoc, OperandVector &Operands) override;

  unsigned validateTargetOperandClass(MCParsedAsmOperand &Op,
                                      unsigned Kind) override;

  // Operand-parsing helpers.
  bool parseOperand(OperandVector &Operands);

  // Map an i8080-canonical identifier to its MCRegister, or NoRegister if
  // the spelling is not accepted in any context.
  static MCRegister matchRegisterName(StringRef Name);

  /// @name Auto-generated Matcher Functions
  /// {

#define GET_ASSEMBLER_HEADER
#include "V6ClangGenAsmMatcher.inc"

  /// }

public:
  V6ClangAsmParser(const MCSubtargetInfo &STI, MCAsmParser &Parser,
               const MCInstrInfo &MII, const MCTargetOptions &Options)
      : MCTargetAsmParser(Options, STI, MII), STI(STI), Parser(Parser) {
    MCAsmParserExtension::Initialize(Parser);
    setAvailableFeatures(ComputeAvailableFeatures(STI.getFeatureBits()));
  }
};

/// A parsed V6CLANG assembly operand.
class V6ClangOperand : public MCParsedAsmOperand {
  enum KindTy { k_Tok, k_Reg, k_Imm } Kind;

  struct RegOp {
    unsigned RegNum;
  };

  union {
    StringRef Tok;
    RegOp Reg;
    const MCExpr *Imm;
  };

  SMLoc Start, End;

public:
  V6ClangOperand(KindTy K, SMLoc S, SMLoc E) : Kind(K), Start(S), End(E) {}

  // MCParsedAsmOperand interface.
  bool isToken() const override { return Kind == k_Tok; }
  bool isReg()   const override { return Kind == k_Reg; }
  bool isImm()   const override { return Kind == k_Imm; }
  bool isMem()   const override { return false; }

  SMLoc getStartLoc() const override { return Start; }
  SMLoc getEndLoc()   const override { return End;   }

  StringRef getToken() const {
    assert(Kind == k_Tok && "not a token");
    return Tok;
  }

  unsigned getReg() const override {
    assert(Kind == k_Reg && "not a register");
    return Reg.RegNum;
  }

  void setReg(unsigned RegNum) {
    assert(Kind == k_Reg && "not a register");
    Reg.RegNum = RegNum;
  }

  const MCExpr *getImm() const {
    assert(Kind == k_Imm && "not an immediate");
    return Imm;
  }

  // ----- Operand-class predicates used by the auto-generated matcher -----

  // 8-bit immediate (any expression; range checked at encoding time).
  bool isImm8() const { return Kind == k_Imm; }
  // 16-bit immediate / branch target.
  bool isImm16()    const { return Kind == k_Imm; }
  bool isI8port()   const { return Kind == k_Imm; }
  bool isBrtarget() const { return Kind == k_Imm; }

  // ----- AsmOperand emitters -----

  void addRegOperands(MCInst &Inst, unsigned N) const {
    assert(Kind == k_Reg && "not a register");
    assert(N == 1 && "wrong operand count");
    Inst.addOperand(MCOperand::createReg(Reg.RegNum));
  }

  void addExprOperand(MCInst &Inst, const MCExpr *Expr) const {
    if (!Expr)
      Inst.addOperand(MCOperand::createImm(0));
    else if (const auto *CE = dyn_cast<MCConstantExpr>(Expr))
      Inst.addOperand(MCOperand::createImm(CE->getValue()));
    else
      Inst.addOperand(MCOperand::createExpr(Expr));
  }

  void addImmOperands(MCInst &Inst, unsigned N) const {
    assert(Kind == k_Imm && "not an immediate");
    assert(N == 1 && "wrong operand count");
    addExprOperand(Inst, Imm);
  }

  void addImm8Operands(MCInst &Inst, unsigned N) const {
    addImmOperands(Inst, N);
  }
  void addImm16Operands(MCInst &Inst, unsigned N) const {
    addImmOperands(Inst, N);
  }
  void addI8portOperands(MCInst &Inst, unsigned N) const {
    addImmOperands(Inst, N);
  }
  void addBrtargetOperands(MCInst &Inst, unsigned N) const {
    addImmOperands(Inst, N);
  }

  void print(raw_ostream &O) const override {
    switch (Kind) {
    case k_Tok: O << "Token '" << Tok << "'";    break;
    case k_Reg: O << "Reg "   << Reg.RegNum;     break;
    case k_Imm: O << "Imm "   << *Imm;           break;
    }
  }

  // Factories.
  static std::unique_ptr<V6ClangOperand> CreateToken(StringRef Str, SMLoc S) {
    auto Op = std::make_unique<V6ClangOperand>(k_Tok, S, S);
    Op->Tok = Str;
    return Op;
  }
  static std::unique_ptr<V6ClangOperand> CreateReg(unsigned RegNum,
                                                SMLoc S, SMLoc E) {
    auto Op = std::make_unique<V6ClangOperand>(k_Reg, S, E);
    Op->Reg.RegNum = RegNum;
    return Op;
  }
  static std::unique_ptr<V6ClangOperand> CreateImm(const MCExpr *Val,
                                                SMLoc S, SMLoc E) {
    auto Op = std::make_unique<V6ClangOperand>(k_Imm, S, E);
    Op->Imm = Val;
    return Op;
  }
};

} // end anonymous namespace

#define GET_REGISTER_MATCHER
#define GET_MATCHER_IMPLEMENTATION
#include "V6ClangGenAsmMatcher.inc"

//===----------------------------------------------------------------------===//
// Register name resolution
//===----------------------------------------------------------------------===//

// Accept ONLY the i8080-canonical spellings. Returns NoRegister for any
// other identifier (including the long pair forms HL/DE/BC).
//
// 8-bit registers:  A B C D E H L
// 16-bit:           SP, PSW
// Pair-letters parsed as their 8-bit half; promoted to a pair register by
// validateTargetOperandClass when the matched operand class requires a pair.
MCRegister V6ClangAsmParser::matchRegisterName(StringRef Name) {
  // Normalize to upper case for the small fixed set.
  if (Name.size() == 1) {
    switch (Name[0] | 0x20) {
    case 'a': return V6Clang::A;
    case 'b': return V6Clang::B;
    case 'c': return V6Clang::C;
    case 'd': return V6Clang::D;
    case 'e': return V6Clang::E;
    case 'h': return V6Clang::H;
    case 'l': return V6Clang::L;
    default:  return MCRegister();
    }
  }
  if (Name.equals_insensitive("sp"))  return V6Clang::SP;
  if (Name.equals_insensitive("psw")) return V6Clang::PSW;
  // Long pair forms HL/DE/BC are deliberately rejected.
  return MCRegister();
}

bool V6ClangAsmParser::parseRegister(MCRegister &Reg, SMLoc &StartLoc,
                                 SMLoc &EndLoc) {
  ParseStatus Res = tryParseRegister(Reg, StartLoc, EndLoc);
  if (Res.isSuccess()) return false;
  if (Res.isFailure()) return Error(StartLoc, "invalid register name");
  return true; // NoMatch
}

ParseStatus V6ClangAsmParser::tryParseRegister(MCRegister &Reg, SMLoc &StartLoc,
                                           SMLoc &EndLoc) {
  if (getLexer().isNot(AsmToken::Identifier))
    return ParseStatus::NoMatch;

  StringRef Name = getLexer().getTok().getIdentifier();
  MCRegister R = matchRegisterName(Name);
  if (!R)
    return ParseStatus::NoMatch;

  StartLoc = getLexer().getTok().getLoc();
  EndLoc   = getLexer().getTok().getEndLoc();
  Reg = R;
  getLexer().Lex(); // consume register identifier
  return ParseStatus::Success;
}

//===----------------------------------------------------------------------===//
// Instruction / operand parsing
//===----------------------------------------------------------------------===//

bool V6ClangAsmParser::parseOperand(OperandVector &Operands) {
  // Identifiers may be:
  //   * a register name -> Reg operand
  //   * the literal "M"  -> Token operand (memory-via-HL marker)
  //   * a symbolic expression (label) -> Imm operand
  if (getLexer().is(AsmToken::Identifier)) {
    StringRef Id = getLexer().getTok().getIdentifier();
    // The literal "M" token used by MOV r,M / MOV M,r / ADD M / ANA M / ...
    if (Id.size() == 1 && (Id[0] == 'M' || Id[0] == 'm')) {
      SMLoc L = getLexer().getTok().getLoc();
      Operands.push_back(V6ClangOperand::CreateToken("M", L));
      getLexer().Lex();
      return false;
    }
    MCRegister Reg = matchRegisterName(Id);
    if (Reg) {
      SMLoc S = getLexer().getTok().getLoc();
      SMLoc E = getLexer().getTok().getEndLoc();
      Operands.push_back(V6ClangOperand::CreateReg(Reg, S, E));
      getLexer().Lex();
      return false;
    }
    // Otherwise fall through to expression parsing (symbolic immediate).
  }

  // V6CLANG lo8/hi8 byte-extraction prefix operators, matching V6ClangInstPrinter:
  //   <(expr)  -> low byte  of a (possibly link-time) 16-bit value
  //   >(expr)  -> high byte of a (possibly link-time) 16-bit value
  // For a symbol reference these emit an R_V6CLANG_LO8 / R_V6CLANG_HI8 relocation,
  // letting inline asm take one byte of an address resolved at link time.
  if (getLexer().is(AsmToken::Less) || getLexer().is(AsmToken::Greater)) {
    bool IsLo = getLexer().is(AsmToken::Less);
    SMLoc S = getLexer().getTok().getLoc();
    getLexer().Lex(); // consume '<' or '>'
    const MCExpr *Sub;
    if (getParser().parseExpression(Sub))
      return Error(S, "expected expression after lo8/hi8 operator");
    const MCExpr *Val = V6ClangMCExpr::create(
        IsLo ? V6ClangMCExpr::VK_V6CLANG_LO8 : V6ClangMCExpr::VK_V6CLANG_HI8, Sub,
        getParser().getContext());
    SMLoc E =
        SMLoc::getFromPointer(getLexer().getTok().getLoc().getPointer() - 1);
    Operands.push_back(V6ClangOperand::CreateImm(Val, S, E));
    return false;
  }

  // Numeric / expression / symbol operand.
  SMLoc S = getLexer().getTok().getLoc();
  const MCExpr *Val;
  if (getParser().parseExpression(Val))
    return Error(S, "expected expression operand");
  SMLoc E = SMLoc::getFromPointer(getLexer().getTok().getLoc().getPointer() - 1);
  Operands.push_back(V6ClangOperand::CreateImm(Val, S, E));
  return false;
}

bool V6ClangAsmParser::ParseInstruction(ParseInstructionInfo & /*Info*/,
                                    StringRef Name, SMLoc NameLoc,
                                    OperandVector &Operands) {
  // Mnemonic.
  Operands.push_back(V6ClangOperand::CreateToken(Name, NameLoc));

  // No operands?
  if (getLexer().is(AsmToken::EndOfStatement))
    return false;

  // Special case: RST takes a literal vector number 0..7 as a *token*
  // (the asm strings in V6ClangInstrInfo.td are "RST\t0".."RST\t7", so the
  // matcher expects token operands, not an immediate).
  if (Name.equals_insensitive("rst") &&
      getLexer().is(AsmToken::Integer)) {
    int64_t Val = getLexer().getTok().getIntVal();
    SMLoc L = getLexer().getTok().getLoc();
    if (Val < 0 || Val > 7) {
      getParser().eatToEndOfStatement();
      return Error(L, "RST vector must be 0..7");
    }
    static const char *const Digits[] = {"0","1","2","3","4","5","6","7"};
    Operands.push_back(V6ClangOperand::CreateToken(Digits[Val], L));
    getLexer().Lex();
    if (getLexer().isNot(AsmToken::EndOfStatement)) {
      SMLoc EL = getLexer().getTok().getLoc();
      getParser().eatToEndOfStatement();
      return Error(EL, "unexpected token in operand list");
    }
    getLexer().Lex();
    return false;
  }

  // First operand.
  if (parseOperand(Operands))
    return true;

  // Comma-separated subsequent operands.
  while (getLexer().is(AsmToken::Comma)) {
    getLexer().Lex(); // consume ','
    if (parseOperand(Operands))
      return true;
  }

  if (getLexer().isNot(AsmToken::EndOfStatement)) {
    SMLoc Loc = getLexer().getTok().getLoc();
    getParser().eatToEndOfStatement();
    return Error(Loc, "unexpected token in operand list");
  }
  getLexer().Lex(); // consume EOL
  return false;
}

//===----------------------------------------------------------------------===//
// Operand-class validation (handles pair-letter -> pair promotion and PSW)
//===----------------------------------------------------------------------===//

unsigned V6ClangAsmParser::validateTargetOperandClass(MCParsedAsmOperand &AsmOp,
                                                   unsigned Kind) {
  V6ClangOperand &Op = static_cast<V6ClangOperand &>(AsmOp);
  if (!Op.isReg())
    return Match_InvalidOperand;
  unsigned R = Op.getReg();

  auto promotePair = [](unsigned Reg) -> unsigned {
    switch (Reg) {
    case V6Clang::B: return V6Clang::BC;
    case V6Clang::D: return V6Clang::DE;
    case V6Clang::H: return V6Clang::HL;
    default:     return 0;
    }
  };

  switch (Kind) {
  default:
    return Match_InvalidOperand;

  // Any 16-bit pair operand (DAD, INX, DCX, LXI):
  // accept B/D/H (promoted), SP (already in GR16All — default check passed),
  // and PSW (not in GR16All — we accept it here).
  case MCK_GR16All:
    if (R == V6Clang::PSW || R == V6Clang::SP)
      return Match_Success;
    if (unsigned P = promotePair(R)) {
      Op.setReg(P);
      return Match_Success;
    }
    return Match_InvalidOperand;

  // PUSH / POP operand: BC, DE, HL, PSW (NOT SP — opcode 0xF1/0xF5 means PSW).
  case MCK_GR16Stack:
    if (R == V6Clang::PSW)
      return Match_Success;
    if (unsigned P = promotePair(R)) {
      Op.setReg(P);
      return Match_Success;
    }
    return Match_InvalidOperand;

  // GR16 register class (HL/DE/BC, no SP / PSW).
  case MCK_GR16:
    if (unsigned P = promotePair(R)) {
      Op.setReg(P);
      return Match_Success;
    }
    return Match_InvalidOperand;

  // GR16Idx (BC/DE only — for LDAX/STAX).
  case MCK_GR16Idx:
    if (R == V6Clang::B || R == V6Clang::D) {
      Op.setReg(promotePair(R));
      return Match_Success;
    }
    return Match_InvalidOperand;

  // GR16Ptr (HL only — used internally; rare in hand-written asm).
  case MCK_GR16Ptr:
    if (R == V6Clang::H) {
      Op.setReg(V6Clang::HL);
      return Match_Success;
    }
    return Match_InvalidOperand;

  // GR16SP (SP only).
  case MCK_GR16SP:
    if (R == V6Clang::SP)
      return Match_Success;
    return Match_InvalidOperand;
  }
}

//===----------------------------------------------------------------------===//
// MatchAndEmitInstruction
//===----------------------------------------------------------------------===//

bool V6ClangAsmParser::MatchAndEmitInstruction(SMLoc IDLoc, unsigned &Opcode,
                                           OperandVector &Operands,
                                           MCStreamer &Out,
                                           uint64_t &ErrorInfo,
                                           bool MatchingInlineAsm) {
  MCInst Inst;
  unsigned MatchResult =
      MatchInstructionImpl(Operands, Inst, ErrorInfo, MatchingInlineAsm);

  switch (MatchResult) {
  case Match_Success:
    Inst.setLoc(IDLoc);
    Out.emitInstruction(Inst, STI);
    Opcode = Inst.getOpcode();
    return false;
  case Match_MnemonicFail:
    return Error(IDLoc, "invalid instruction mnemonic");
  case Match_InvalidOperand: {
    SMLoc ErrorLoc = IDLoc;
    if (ErrorInfo != ~0ULL) {
      if (ErrorInfo >= Operands.size())
        return Error(IDLoc, "too few operands for instruction");
      ErrorLoc = static_cast<V6ClangOperand &>(*Operands[ErrorInfo]).getStartLoc();
      if (ErrorLoc == SMLoc())
        ErrorLoc = IDLoc;
    }
    return Error(ErrorLoc, "invalid operand for instruction");
  }
  default:
    return true;
  }
}

//===----------------------------------------------------------------------===//
// Target registration
//===----------------------------------------------------------------------===//

extern "C" LLVM_EXTERNAL_VISIBILITY void LLVMInitializeV6ClangAsmParser() {
  RegisterMCAsmParser<V6ClangAsmParser> X(getTheV6ClangTarget());
}
