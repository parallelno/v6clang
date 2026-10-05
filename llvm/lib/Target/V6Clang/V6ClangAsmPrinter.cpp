//===-- V6ClangAsmPrinter.cpp - V6CLANG LLVM assembly writer ----------------------===//
//
// Part of the V6CLANG backend for LLVM.
//
// Converts MachineFunction/MachineInstr representation into 8080 assembly
// text compatible with v6asm.
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "V6ClangMCInstLower.h"
#include "V6ClangSubtarget.h"
#include "V6ClangTargetMachine.h"
#include "V6ClangInstrInfo.h"
#include "MCTargetDesc/V6ClangInstPrinter.h"
#include "TargetInfo/V6ClangTargetInfo.h"

#include "llvm/CodeGen/AsmPrinter.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DebugInfoMetadata.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/Module.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCStreamer.h"
#include "llvm/MC/MCSymbol.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Target/TargetLoweringObjectFile.h"

#define DEBUG_TYPE "v6clang-asm-printer"

namespace llvm {

class V6ClangAsmPrinter : public AsmPrinter {
public:
  V6ClangAsmPrinter(TargetMachine &TM, std::unique_ptr<MCStreamer> Streamer)
      : AsmPrinter(TM, std::move(Streamer)) {}

  StringRef getPassName() const override { return "V6CLANG Assembly Printer"; }

  bool runOnMachineFunction(MachineFunction &MF) override;

  void emitFunctionBodyStart() override;
  void emitInstruction(const MachineInstr *MI) override;

  bool PrintAsmOperand(const MachineInstr *MI, unsigned OpNum,
                       const char *ExtraCode, raw_ostream &O) override;
};

bool V6ClangAsmPrinter::runOnMachineFunction(MachineFunction &MF) {
  // Suppress auto-included v6clang_arith.h runtime helpers from human-readable
  // asm output unless explicitly requested via -mv6clang-print-rt-helpers.
  // Only applies to text (`-S`) emission — when emitting an object file
  // (`-filetype=obj`) every helper must still be encoded so the linker
  // can resolve calls to `__mulqi3` etc.
  //
  // Functions are tagged via `__attribute__((v6clang_rt_helper))` (see
  // clang/include/clang/Basic/Attr.td), which lowers to the LLVM string
  // function attribute "v6clang-rt-helper". Unlike __attribute__((annotate))
  // this does NOT take the function's address and does NOT block IPO.
  if (!getV6ClangPrintRTHelpersEnabled() && OutStreamer->hasRawTextSupport() &&
      MF.getFunction().hasFnAttribute("v6clang-rt-helper"))
    return false;
  return AsmPrinter::runOnMachineFunction(MF);
}

void V6ClangAsmPrinter::emitFunctionBodyStart() {
  if (!getV6ClangAnnotatePseudosEnabled())
    return;

  const Function &F = MF->getFunction();
  const TargetRegisterInfo *TRI = MF->getSubtarget().getRegisterInfo();

  // Format a constant Value as a short human-readable string (e.g. "127",
  // "0x8000", "null").  Used for the [folded: ...] annotation.
  auto ConstStr = [](const Value *V) -> std::string {
    if (!V || isa<UndefValue>(V))
      return "undef";
    if (isa<ConstantPointerNull>(V))
      return "null";
    if (auto *CI = dyn_cast<ConstantInt>(V)) {
      int64_t Val = CI->getSExtValue();
      if (Val < -255 || Val > 255)
        return "0x" + utohexstr((uint64_t)(uint16_t)Val);
      return std::to_string(Val);
    }
    // inttoptr constant expression — extract the numeric address.
    if (auto *CE = dyn_cast<ConstantExpr>(V))
      if (CE->getOpcode() == Instruction::IntToPtr)
        if (auto *CI = dyn_cast<ConstantInt>(CE->getOperand(0)))
          return "0x" + utohexstr(CI->getZExtValue());
    // Fallback: print without type.
    std::string S;
    raw_string_ostream OS(S);
    V->printAsOperand(OS, /*PrintType=*/false);
    return S;
  };

  // Collect parameter debug info from llvm.dbg.value intrinsics (requires -g).
  // Maps 1-based original parameter index -> {original_name, optional_folded_val}.
  struct DbgParam {
    std::string Name;
    const Argument *SurvivingArg = nullptr; // non-null iff the arg survived CP
    bool Folded = false;
    std::string FoldedVal;
  };
  std::map<unsigned, DbgParam> DbgParams;
  // Maps each surviving Argument to its original source name.
  DenseMap<const Argument *, std::string> ArgOrigName;

  for (const BasicBlock &BB : F) {
    for (const Instruction &I : BB) {
      auto *DVI = dyn_cast<DbgValueInst>(&I);
      if (!DVI)
        continue;
      DILocalVariable *DLV = DVI->getVariable();
      if (!DLV || DLV->getArg() == 0)
        continue;
      StringRef ParamName = DLV->getName();
      if (ParamName.empty())
        continue;
      unsigned Idx = DLV->getArg(); // 1-based DWARF arg index
      DbgParam &P = DbgParams[Idx];
      P.Name = ParamName.str();
      Value *Val = DVI->getValue(0);
      if (auto *A = dyn_cast_or_null<Argument>(Val)) {
        P.SurvivingArg = A;
        P.Folded = false;
        ArgOrigName[A] = P.Name;
      } else if (Val && isa<Constant>(Val) && !isa<UndefValue>(Val) &&
                 !P.Folded) {
        // Only record the first constant binding; that's the folded value.
        P.Folded = true;
        P.FoldedVal = ConstStr(Val);
      }
    }
  }

  // Map LLVM IR type to C-like type string.
  auto TypeStr = [](Type *Ty) -> std::string {
    if (Ty->isVoidTy()) return "void";
    if (Ty->isIntegerTy(1)) return "bool";
    if (Ty->isIntegerTy(8)) return "char";
    if (Ty->isIntegerTy(16)) return "int";
    if (Ty->isPointerTy()) return "void*";
    return "?";
  };

  // Build C-like declaration string.
  std::string Decl = TypeStr(F.getReturnType());
  Decl += " ";
  Decl += F.getName().str();
  Decl += "(";

  // V6CLANG calling convention: free-list allocator (mirrors
  // V6ClangArgAllocator in V6ClangISelLowering.cpp). i8 args take from
  // {A,B,C,D,E,L,H}; i16 args take from {HL,DE,BC}; taking an i16 pair
  // removes its two halves from the i8 list and vice versa.
  SmallVector<MCPhysReg, 7> FreeI8 = {V6Clang::A, V6Clang::B, V6Clang::C,
                                      V6Clang::D, V6Clang::E, V6Clang::L, V6Clang::H};
  SmallVector<MCPhysReg, 3> FreeI16 = {V6Clang::HL, V6Clang::DE, V6Clang::BC};
  auto dropReg = [](SmallVectorImpl<MCPhysReg> &L, MCPhysReg R) {
    auto It = std::find(L.begin(), L.end(), R);
    if (It != L.end())
      L.erase(It);
  };
  auto pairOf = [](MCPhysReg H) -> MCPhysReg {
    switch (H) {
    case V6Clang::H: case V6Clang::L: return V6Clang::HL;
    case V6Clang::D: case V6Clang::E: return V6Clang::DE;
    case V6Clang::B: case V6Clang::C: return V6Clang::BC;
    default: return MCRegister::NoRegister;
    }
  };
  auto halves = [](MCPhysReg P) -> std::pair<MCPhysReg, MCPhysReg> {
    switch (P) {
    case V6Clang::HL: return {V6Clang::H, V6Clang::L};
    case V6Clang::DE: return {V6Clang::D, V6Clang::E};
    case V6Clang::BC: return {V6Clang::B, V6Clang::C};
    default: return {MCRegister::NoRegister, MCRegister::NoRegister};
    }
  };
  auto takeI8 = [&]() -> MCPhysReg {
    if (FreeI8.empty()) return MCRegister::NoRegister;
    MCPhysReg R = FreeI8.front();
    FreeI8.erase(FreeI8.begin());
    if (MCPhysReg P = pairOf(R)) dropReg(FreeI16, P);
    return R;
  };
  auto takeI16 = [&]() -> MCPhysReg {
    if (FreeI16.empty()) return MCRegister::NoRegister;
    MCPhysReg P = FreeI16.front();
    FreeI16.erase(FreeI16.begin());
    auto Hs = halves(P);
    dropReg(FreeI8, Hs.first);
    dropReg(FreeI8, Hs.second);
    return P;
  };

  struct ParamInfo {
    std::string Name;
    std::string Reg;
  };
  SmallVector<ParamInfo, 4> Params;

  for (unsigned i = 0; i < F.arg_size(); ++i) {
    const Argument *Arg = F.getArg(i);
    Type *Ty = Arg->getType();
    std::string TStr = TypeStr(Ty);
    // Prefer original source name from debug info, then IR name (preserved by
    // -fno-discard-value-names), then fallback "argN".
    std::string Name;
    auto DIt = ArgOrigName.find(Arg);
    if (DIt != ArgOrigName.end())
      Name = DIt->second;
    else if (!Arg->getName().empty())
      Name = Arg->getName().str();
    else
      Name = "arg" + std::to_string(i);

    if (i > 0)
      Decl += ", ";
    Decl += TStr + " " + Name;

    bool Is8Bit = Ty->isIntegerTy() && Ty->getIntegerBitWidth() <= 8;
    MCPhysReg Reg = Is8Bit ? takeI8() : takeI16();
    std::string RegStr = Reg ? std::string(TRI->getName(Reg)) : "stack";
    Params.push_back({Name, RegStr});
  }

  if (F.arg_size() == 0)
    Decl += "void";
  Decl += ")";

  OutStreamer->emitRawComment("=== " + Decl + " ===");
  for (const auto &P : Params) {
    OutStreamer->emitRawComment("  " + P.Name + " = " + P.Reg);
  }

  // Emit folded-parameter summary when debug info is available.
  SmallVector<std::string, 4> FoldedParts;
  StringSet<> EmittedNames;
  for (auto &KV : DbgParams)
    if (KV.second.Folded && EmittedNames.insert(KV.second.Name).second)
      FoldedParts.push_back(KV.second.Name + "=" + KV.second.FoldedVal);
  if (!FoldedParts.empty()) {
    std::string S = "  [folded:";
    for (size_t Idx = 0; Idx < FoldedParts.size(); ++Idx) {
      S += " " + FoldedParts[Idx];
      if (Idx + 1 < FoldedParts.size())
        S += ",";
    }
    S += "]";
    OutStreamer->emitRawComment(S);
  }
}

void V6ClangAsmPrinter::emitInstruction(const MachineInstr *MI) {
  if (MI->getOpcode() == V6Clang::V6CLANG_PSEUDO_COMMENT) {
    unsigned OrigOpc = MI->getOperand(0).getImm();
    const TargetInstrInfo *TII = MF->getSubtarget().getInstrInfo();
    OutStreamer->emitRawComment(Twine("--- ") + TII->getName(OrigOpc) + " ---");
    return;
  }

  V6ClangMCInstLower MCInstLowering(OutContext, *this);

  MCInst TmpInst;
  MCInstLowering.lowerInstruction(*MI, TmpInst);
  EmitToStreamer(*OutStreamer, TmpInst);
}

bool V6ClangAsmPrinter::PrintAsmOperand(const MachineInstr *MI, unsigned OpNum,
                                     const char *ExtraCode, raw_ostream &O) {
  if (ExtraCode && ExtraCode[0])
    return true; // Unknown modifier.

  const MachineOperand &MO = MI->getOperand(OpNum);
  switch (MO.getType()) {
  case MachineOperand::MO_Register: {
    // V6ClangAsmParser rejects long-form pair names HL/DE/BC; print them as
    // their 8080-canonical first-half (H/D/B) instead so inline-asm output
    // round-trips through the integrated assembler.
    Register Reg = MO.getReg();
    unsigned AltIdx = V6Clang::NoRegAltName;
    if (V6Clang::GR16AllRegClass.contains(Reg))
      AltIdx = V6Clang::Pair8080;
    O << V6ClangInstPrinter::getRegisterName(Reg, AltIdx);
    return false;
  }
  case MachineOperand::MO_Immediate:
    O << MO.getImm();
    return false;
  case MachineOperand::MO_GlobalAddress:
    // Symbol address used with constraint "i" (e.g. LXI B, %[sym]).
    PrintSymbolOperand(MO, O);
    return false;
  case MachineOperand::MO_ExternalSymbol:
    O << MO.getSymbolName();
    return false;
  case MachineOperand::MO_BlockAddress:
    GetBlockAddressSymbol(MO.getBlockAddress())->print(O, MAI);
    return false;
  default:
    return true;
  }
}

} // namespace llvm

extern "C" LLVM_EXTERNAL_VISIBILITY void LLVMInitializeV6ClangAsmPrinter() {
  llvm::RegisterAsmPrinter<llvm::V6ClangAsmPrinter> X(llvm::getTheV6ClangTarget());
}
