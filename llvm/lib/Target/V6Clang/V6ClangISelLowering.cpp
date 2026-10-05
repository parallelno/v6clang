//===-- V6ClangISelLowering.cpp - V6CLANG DAG Lowering Implementation -------------===//
//
// Part of the V6CLANG backend for LLVM.
//
// M5: Frame Lowering & Calling Convention.
//
//===----------------------------------------------------------------------===//

#include "V6ClangISelLowering.h"
#include "V6ClangSubtarget.h"
#include "V6ClangTargetMachine.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "llvm/CodeGen/CallingConvLower.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/SelectionDAG.h"
#include "llvm/CodeGen/TargetLoweringObjectFileImpl.h"
#include "llvm/IR/Function.h"

using namespace llvm;

#define DEBUG_TYPE "v6clang-lower"

//===----------------------------------------------------------------------===//
// V6ClangTargetLowering constructor — type legalization, operation actions
//===----------------------------------------------------------------------===//

V6ClangTargetLowering::V6ClangTargetLowering(const V6ClangTargetMachine &TM,
                                       const V6ClangSubtarget &STI)
    : TargetLowering(TM) {
  // Register classes.
  addRegisterClass(MVT::i8, &V6CLANG::GR8RegClass);
  addRegisterClass(MVT::i16, &V6CLANG::GR16RegClass);

  computeRegisterProperties(STI.getRegisterInfo());

  setStackPointerRegisterToSaveRestore(V6CLANG::SP);

  // Boolean values from setcc are exactly 0 or 1 in an i8 register.
  setBooleanContents(ZeroOrOneBooleanContent);
  setBooleanVectorContents(ZeroOrOneBooleanContent);

  // --- Type legalization ---

  // i8: Legal via TableGen patterns.

  // i16: Legal for loads/stores/copies, Expand or Custom for arithmetic.
  // Full i16 ALU is deferred to M7. For M5 we need i16 for pointers and
  // calling convention (arguments, return values).

  // i32: Expand to pairs of i16.
  // i64: not supported at all.

  // --- Operation actions for i8 ---

  // O70: i8 multiply has its own libcall (__mulqi3 — 8 iterations vs.
  // __mulhi3's 16). Divide stays Promote-to-i16 to share the i16 routine.
  setOperationAction(ISD::MUL,   MVT::i8, LibCall);
  setOperationAction(ISD::SDIV,  MVT::i8, Promote);
  setOperationAction(ISD::UDIV,  MVT::i8, Promote);
  setOperationAction(ISD::SREM,  MVT::i8, Promote);
  setOperationAction(ISD::UREM,  MVT::i8, Promote);
  setOperationAction(ISD::SDIVREM, MVT::i8, Expand);
  setOperationAction(ISD::UDIVREM, MVT::i8, Expand);
  setOperationAction(ISD::MULHS, MVT::i8, Expand);
  setOperationAction(ISD::MULHU, MVT::i8, Expand);
  setOperationAction(ISD::SMUL_LOHI, MVT::i8, Expand);
  setOperationAction(ISD::UMUL_LOHI, MVT::i8, Expand);

  // Shifts: Custom lowering (expand to rotates/loops).
  setOperationAction(ISD::SHL,  MVT::i8, Custom);
  setOperationAction(ISD::SRL,  MVT::i8, Custom);
  setOperationAction(ISD::SRA,  MVT::i8, Custom);

  // Rotates: Custom — chain of V6ClangISD::ROTL8/ROTR8 (RLC/RRC) for constant
  // amounts; promote to i16 fallback for variable amount (rare).
  setOperationAction(ISD::ROTL, MVT::i8, Custom);
  setOperationAction(ISD::ROTR, MVT::i8, Custom);

  // No hardware support for byte swap, ctlz, cttz, ctpop.
  setOperationAction(ISD::BSWAP,    MVT::i8, Expand);
  setOperationAction(ISD::CTLZ,     MVT::i8, Expand);
  setOperationAction(ISD::CTTZ,     MVT::i8, Expand);
  setOperationAction(ISD::CTPOP,    MVT::i8, Expand);

  // Compare-and-branch: Custom (fuse icmp + br into CMP + Jcc).
  setOperationAction(ISD::BR_CC,     MVT::i8, Custom);
  setOperationAction(ISD::SELECT_CC, MVT::i8, Custom);

  // BRCOND with a non-setcc value condition (e.g. `if (x & 1)`) has no
  // selection pattern. Expand it so LegalizeDAG rewrites it into a
  // `BR_CC <cond> SETNE 0`, which the custom BR_CC lowering handles.
  setOperationAction(ISD::BRCOND,    MVT::Other, Expand);

  // No jump-table or indirect-branch support: the i8080 has PCHL but the
  // backend provides no br_jt / brind selection pattern. Marking both
  // BR_JT and BRIND non-legal makes TargetLowering::areJTsAllowed() return
  // false, so switch statements are lowered to comparison-and-branch
  // chains instead of jump tables (avoids "Cannot select: br_jt").
  setOperationAction(ISD::BR_JT, MVT::Other, Expand);
  setOperationAction(ISD::BRIND, MVT::Other, Expand);

  // O75 Phase B: Custom-lower i8 ADD/SUB/AND/OR/XOR to flag-producing
  // V6ClangISD::*F nodes so a downstream BR_CC/SELECT_CC against zero can
  // consume the flags directly (no redundant CMP/CPI).
  setOperationAction(ISD::ADD, MVT::i8, Custom);
  setOperationAction(ISD::SUB, MVT::i8, Custom);
  setOperationAction(ISD::AND, MVT::i8, Custom);
  setOperationAction(ISD::OR,  MVT::i8, Custom);
  setOperationAction(ISD::XOR, MVT::i8, Custom);

  // SELECT: expand to SELECT_CC.
  setOperationAction(ISD::SELECT, MVT::i8, Expand);

  // Extending loads / truncating stores.
  setOperationAction(ISD::SIGN_EXTEND_INREG, MVT::i1, Expand);

  // Extending loads: expand to load + extend (no native extending load).
  setLoadExtAction(ISD::SEXTLOAD, MVT::i16, MVT::i8, Expand);
  setLoadExtAction(ISD::ZEXTLOAD, MVT::i16, MVT::i8, Expand);
  setLoadExtAction(ISD::EXTLOAD,  MVT::i16, MVT::i8, Expand);

  // Truncating stores: expand to (trunc + store) so ISel sees a clean
  // i8 store. Without this, at -O0 the matcher hits an unselectable
  // `store<trunc to i8> i16` node (no DAGCombiner pass to fold the
  // truncate into the value being stored).
  setTruncStoreAction(MVT::i16, MVT::i8, Expand);

  // GlobalAddress, ExternalSymbol: Custom (wrap for LXI).
  setOperationAction(ISD::GlobalAddress,  MVT::i16, Custom);
  setOperationAction(ISD::ExternalSymbol, MVT::i16, Custom);

  // Varargs: not supported.
  setOperationAction(ISD::VASTART, MVT::Other, Expand);
  setOperationAction(ISD::VAARG,   MVT::Other, Expand);
  setOperationAction(ISD::VACOPY,  MVT::Other, Expand);
  setOperationAction(ISD::VAEND,   MVT::Other, Expand);

  // Dynamic stack allocation: not yet supported.
  setOperationAction(ISD::DYNAMIC_STACKALLOC, MVT::i16, Expand);

  // Setcc: expand to select_cc-based sequences.
  setOperationAction(ISD::SETCC, MVT::i8, Expand);

  // Zero/sign/any extend i8→i16: Custom lowering to BUILD_PAIR.
  setOperationAction(ISD::SIGN_EXTEND, MVT::i16, Custom);
  setOperationAction(ISD::ZERO_EXTEND, MVT::i16, Custom);
  setOperationAction(ISD::ANY_EXTEND,  MVT::i16, Custom);
  setOperationAction(ISD::TRUNCATE,    MVT::i8,  Legal);

  // --- Operation actions for i16 ---
  // M7: i16 ALU ops matched to pseudo-instructions via TableGen patterns.

  // ADD, SUB, AND, OR, XOR: Legal — matched by V6CLANG_ADD16, etc. pseudos.
  setOperationAction(ISD::ADD,   MVT::i16, Legal);
  setOperationAction(ISD::SUB,   MVT::i16, Legal);
  setOperationAction(ISD::AND,   MVT::i16, Legal);
  setOperationAction(ISD::OR,    MVT::i16, Legal);
  setOperationAction(ISD::XOR,   MVT::i16, Legal);

  // Multiply, divide: no hardware support → Expand (LibCall).
  setOperationAction(ISD::MUL,   MVT::i16, Expand);
  setOperationAction(ISD::SDIV,  MVT::i16, Expand);
  setOperationAction(ISD::UDIV,  MVT::i16, Expand);
  setOperationAction(ISD::SREM,  MVT::i16, Expand);
  setOperationAction(ISD::UREM,  MVT::i16, Expand);
  setOperationAction(ISD::SDIVREM, MVT::i16, LibCall);
  setOperationAction(ISD::UDIVREM, MVT::i16, LibCall);

  // Shifts: Custom (unrolled for constant, libcall for variable).
  setOperationAction(ISD::SHL,   MVT::i16, Custom);
  setOperationAction(ISD::SRL,   MVT::i16, Custom);
  setOperationAction(ISD::SRA,   MVT::i16, Custom);
  // O68 Phase 2: i16 rotate-left by 1 lowers to V6ClangISD::ROTL16_1
  // (DAD H + ACI 0 carry-fold). All other amounts and ROTR fall back
  // to the default Expand path via SDValue() return in LowerROTL.
  setOperationAction(ISD::ROTL,  MVT::i16, Custom);
  setOperationAction(ISD::ROTR,  MVT::i16, Expand);

  // Compare-and-branch, select: Custom (fuse into 8-bit compare sequences).
  setOperationAction(ISD::BR_CC,     MVT::i16, Custom);
  setOperationAction(ISD::SELECT_CC, MVT::i16, Custom);
  setOperationAction(ISD::SELECT,    MVT::i16, Expand);
  setOperationAction(ISD::SETCC,     MVT::i16, Expand);

  setOperationAction(ISD::CTLZ,  MVT::i16, Expand);
  setOperationAction(ISD::CTTZ,  MVT::i16, Expand);
  setOperationAction(ISD::CTPOP, MVT::i16, Expand);
  setOperationAction(ISD::BSWAP, MVT::i16, Expand);

  setOperationAction(ISD::MULHS,     MVT::i16, Expand);
  setOperationAction(ISD::MULHU,     MVT::i16, Expand);
  setOperationAction(ISD::SMUL_LOHI, MVT::i16, Expand);
  setOperationAction(ISD::UMUL_LOHI, MVT::i16, Expand);

  // --- Runtime library call names ---
  // O70: implementations live in compiler-rt/lib/builtins/v6clang/include/v6clang_arith.h
  // (header-only, auto-included by the V6CLANG driver). Each routine compiles
  // to a per-TU `static` definition so ISel-emitted CALLs resolve via the
  // assembler's same-TU symbol matching, and IPRA recovers the actual
  // clobber set per call site.
  setLibcallName(RTLIB::MUL_I8,   "__mulqi3");
  setLibcallName(RTLIB::MUL_I16,  "__mulhi3");
  setLibcallName(RTLIB::SDIV_I16, "__divhi3");
  setLibcallName(RTLIB::UDIV_I16, "__udivhi3");
  setLibcallName(RTLIB::SREM_I16, "__modhi3");
  setLibcallName(RTLIB::UREM_I16, "__umodhi3");
  // O70 Step 3.5: fused divmod libcalls. LLVM's UDIVREM/SDIVREM ISD nodes
  // collapse a `q=a/b; r=a%b;` pair into a single libcall when both ops
  // share operands — saves one full CALL when the user wants both.
  setLibcallName(RTLIB::UDIVREM_I16, "__udivmodhi4");
  setLibcallName(RTLIB::SDIVREM_I16, "__divmodhi4");
  setLibcallName(RTLIB::SHL_I16,  "__ashlhi3");
  setLibcallName(RTLIB::SRL_I16,  "__lshrhi3");
  setLibcallName(RTLIB::SRA_I16,  "__ashrhi3");

  // Minimum function alignment (8080 has no alignment requirements).
  setMinFunctionAlignment(Align(1));

  // Enable DAG combine for i16 ADD → DAD optimization.
  setTargetDAGCombine(ISD::ADD);

  // Re-canonicalize i16 MUL so the HL-sourced operand is always LHS,
  // preventing a HL↔DE register swap before the __mulhi3 libcall.
  setTargetDAGCombine(ISD::MUL);
}

//===----------------------------------------------------------------------===//
// getSetCCResultType — booleans are i8 on V6CLANG (not the default i16 pointer)
//===----------------------------------------------------------------------===//

EVT V6ClangTargetLowering::getSetCCResultType(const DataLayout &DL,
                                           LLVMContext &C, EVT VT) const {
  return MVT::i8;
}

//===----------------------------------------------------------------------===//
// getTargetNodeName
//===----------------------------------------------------------------------===//

const char *V6ClangTargetLowering::getTargetNodeName(unsigned Opcode) const {
  switch (static_cast<V6ClangISD::NodeType>(Opcode)) {
  case V6ClangISD::FIRST_NUMBER: break;
  case V6ClangISD::RET:       return "V6ClangISD::RET";
  case V6ClangISD::CALL:      return "V6ClangISD::CALL";
  case V6ClangISD::CMP:       return "V6ClangISD::CMP";
  case V6ClangISD::CMP_ZERO:  return "V6ClangISD::CMP_ZERO";
  case V6ClangISD::CMP_SIGN:  return "V6ClangISD::CMP_SIGN";
  case V6ClangISD::BRCOND:    return "V6ClangISD::BRCOND";
  case V6ClangISD::SELECT_CC: return "V6ClangISD::SELECT_CC";
  case V6ClangISD::Wrapper:   return "V6ClangISD::Wrapper";
  case V6ClangISD::BR_CC16:   return "V6ClangISD::BR_CC16";
  case V6ClangISD::SEXT:      return "V6ClangISD::SEXT";
  case V6ClangISD::NEG8:      return "V6ClangISD::NEG8";
  case V6ClangISD::SHL16_DAD:   return "V6ClangISD::SHL16_DAD";
  case V6ClangISD::SHL16_BYTE:  return "V6ClangISD::SHL16_BYTE";
  case V6ClangISD::SHL16_RAM_HI:return "V6ClangISD::SHL16_RAM_HI";
  case V6ClangISD::SRL16_RAR:   return "V6ClangISD::SRL16_RAR";
  case V6ClangISD::SRL16_24BIT: return "V6ClangISD::SRL16_24BIT";
  case V6ClangISD::SRL16_BYTE:  return "V6ClangISD::SRL16_BYTE";
  case V6ClangISD::SRL16_RAM_LO:return "V6ClangISD::SRL16_RAM_LO";
  case V6ClangISD::SRA16_RAR:   return "V6ClangISD::SRA16_RAR";
  case V6ClangISD::SRA16_24BIT: return "V6ClangISD::SRA16_24BIT";
  case V6ClangISD::SRA16_BYTE:  return "V6ClangISD::SRA16_BYTE";
  case V6ClangISD::SRA16_RAM_LO:return "V6ClangISD::SRA16_RAM_LO";
  case V6ClangISD::DAD:       return "V6ClangISD::DAD";
  case V6ClangISD::INX16:    return "V6ClangISD::INX16";
  case V6ClangISD::DCX16:    return "V6ClangISD::DCX16";
  case V6ClangISD::ROTL8:    return "V6ClangISD::ROTL8";
  case V6ClangISD::ROTR8:    return "V6ClangISD::ROTR8";
  case V6ClangISD::ROTL16_1: return "V6ClangISD::ROTL16_1";
  case V6ClangISD::ADDF:     return "V6ClangISD::ADDF";
  case V6ClangISD::SUBF:     return "V6ClangISD::SUBF";
  case V6ClangISD::ANDF:     return "V6ClangISD::ANDF";
  case V6ClangISD::ORF:      return "V6ClangISD::ORF";
  case V6ClangISD::XORF:     return "V6ClangISD::XORF";
  case V6ClangISD::ADDF_IMM: return "V6ClangISD::ADDF_IMM";
  case V6ClangISD::SUBF_IMM: return "V6ClangISD::SUBF_IMM";
  case V6ClangISD::ANDF_IMM: return "V6ClangISD::ANDF_IMM";
  case V6ClangISD::ORF_IMM:  return "V6ClangISD::ORF_IMM";
  case V6ClangISD::XORF_IMM: return "V6ClangISD::XORF_IMM";
  case V6ClangISD::INCF:     return "V6ClangISD::INCF";
  case V6ClangISD::DECF:     return "V6ClangISD::DECF";
  }
  return nullptr;
}

//===----------------------------------------------------------------------===//
// PerformDAGCombine — target-specific DAG optimizations
//===----------------------------------------------------------------------===//

static bool isCopyFromPhysReg(SDValue V, unsigned PhysReg) {
  if (V.getOpcode() != ISD::CopyFromReg)
    return false;
  auto *Reg = dyn_cast<RegisterSDNode>(V.getOperand(1));
  return Reg && Reg->getReg() == PhysReg;
}

/// Like isCopyFromPhysReg but also recognises virtual register live-ins.
/// LowerFormalArguments copies incoming physical registers into virtual regs
/// (addLiveIn), so at DAG-combine time the arg SDValue is CopyFromReg of a
/// virtual register, not the physical one.  This helper handles both.
static bool isCopyFromArgReg(SDValue V, unsigned PhysReg,
                              const SelectionDAG &DAG) {
  if (V.getOpcode() != ISD::CopyFromReg)
    return false;
  auto *RN = dyn_cast<RegisterSDNode>(V.getOperand(1));
  if (!RN)
    return false;
  Register Reg = RN->getReg();
  if (!Reg.isVirtual())
    return Reg == PhysReg;
  return DAG.getMachineFunction().getRegInfo().getLiveInPhysReg(Reg) == PhysReg;
}

SDValue V6ClangTargetLowering::PerformDAGCombine(SDNode *N,
                                              DAGCombinerInfo &DCI) const {
  SelectionDAG &DAG = DCI.DAG;

  switch (N->getOpcode()) {
  default:
    break;

  case ISD::ADD:
    if (N->getValueType(0) == MVT::i16) {
      // O41: Check for small constant ±1..±3 → INX16/DCX16 pseudo.
      // This runs BEFORE the DAD conversion so that pointer increments
      // also benefit (INX needs no constant register pair).
      for (unsigned OpIdx = 0; OpIdx < 2; ++OpIdx) {
        if (auto *C = dyn_cast<ConstantSDNode>(N->getOperand(OpIdx))) {
          int64_t Val = C->getSExtValue();
          SDLoc DL(N);
          if (Val >= 1 && Val <= 3)
            return DAG.getNode(V6ClangISD::INX16, DL, MVT::i16,
                               N->getOperand(1 - OpIdx),
                               DAG.getTargetConstant(Val, DL, MVT::i8));
          if (Val >= -3 && Val <= -1)
            return DAG.getNode(V6ClangISD::DCX16, DL, MVT::i16,
                               N->getOperand(1 - OpIdx),
                               DAG.getTargetConstant(-Val, DL, MVT::i8));
        }
      }

      // Convert i16 add to V6ClangISD::DAD when the result is used as a pointer
      // for a memory operation. DAD uses the HL register pair (12cc, does not
      // clobber A), which is exactly what loads/stores need for addressing.
      bool UsedAsPointer = false;
      for (SDNode::use_iterator UI = N->use_begin(), UE = N->use_end();
           UI != UE; ++UI) {
        unsigned UseOpc = UI->getOpcode();
        // Load: operands are (chain, ptr). We're the pointer if operand 1.
        if (UseOpc == ISD::LOAD && UI.getOperandNo() == 1)
          UsedAsPointer = true;
        // Store: operands are (chain, val, ptr). We're the pointer if operand 2.
        if (UseOpc == ISD::STORE && UI.getOperandNo() == 2)
          UsedAsPointer = true;
      }
      if (UsedAsPointer) {
        SDLoc DL(N);
        SDValue LHS = N->getOperand(0);
        SDValue RHS = N->getOperand(1);

        // Canonicalise: put the HL-sourced operand (either a phys-reg copy or
        // a virtual live-in from HL, e.g. a function argument) on the LHS so
        // that RA can allocate it to HL without an extra copy.  Now that
        // V6Clangdad lacks SDNPCommutative the combiner will not undo this order.
        bool LHSIsHL = isCopyFromArgReg(LHS, V6CLANG::HL, DAG);
        bool RHSIsHL = isCopyFromArgReg(RHS, V6CLANG::HL, DAG);
        if (!LHSIsHL && RHSIsHL)
          std::swap(LHS, RHS);

        return DAG.getNode(V6ClangISD::DAD, DL, MVT::i16, LHS, RHS);
      }
    }
    break;

  case ISD::MUL:
    // Re-canonicalize i16 MUL so the operand sourced from the first-arg
    // register (HL) is always LHS.  The generic DAG combiner may swap
    // operands for canonical form; on V6CLANG that forces a HL↔DE register-swap
    // sequence (5 instructions) before the __mulhi3 libcall.  When the
    // HL-sourced value is LHS the calling convention places it directly into
    // the physical HL register with no copies.
    if (N->getValueType(0) == MVT::i16) {
      SDValue LHS = N->getOperand(0);
      SDValue RHS = N->getOperand(1);
      if (!isCopyFromArgReg(LHS, V6CLANG::HL, DAG) &&
          isCopyFromArgReg(RHS, V6CLANG::HL, DAG)) {
        SDLoc DL(N);
        return DAG.getNode(ISD::MUL, DL, MVT::i16, RHS, LHS);
      }
    }
    break;

  case ISD::SUB:
    // O41: sub i16 x, ±1..±3 → DCX16/INX16.
    if (N->getValueType(0) == MVT::i16) {
      if (auto *C = dyn_cast<ConstantSDNode>(N->getOperand(1))) {
        int64_t Val = C->getSExtValue();
        SDLoc DL(N);
        if (Val >= 1 && Val <= 3)
          return DAG.getNode(V6ClangISD::DCX16, DL, MVT::i16,
                             N->getOperand(0),
                             DAG.getTargetConstant(Val, DL, MVT::i8));
        if (Val >= -3 && Val <= -1)
          return DAG.getNode(V6ClangISD::INX16, DL, MVT::i16,
                             N->getOperand(0),
                             DAG.getTargetConstant(-Val, DL, MVT::i8));
      }
    }
    break;
  }

  return SDValue();
}

//===----------------------------------------------------------------------===//
// LowerOperation — dispatch custom-lowered operations
//===----------------------------------------------------------------------===//

SDValue V6ClangTargetLowering::LowerOperation(SDValue Op,
                                            SelectionDAG &DAG) const {
  switch (Op.getOpcode()) {
  default:
    report_fatal_error("V6CLANG: unimplemented operation: " +
                       Twine(Op.getOpcode()));
  case ISD::GlobalAddress:  return LowerGlobalAddress(Op, DAG);
  case ISD::ExternalSymbol: return LowerExternalSymbol(Op, DAG);
  case ISD::BR_CC:          return LowerBR_CC(Op, DAG);
  case ISD::SELECT_CC:      return LowerSELECT_CC(Op, DAG);
  case ISD::SHL:            return LowerSHL(Op, DAG);
  case ISD::SRL:            return LowerSRL(Op, DAG);
  case ISD::SRA:            return LowerSRA(Op, DAG);
  case ISD::ROTL:           return LowerROTL(Op, DAG);
  case ISD::ROTR:           return LowerROTR(Op, DAG);
  case ISD::ZERO_EXTEND:    return LowerZERO_EXTEND(Op, DAG);
  case ISD::SIGN_EXTEND:    return LowerSIGN_EXTEND(Op, DAG);
  case ISD::ANY_EXTEND:     return LowerANY_EXTEND(Op, DAG);
  case ISD::ADD:
  case ISD::AND:
  case ISD::OR:
  case ISD::XOR:            return LowerArithF(Op, DAG);
  case ISD::SUB:
    if (Op.getValueType() == MVT::i8) {
      if (auto *CLHS = dyn_cast<ConstantSDNode>(Op.getOperand(0))) {
        if ((CLHS->getZExtValue() & 0xFF) == 0 &&
            isCopyFromArgReg(Op.getOperand(1), V6CLANG::A, DAG))
          return DAG.getNode(V6ClangISD::NEG8, SDLoc(Op), MVT::i8,
                             Op.getOperand(1));
      }
    }
    return LowerArithF(Op, DAG);
  }
}

//===----------------------------------------------------------------------===//
// GlobalAddress / ExternalSymbol lowering → V6ClangISD::Wrapper
//===----------------------------------------------------------------------===//

SDValue V6ClangTargetLowering::LowerGlobalAddress(SDValue Op,
                                                SelectionDAG &DAG) const {
  SDLoc DL(Op);
  const GlobalAddressSDNode *GA = cast<GlobalAddressSDNode>(Op);
  SDValue Addr = DAG.getTargetGlobalAddress(GA->getGlobal(), DL, MVT::i16,
                                            GA->getOffset());
  return DAG.getNode(V6ClangISD::Wrapper, DL, MVT::i16, Addr);
}

SDValue V6ClangTargetLowering::LowerExternalSymbol(SDValue Op,
                                                 SelectionDAG &DAG) const {
  SDLoc DL(Op);
  const ExternalSymbolSDNode *ES = cast<ExternalSymbolSDNode>(Op);
  SDValue Addr = DAG.getTargetExternalSymbol(ES->getSymbol(), MVT::i16);
  return DAG.getNode(V6ClangISD::Wrapper, DL, MVT::i16, Addr);
}

//===----------------------------------------------------------------------===//
// BR_CC lowering → V6ClangISD::CMP + V6ClangISD::BRCOND
//===----------------------------------------------------------------------===//

// Convert LLVM ISD condition code to V6CLANG condition code.
static V6ClangCC::CondCode getV6ClangCC(ISD::CondCode CC) {
  switch (CC) {
  default: llvm_unreachable("unsupported condition code");
  case ISD::SETEQ:  return V6ClangCC::COND_Z;
  case ISD::SETNE:  return V6ClangCC::COND_NZ;
  case ISD::SETLT:  return V6ClangCC::COND_M;   // Signed: negative flag
  case ISD::SETGE:  return V6ClangCC::COND_P;   // Signed: positive flag
  case ISD::SETULT: return V6ClangCC::COND_C;   // Unsigned: carry
  case ISD::SETUGE: return V6ClangCC::COND_NC;  // Unsigned: no carry
  // For GT/LE, the caller must swap operands or use two conditions.
  // Expand handles that for us via BR_CC custom lowering.
  }
}

static bool matchI16SignedZeroTest(ISD::CondCode CC, SDValue LHS, SDValue RHS,
                                   SDValue &Value, V6ClangCC::CondCode &V6ClangC) {
  if (LHS.getValueType() != MVT::i16)
    return false;

  auto *CRHS = dyn_cast<ConstantSDNode>(RHS);
  if (!CRHS)
    return false;

  int64_t Imm = CRHS->getSExtValue() & 0xFFFF;
  switch (CC) {
  case ISD::SETGE:
    if (Imm == 0) {
      Value = LHS;
      V6ClangC = V6ClangCC::COND_P;
      return true;
    }
    break;
  case ISD::SETLT:
    if (Imm == 0) {
      Value = LHS;
      V6ClangC = V6ClangCC::COND_M;
      return true;
    }
    break;
  case ISD::SETGT:
    if (Imm == 0xFFFF) {
      Value = LHS;
      V6ClangC = V6ClangCC::COND_P;
      return true;
    }
    break;
  case ISD::SETLE:
    if (Imm == 0xFFFF) {
      Value = LHS;
      V6ClangC = V6ClangCC::COND_M;
      return true;
    }
    break;
  default:
    break;
  }

  return false;
}

SDValue V6ClangTargetLowering::LowerBR_CC(SDValue Op, SelectionDAG &DAG) const {
  SDLoc DL(Op);
  SDValue Chain  = Op.getOperand(0);
  ISD::CondCode CC = cast<CondCodeSDNode>(Op.getOperand(1))->get();
  SDValue LHS    = Op.getOperand(2);
  SDValue RHS    = Op.getOperand(3);
  SDValue Dest   = Op.getOperand(4);

  SDValue SignSrc;
  V6ClangCC::CondCode SignCC;
  if (matchI16SignedZeroTest(CC, LHS, RHS, SignSrc, SignCC)) {
    SDValue Flags = DAG.getNode(V6ClangISD::CMP_SIGN, DL, MVT::i8, SignSrc);
    SDValue CCVal = DAG.getConstant(SignCC, DL, MVT::i8);
    return DAG.getNode(V6ClangISD::BRCOND, DL, MVT::Other,
                       {Chain, Dest, CCVal, Flags});
  }

  // Handle GT/LE by swapping operands.
  switch (CC) {
  case ISD::SETGT:
    std::swap(LHS, RHS);
    CC = ISD::SETLT;
    break;
  case ISD::SETLE:
    std::swap(LHS, RHS);
    CC = ISD::SETGE;
    break;
  case ISD::SETUGT:
    std::swap(LHS, RHS);
    CC = ISD::SETULT;
    break;
  case ISD::SETULE:
    std::swap(LHS, RHS);
    CC = ISD::SETUGE;
    break;
  default:
    break;
  }

  V6ClangCC::CondCode V6ClangC = getV6ClangCC(CC);

  // For i16: use fused compare+branch pseudo (V6CLANG_BR_CC16) because
  // 16-bit comparisons require different flag sequences for EQ/NE vs LT/GE.
  if (LHS.getValueType() == MVT::i16) {
    SDValue CCVal = DAG.getTargetConstant(V6ClangC, DL, MVT::i8);
    SDValue Ops[] = {Chain, LHS, RHS, CCVal, Dest};
    return DAG.getNode(V6ClangISD::BR_CC16, DL, MVT::Other, Ops);
  }

  // For i8: ensure the immediate is on the RHS so CPI can match.
  // After GT/LE canonicalization (and LLVM's InstCombine converting
  // UGE/ULE/SGE/SLE to strict comparisons with adjusted constants),
  // the constant may end up on the LHS.  Undo this by transforming:
  //   OP(const, x) → INV_OP(x, const + 1)
  // For EQ/NE (commutative): simply swap without adjusting.
  if (LHS.getValueType() == MVT::i8) {
    if (auto *CLHS = dyn_cast<ConstantSDNode>(LHS)) {
      if (!isa<ConstantSDNode>(RHS)) {
        int64_t Imm = CLHS->getSExtValue();
        switch (V6ClangC) {
        case V6ClangCC::COND_Z:  // EQ: commutative, just swap
        case V6ClangCC::COND_NZ: // NE: commutative, just swap
          std::swap(LHS, RHS);
          break;
        case V6ClangCC::COND_C:  // ULT(C,x) → UGE(x, C+1)
          if ((Imm & 0xFF) != 0xFF) {
            LHS = RHS;
            RHS = DAG.getConstant((Imm + 1) & 0xFF, DL, MVT::i8);
            V6ClangC = V6ClangCC::COND_NC;
          }
          break;
        case V6ClangCC::COND_NC: // UGE(C,x) → ULT(x, C+1)
          if ((Imm & 0xFF) != 0xFF) {
            LHS = RHS;
            RHS = DAG.getConstant((Imm + 1) & 0xFF, DL, MVT::i8);
            V6ClangC = V6ClangCC::COND_C;
          }
          break;
        case V6ClangCC::COND_M:  // SLT(C,x) → SGE(x, C+1)
          if (Imm != 127) {
            LHS = RHS;
            RHS = DAG.getConstant((Imm + 1) & 0xFF, DL, MVT::i8);
            V6ClangC = V6ClangCC::COND_P;
          }
          break;
        case V6ClangCC::COND_P:  // SGE(C,x) → SLT(x, C+1)
          if (Imm != 127) {
            LHS = RHS;
            RHS = DAG.getConstant((Imm + 1) & 0xFF, DL, MVT::i8);
            V6ClangC = V6ClangCC::COND_M;
          }
          break;
        case V6ClangCC::COND_PO:
        case V6ClangCC::COND_PE:
          break;
        }
      }
    }
  }

  // O75 Phase B: if LHS is the result of a flag-producing arithmetic
  // node (V6ClangISD::*F) and we're comparing it to zero with EQ/NE,
  // consume its FLAGS directly — no redundant CMP/CPI.
  auto isFlagArith = [](unsigned Opc) {
    return Opc >= V6ClangISD::ADDF && Opc <= V6ClangISD::DECF;
  };
  if (LHS.getValueType() == MVT::i8 && isNullConstant(RHS) &&
      (V6ClangC == V6ClangCC::COND_Z || V6ClangC == V6ClangCC::COND_NZ)) {
    // LegalizeDAG processes nodes parent-first via AllNodes traversal,
    // so BR_CC is typically visited *before* its ISD::ADD/SUB/AND/OR/XOR
    // operand has been Custom-lowered to a V6ClangISD::*F node.  If LHS is
    // still a raw ISD arithmetic op we can lower, do it here proactively;
    // SelectionDAG CSE will dedupe with the eventual LowerArithF call.
    unsigned LhsOp = LHS.getOpcode();
    if (LhsOp == ISD::ADD || LhsOp == ISD::SUB || LhsOp == ISD::AND ||
        LhsOp == ISD::OR  || LhsOp == ISD::XOR) {
      SDValue Lowered = LowerArithF(LHS, DAG);
      if (Lowered) {
        // Redirect any other in-flight users of LHS to the new value.
        DAG.ReplaceAllUsesOfValueWith(LHS, Lowered);
        LHS = Lowered;
      }
    }
    if (isFlagArith(LHS.getOpcode())) {
      SDValue Flags = LHS.getValue(1);
      SDValue CCVal = DAG.getConstant(V6ClangC, DL, MVT::i8);
      return DAG.getNode(V6ClangISD::BRCOND, DL, MVT::Other,
                         {Chain, Dest, CCVal, Flags});
    }
  }

  // For i8: emit CMP (produces FLAGS as SSA i8) then BRCOND consumes it.
  SDValue Flags = DAG.getNode(V6ClangISD::CMP, DL, MVT::i8, LHS, RHS);
  SDValue CCVal = DAG.getConstant(V6ClangC, DL, MVT::i8);
  return DAG.getNode(V6ClangISD::BRCOND, DL, MVT::Other,
                     {Chain, Dest, CCVal, Flags});
}

//===----------------------------------------------------------------------===//
// SELECT_CC lowering → V6ClangISD::CMP + V6ClangISD::SELECT_CC
//===----------------------------------------------------------------------===//

SDValue V6ClangTargetLowering::LowerSELECT_CC(SDValue Op,
                                            SelectionDAG &DAG) const {
  SDLoc DL(Op);
  SDValue LHS      = Op.getOperand(0);
  SDValue RHS      = Op.getOperand(1);
  SDValue TrueVal  = Op.getOperand(2);
  SDValue FalseVal = Op.getOperand(3);
  ISD::CondCode CC = cast<CondCodeSDNode>(Op.getOperand(4))->get();

  SDValue SignSrc;
  V6ClangCC::CondCode SignCC;
  if (matchI16SignedZeroTest(CC, LHS, RHS, SignSrc, SignCC)) {
    SDValue Flags = DAG.getNode(V6ClangISD::CMP_SIGN, DL, MVT::i8, SignSrc);
    SDValue CCVal = DAG.getConstant(SignCC, DL, MVT::i8);
    SDVTList VTs = DAG.getVTList(Op.getValueType());
    return DAG.getNode(V6ClangISD::SELECT_CC, DL, VTs,
                       {TrueVal, FalseVal, CCVal, Flags});
  }

  // Handle GT/LE by swapping.
  switch (CC) {
  case ISD::SETGT:
    std::swap(LHS, RHS);
    CC = ISD::SETLT;
    break;
  case ISD::SETLE:
    std::swap(LHS, RHS);
    CC = ISD::SETGE;
    break;
  case ISD::SETUGT:
    std::swap(LHS, RHS);
    CC = ISD::SETULT;
    break;
  case ISD::SETULE:
    std::swap(LHS, RHS);
    CC = ISD::SETUGE;
    break;
  default:
    break;
  }

  V6ClangCC::CondCode V6ClangC = getV6ClangCC(CC);

  // For i8: ensure the immediate is on the RHS so CPI can match.
  if (LHS.getValueType() == MVT::i8) {
    if (auto *CLHS = dyn_cast<ConstantSDNode>(LHS)) {
      if (!isa<ConstantSDNode>(RHS)) {
        int64_t Imm = CLHS->getSExtValue();
        switch (V6ClangC) {
        case V6ClangCC::COND_Z:
        case V6ClangCC::COND_NZ:
          std::swap(LHS, RHS);
          break;
        case V6ClangCC::COND_C:
          if ((Imm & 0xFF) != 0xFF) {
            LHS = RHS;
            RHS = DAG.getConstant((Imm + 1) & 0xFF, DL, MVT::i8);
            V6ClangC = V6ClangCC::COND_NC;
          }
          break;
        case V6ClangCC::COND_NC:
          if ((Imm & 0xFF) != 0xFF) {
            LHS = RHS;
            RHS = DAG.getConstant((Imm + 1) & 0xFF, DL, MVT::i8);
            V6ClangC = V6ClangCC::COND_C;
          }
          break;
        case V6ClangCC::COND_M:
          if (Imm != 127) {
            LHS = RHS;
            RHS = DAG.getConstant((Imm + 1) & 0xFF, DL, MVT::i8);
            V6ClangC = V6ClangCC::COND_P;
          }
          break;
        case V6ClangCC::COND_P:
          if (Imm != 127) {
            LHS = RHS;
            RHS = DAG.getConstant((Imm + 1) & 0xFF, DL, MVT::i8);
            V6ClangC = V6ClangCC::COND_M;
          }
          break;
        case V6ClangCC::COND_PO:
        case V6ClangCC::COND_PE:
          break;
        }
      }
    }
  }

  SDValue CCVal = DAG.getConstant(V6ClangC, DL, MVT::i8);

  // O34: For i16 EQ/NE against zero, use zero-test (MOV A, Hi; ORA Lo)
  // instead of materializing 0 into a register pair for SUB/SBB.
  if (LHS.getValueType() == MVT::i16 && isNullConstant(RHS) &&
      (CC == ISD::SETEQ || CC == ISD::SETNE)) {
    SDValue Flags = DAG.getNode(V6ClangISD::CMP_ZERO, DL, MVT::i8, LHS);
    SDVTList VTs = DAG.getVTList(Op.getValueType());
    return DAG.getNode(V6ClangISD::SELECT_CC, DL, VTs,
                       {TrueVal, FalseVal, CCVal, Flags});
  }

  // O24: For i16 ordering conditions with constant operand, adjust so
  // MVI+SUB/SBB (const-reg direction) gives correct flags.
  // This is the only place where both CMP operands and CC are accessible.
  if (LHS.getValueType() == MVT::i16 &&
      (V6ClangC == V6ClangCC::COND_C || V6ClangC == V6ClangCC::COND_NC ||
       V6ClangC == V6ClangCC::COND_M || V6ClangC == V6ClangCC::COND_P)) {
    // Case A: Constant on LHS (from GT/LE swap above).
    // MVI+SUB computes const-reg, matching the swap direction. Keep CC.
    if (isa<ConstantSDNode>(LHS) && !isa<ConstantSDNode>(RHS)) {
      std::swap(LHS, RHS);
      // CC unchanged — MVI+SUB direction matches.
    }
    // Case B: Constant on RHS (natural ULT/UGE/SLT/SGE).
    // Adjust K → K-1 and invert CC (C↔NC, M↔P).
    else if (auto *CR = dyn_cast<ConstantSDNode>(RHS)) {
      int64_t K = CR->getSExtValue();
      bool IsUnsigned = (V6ClangC == V6ClangCC::COND_C || V6ClangC == V6ClangCC::COND_NC);
      bool CanAdjust = IsUnsigned ? ((K & 0xFFFF) != 0)
                                  : ((K & 0xFFFF) != 0x8000);
      if (CanAdjust) {
        int64_t Km1 = (K - 1) & 0xFFFF;
        RHS = DAG.getConstant(Km1, DL, MVT::i16);
        switch (V6ClangC) {
        case V6ClangCC::COND_C:  V6ClangC = V6ClangCC::COND_NC; break;
        case V6ClangCC::COND_NC: V6ClangC = V6ClangCC::COND_C;  break;
        case V6ClangCC::COND_M:  V6ClangC = V6ClangCC::COND_P;  break;
        case V6ClangCC::COND_P:  V6ClangC = V6ClangCC::COND_M;  break;
        default: break;
        }
        CCVal = DAG.getConstant(V6ClangC, DL, MVT::i8);
      }
    }
  }

  // O75 Phase B: short-circuit i8 EQ/NE-against-zero on a *F result.
  auto isFlagArith = [](unsigned Opc) {
    return Opc >= V6ClangISD::ADDF && Opc <= V6ClangISD::DECF;
  };
  if (LHS.getValueType() == MVT::i8 && isNullConstant(RHS) &&
      (V6ClangC == V6ClangCC::COND_Z || V6ClangC == V6ClangCC::COND_NZ)) {
    // Mirror of LowerBR_CC: proactively materialize the *F when LHS is
    // still raw ISD::ADD/SUB/AND/OR/XOR (LegalizeDAG visits SELECT_CC
    // before its arithmetic operand).  CSE will dedupe.
    unsigned LhsOp = LHS.getOpcode();
    if (LhsOp == ISD::ADD || LhsOp == ISD::SUB || LhsOp == ISD::AND ||
        LhsOp == ISD::OR  || LhsOp == ISD::XOR) {
      SDValue Lowered = LowerArithF(LHS, DAG);
      if (Lowered) {
        DAG.ReplaceAllUsesOfValueWith(LHS, Lowered);
        LHS = Lowered;
      }
    }
    if (isFlagArith(LHS.getOpcode())) {
      SDValue Flags = LHS.getValue(1);
      SDVTList VTs = DAG.getVTList(Op.getValueType());
      return DAG.getNode(V6ClangISD::SELECT_CC, DL, VTs,
                         {TrueVal, FalseVal, CCVal, Flags});
    }
  }

  // For i16 comparison operands, emit CMP16 then SELECT_CC (uses FLAGS).
  // For i8, emit CMP then SELECT_CC.
  SDValue Flags = DAG.getNode(V6ClangISD::CMP, DL, MVT::i8, LHS, RHS);
  SDVTList VTs = DAG.getVTList(Op.getValueType());
  return DAG.getNode(V6ClangISD::SELECT_CC, DL, VTs,
                     {TrueVal, FalseVal, CCVal, Flags});
}

//===----------------------------------------------------------------------===//
// Shift lowering — expand to rotates for shift-by-1, library call otherwise
//===----------------------------------------------------------------------===//

// For M4 we support shift-by-constant only.  For shift-by-1, emit the
// appropriate rotate instruction.  For larger constants, emit a sequence.
// Variable shifts are expanded to a loop (deferred to M7/M11 library call).

static SDValue expandShiftByOne(unsigned Opc, SDValue Op, SelectionDAG &DAG) {
  // This will be matched by the RLC/RAL/RRC/RAR TableGen patterns
  // in a later milestone.  For M4, return SDValue() and let the
  // expander handle it via repeated shift-by-1.
  return SDValue();
}

//===----------------------------------------------------------------------===//
// O75 Phase B: Lower i8 ADD/SUB/AND/OR/XOR to flag-producing V6ClangISD::*F
//===----------------------------------------------------------------------===//

SDValue V6ClangTargetLowering::LowerArithF(SDValue Op, SelectionDAG &DAG) const {
  SDLoc DL(Op);
  EVT VT = Op.getValueType();
  assert(VT == MVT::i8 && "LowerArithF only handles i8");

  SDValue LHS = Op.getOperand(0);
  SDValue RHS = Op.getOperand(1);
  unsigned Opc = Op.getOpcode();

  // XOR with 0xFF (i.e. ~x): leave as ISD::XOR so the CMA pattern can
  // match.  CMA does not affect FLAGS, so it is intentionally not part
  // of the *F flag-producing family.
  if (Opc == ISD::XOR) {
    if (auto *C = dyn_cast<ConstantSDNode>(RHS)) {
      if ((C->getZExtValue() & 0xFF) == 0xFF)
        return SDValue();
    }
    if (auto *C = dyn_cast<ConstantSDNode>(LHS)) {
      if ((C->getZExtValue() & 0xFF) == 0xFF)
        return SDValue();
    }
  }

  // ADD with ±1 → INCF / DECF (single-input, dst==src reg form).
  if (Opc == ISD::ADD) {
    if (auto *C = dyn_cast<ConstantSDNode>(RHS)) {
      int64_t V = C->getSExtValue();
      if (V == 1) {
        SDVTList VTs = DAG.getVTList(MVT::i8, MVT::i8);
        SDValue N = DAG.getNode(V6ClangISD::INCF, DL, VTs, LHS);
        return N.getValue(0);
      }
      if (V == -1) {
        SDVTList VTs = DAG.getVTList(MVT::i8, MVT::i8);
        SDValue N = DAG.getNode(V6ClangISD::DECF, DL, VTs, LHS);
        return N.getValue(0);
      }
    }
  }

  // Choose the *F or *F_IMM opcode.
  bool RHSIsImm = isa<ConstantSDNode>(RHS);
  unsigned FOpc;
  switch (Opc) {
  case ISD::ADD: FOpc = RHSIsImm ? V6ClangISD::ADDF_IMM : V6ClangISD::ADDF; break;
  case ISD::SUB: FOpc = RHSIsImm ? V6ClangISD::SUBF_IMM : V6ClangISD::SUBF; break;
  case ISD::AND: FOpc = RHSIsImm ? V6ClangISD::ANDF_IMM : V6ClangISD::ANDF; break;
  case ISD::OR:  FOpc = RHSIsImm ? V6ClangISD::ORF_IMM  : V6ClangISD::ORF;  break;
  case ISD::XOR: FOpc = RHSIsImm ? V6ClangISD::XORF_IMM : V6ClangISD::XORF; break;
  default: llvm_unreachable("LowerArithF: unexpected opcode");
  }

  // SUB has no commutative form; for ADD/AND/OR/XOR, if LHS is the
  // constant, swap so the immediate is on the RHS (canonical for *_IMM).
  if (RHSIsImm == false && isa<ConstantSDNode>(LHS) && Opc != ISD::SUB) {
    std::swap(LHS, RHS);
    RHSIsImm = true;
    switch (Opc) {
    case ISD::ADD: FOpc = V6ClangISD::ADDF_IMM; break;
    case ISD::AND: FOpc = V6ClangISD::ANDF_IMM; break;
    case ISD::OR:  FOpc = V6ClangISD::ORF_IMM;  break;
    case ISD::XOR: FOpc = V6ClangISD::XORF_IMM; break;
    default: break;
    }
  }

  SDVTList VTs = DAG.getVTList(MVT::i8, MVT::i8);
  SDValue N = DAG.getNode(FOpc, DL, VTs, LHS, RHS);
  return N.getValue(0);
}

SDValue V6ClangTargetLowering::LowerSHL(SDValue Op, SelectionDAG &DAG) const {
  if (Op.getValueType() == MVT::i16)
    return LowerSHL_i16(Op, DAG);

  SDLoc DL(Op);
  SDValue Val = Op.getOperand(0);
  SDValue Amt = Op.getOperand(1);

  // Only i8 supported here.
  if (Op.getValueType() != MVT::i8)
    return SDValue();

  // Constant shift amounts: unroll to add-to-self (shl 1 = ADD A,A).
  if (auto *CA = dyn_cast<ConstantSDNode>(Amt)) {
    unsigned ShAmt = CA->getZExtValue() & 7;
    if (ShAmt == 0)
      return Val;
    SDValue Result = Val;
    for (unsigned i = 0; i < ShAmt; ++i)
      Result = DAG.getNode(ISD::ADD, DL, MVT::i8, Result, Result);
    return Result;
  }

  // Variable i8 shift: promote to i16 (which uses libcall for variable amount).
  SDValue ExtVal = DAG.getNode(ISD::ZERO_EXTEND, DL, MVT::i16, Val);
  SDValue ExtAmt = DAG.getNode(ISD::ZERO_EXTEND, DL, MVT::i16, Amt);
  SDValue Shifted = DAG.getNode(ISD::SHL, DL, MVT::i16, ExtVal, ExtAmt);
  return DAG.getNode(ISD::TRUNCATE, DL, MVT::i8, Shifted);
}

// Forward declaration: emitRotChain is defined in the O67 section below.
static SDValue emitRotChain(SelectionDAG &DAG, const SDLoc &DL, SDValue Val,
                            unsigned RotOpc, unsigned N);

SDValue V6ClangTargetLowering::LowerSRL(SDValue Op, SelectionDAG &DAG) const {
  if (Op.getValueType() == MVT::i16)
    return LowerSRL_i16(Op, DAG);

  SDLoc DL(Op);
  SDValue Val = Op.getOperand(0);
  SDValue Amt = Op.getOperand(1);

  if (Op.getValueType() != MVT::i8)
    return SDValue();

  // Constant shift: emit pure 8-bit rotate chain + AND mask.
  // Avoids widening to i16 (BUILD_PAIR + SRL16 sequence).
  //   ShAmt <= 4: RRC x ShAmt, then ANI (0xFF >> ShAmt).
  //   ShAmt >  4: RLC x (8-ShAmt) rotates the desired bits into position,
  //               then same ANI mask clears the rotated-in garbage.
  if (auto *CA = dyn_cast<ConstantSDNode>(Amt)) {
    unsigned ShAmt = CA->getZExtValue() & 7;
    if (ShAmt == 0)
      return Val;
    SDValue Rotated;
    if (ShAmt <= 4)
      Rotated = emitRotChain(DAG, DL, Val, V6ClangISD::ROTR8, ShAmt);
    else
      Rotated = emitRotChain(DAG, DL, Val, V6ClangISD::ROTL8, 8 - ShAmt);
    unsigned MaskVal = 0xFFu >> ShAmt;
    return DAG.getNode(ISD::AND, DL, MVT::i8, Rotated,
                       DAG.getConstant(MaskVal, DL, MVT::i8));
  }

  // Variable i8 logical right shift: promote to i16.
  SDValue ExtVal = DAG.getNode(ISD::ZERO_EXTEND, DL, MVT::i16, Val);
  SDValue ExtAmt = DAG.getNode(ISD::ZERO_EXTEND, DL, MVT::i16, Amt);
  SDValue Shifted = DAG.getNode(ISD::SRL, DL, MVT::i16, ExtVal, ExtAmt);
  return DAG.getNode(ISD::TRUNCATE, DL, MVT::i8, Shifted);
}

SDValue V6ClangTargetLowering::LowerSRA(SDValue Op, SelectionDAG &DAG) const {
  if (Op.getValueType() == MVT::i16)
    return LowerSRA_i16(Op, DAG);

  SDLoc DL(Op);
  SDValue Val = Op.getOperand(0);
  SDValue Amt = Op.getOperand(1);

  if (Op.getValueType() != MVT::i8)
    return SDValue();

  // Constant shift: unroll.
  if (auto *CA = dyn_cast<ConstantSDNode>(Amt)) {
    unsigned ShAmt = CA->getZExtValue() & 7;
    if (ShAmt == 0)
      return Val;
    // For i8 arithmetic right shift by constant, promote to i16 and shift.
    SDValue Ext = DAG.getNode(ISD::SIGN_EXTEND, DL, MVT::i16, Val);
    SDValue ShiftedWide = DAG.getNode(ISD::SRA, DL, MVT::i16, Ext,
                                      DAG.getConstant(ShAmt, DL, MVT::i8));
    return DAG.getNode(ISD::TRUNCATE, DL, MVT::i8, ShiftedWide);
  }

  // Variable i8 arithmetic right shift: sign-extend to i16, shift.
  SDValue ExtVal = DAG.getNode(ISD::SIGN_EXTEND, DL, MVT::i16, Val);
  SDValue ExtAmt = DAG.getNode(ISD::ZERO_EXTEND, DL, MVT::i16, Amt);
  SDValue Shifted = DAG.getNode(ISD::SRA, DL, MVT::i16, ExtVal, ExtAmt);
  return DAG.getNode(ISD::TRUNCATE, DL, MVT::i8, Shifted);
}

//===----------------------------------------------------------------------===//
// O67 — i8 rotate lowering: ISD::ROTL/ROTR → chain of V6ClangISD::ROTL8/ROTR8
//===----------------------------------------------------------------------===//

// Helper: emit a chain of N × 1-bit rotates (V6ClangISD::ROTL8 or ROTR8).
static SDValue emitRotChain(SelectionDAG &DAG, const SDLoc &DL, SDValue Val,
                            unsigned RotOpc, unsigned N) {
  SDValue R = Val;
  for (unsigned i = 0; i < N; ++i)
    R = DAG.getNode(RotOpc, DL, MVT::i8, R);
  return R;
}

SDValue V6ClangTargetLowering::LowerROTL(SDValue Op, SelectionDAG &DAG) const {
  EVT VT = Op.getValueType();
  SDLoc DL(Op);
  SDValue Val = Op.getOperand(0);
  SDValue Amt = Op.getOperand(1);

  if (VT == MVT::i16) {
    // O68 Phase 2: rotl i16 x, 1 → V6ClangISD::ROTL16_1 (DAD H + ACI 0).
    // Other constants and variable amounts return SDValue() so LLVM
    // falls back to the default Expand path (SHL+SRL+OR).
    if (auto *CA = dyn_cast<ConstantSDNode>(Amt))
      if ((CA->getZExtValue() & 15) == 1)
        return DAG.getNode(V6ClangISD::ROTL16_1, DL, MVT::i16, Val);
    return SDValue();
  }

  if (VT != MVT::i8)
    return SDValue();

  if (auto *CA = dyn_cast<ConstantSDNode>(Amt)) {
    unsigned N = CA->getZExtValue() & 7;
    if (N == 0)
      return Val;
    // Canonicalise direction: ROTL by N == ROTR by (8-N). Pick the
    // shorter chain. N == 4 ties (4 left == 4 right) — keep ROTL.
    if (N > 4)
      return emitRotChain(DAG, DL, Val, V6ClangISD::ROTR8, 8 - N);
    return emitRotChain(DAG, DL, Val, V6ClangISD::ROTL8, N);
  }

  // Variable amount: synthesise via i16 promotion. Vanishingly rare in
  // real i8 code; no dedicated runtime helper needed.
  // ROTL(x, amt) = ((x<<8 | x) << amt) >> 8  (low byte of the result).
  SDValue Ext = DAG.getNode(ISD::ZERO_EXTEND, DL, MVT::i16, Val);
  SDValue Eight = DAG.getConstant(8, DL, MVT::i16);
  SDValue Hi = DAG.getNode(ISD::SHL, DL, MVT::i16, Ext, Eight);
  SDValue Wide = DAG.getNode(ISD::OR, DL, MVT::i16, Hi, Ext);
  SDValue Amt16 = DAG.getNode(ISD::ZERO_EXTEND, DL, MVT::i16, Amt);
  SDValue Sh = DAG.getNode(ISD::SHL, DL, MVT::i16, Wide, Amt16);
  SDValue Shr = DAG.getNode(ISD::SRL, DL, MVT::i16, Sh, Eight);
  return DAG.getNode(ISD::TRUNCATE, DL, MVT::i8, Shr);
}

SDValue V6ClangTargetLowering::LowerROTR(SDValue Op, SelectionDAG &DAG) const {
  if (Op.getValueType() != MVT::i8)
    return SDValue();

  SDLoc DL(Op);
  SDValue Val = Op.getOperand(0);
  SDValue Amt = Op.getOperand(1);

  if (auto *CA = dyn_cast<ConstantSDNode>(Amt)) {
    unsigned N = CA->getZExtValue() & 7;
    if (N == 0)
      return Val;
    if (N > 4)
      return emitRotChain(DAG, DL, Val, V6ClangISD::ROTL8, 8 - N);
    return emitRotChain(DAG, DL, Val, V6ClangISD::ROTR8, N);
  }

  // Variable amount: ROTR(x, amt) = ((x<<8 | x) >> amt) low byte.
  SDValue Ext = DAG.getNode(ISD::ZERO_EXTEND, DL, MVT::i16, Val);
  SDValue Eight = DAG.getConstant(8, DL, MVT::i16);
  SDValue Hi = DAG.getNode(ISD::SHL, DL, MVT::i16, Ext, Eight);
  SDValue Wide = DAG.getNode(ISD::OR, DL, MVT::i16, Hi, Ext);
  SDValue Amt16 = DAG.getNode(ISD::ZERO_EXTEND, DL, MVT::i16, Amt);
  SDValue Shr = DAG.getNode(ISD::SRL, DL, MVT::i16, Wide, Amt16);
  return DAG.getNode(ISD::TRUNCATE, DL, MVT::i8, Shr);
}

//===----------------------------------------------------------------------===//
// i16 Shift lowering — emit strategy-specific V6CLANG shift pseudos for constants
//===----------------------------------------------------------------------===//

SDValue V6ClangTargetLowering::LowerSHL_i16(SDValue Op, SelectionDAG &DAG) const {
  SDLoc DL(Op);
  SDValue Val = Op.getOperand(0);
  SDValue Amt = Op.getOperand(1);

  if (auto *CA = dyn_cast<ConstantSDNode>(Amt)) {
    unsigned ShAmt = CA->getZExtValue() & 15;
    if (ShAmt == 0)
      return Val;
    if (ShAmt <= 7)
      return DAG.getNode(V6ClangISD::SHL16_DAD, DL, MVT::i16, Val,
                         DAG.getTargetConstant(ShAmt, DL, MVT::i8));
    if (ShAmt == 8)
      return DAG.getNode(V6ClangISD::SHL16_BYTE, DL, MVT::i16, Val,
                         DAG.getTargetConstant(ShAmt, DL, MVT::i8));
    return DAG.getNode(V6ClangISD::SHL16_RAM_HI, DL, MVT::i16, Val,
                       DAG.getTargetConstant(ShAmt, DL, MVT::i8));
  }

  // Variable i16 shift left: emit libcall.
  TargetLowering::MakeLibCallOptions CallOptions;
  return makeLibCall(DAG, RTLIB::SHL_I16, MVT::i16, {Val, Amt}, CallOptions, DL).first;
}

SDValue V6ClangTargetLowering::LowerSRL_i16(SDValue Op, SelectionDAG &DAG) const {
  SDLoc DL(Op);
  SDValue Val = Op.getOperand(0);
  SDValue Amt = Op.getOperand(1);

  if (auto *CA = dyn_cast<ConstantSDNode>(Amt)) {
    unsigned ShAmt = CA->getZExtValue() & 15;
    if (ShAmt == 0)
      return Val;
    if (ShAmt <= 2)
      return DAG.getNode(V6ClangISD::SRL16_RAR, DL, MVT::i16, Val,
                         DAG.getTargetConstant(ShAmt, DL, MVT::i8));
    if (ShAmt <= 7)
      return DAG.getNode(V6ClangISD::SRL16_24BIT, DL, MVT::i16, Val,
                         DAG.getTargetConstant(ShAmt, DL, MVT::i8));
    if (ShAmt == 8)
      return DAG.getNode(V6ClangISD::SRL16_BYTE, DL, MVT::i16, Val,
                         DAG.getTargetConstant(ShAmt, DL, MVT::i8));
    return DAG.getNode(V6ClangISD::SRL16_RAM_LO, DL, MVT::i16, Val,
                       DAG.getTargetConstant(ShAmt, DL, MVT::i8));
  }

  // Variable i16 logical right shift: emit libcall.
  TargetLowering::MakeLibCallOptions CallOptions;
  return makeLibCall(DAG, RTLIB::SRL_I16, MVT::i16, {Val, Amt}, CallOptions, DL).first;
}

SDValue V6ClangTargetLowering::LowerSRA_i16(SDValue Op, SelectionDAG &DAG) const {
  SDLoc DL(Op);
  SDValue Val = Op.getOperand(0);
  SDValue Amt = Op.getOperand(1);

  if (auto *CA = dyn_cast<ConstantSDNode>(Amt)) {
    unsigned ShAmt = CA->getZExtValue() & 15;
    if (ShAmt == 0)
      return Val;
    if (ShAmt <= 2)
      return DAG.getNode(V6ClangISD::SRA16_RAR, DL, MVT::i16, Val,
                         DAG.getTargetConstant(ShAmt, DL, MVT::i8));
    if (ShAmt <= 7)
      return DAG.getNode(V6ClangISD::SRA16_24BIT, DL, MVT::i16, Val,
                         DAG.getTargetConstant(ShAmt, DL, MVT::i8));
    if (ShAmt == 8)
      return DAG.getNode(V6ClangISD::SRA16_BYTE, DL, MVT::i16, Val,
                         DAG.getTargetConstant(ShAmt, DL, MVT::i8));
    return DAG.getNode(V6ClangISD::SRA16_RAM_LO, DL, MVT::i16, Val,
                       DAG.getTargetConstant(ShAmt, DL, MVT::i8));
  }

  // Variable i16 arithmetic right shift: emit libcall.
  TargetLowering::MakeLibCallOptions CallOptions;
  return makeLibCall(DAG, RTLIB::SRA_I16, MVT::i16, {Val, Amt}, CallOptions, DL).first;
}

//===----------------------------------------------------------------------===//
// Zero/Sign/Any extend i8 → i16
//===----------------------------------------------------------------------===//

SDValue V6ClangTargetLowering::LowerZERO_EXTEND(SDValue Op,
                                              SelectionDAG &DAG) const {
  SDLoc DL(Op);
  SDValue Val = Op.getOperand(0);
  assert(Val.getValueType() == MVT::i8 && Op.getValueType() == MVT::i16);

  SDValue Zero = DAG.getConstant(0, DL, MVT::i8);
  return DAG.getNode(ISD::BUILD_PAIR, DL, MVT::i16, Val, Zero);
}

SDValue V6ClangTargetLowering::LowerSIGN_EXTEND(SDValue Op,
                                              SelectionDAG &DAG) const {
  SDLoc DL(Op);
  SDValue Val = Op.getOperand(0);
  assert(Val.getValueType() == MVT::i8 && Op.getValueType() == MVT::i16);

  // Use V6ClangISD::SEXT node — expands post-RA to RLC+SBB sequence.
  return DAG.getNode(V6ClangISD::SEXT, DL, MVT::i16, Val);
}

SDValue V6ClangTargetLowering::LowerANY_EXTEND(SDValue Op,
                                             SelectionDAG &DAG) const {
  SDLoc DL(Op);
  SDValue Val = Op.getOperand(0);
  assert(Val.getValueType() == MVT::i8 && Op.getValueType() == MVT::i16);

  SDValue Hi = DAG.getUNDEF(MVT::i8);
  return DAG.getNode(ISD::BUILD_PAIR, DL, MVT::i16, Val, Hi);
}

//===----------------------------------------------------------------------===//
// LowerFormalArguments — copy arguments from physical regs to virtual regs
//
// V6CLANG_CConv (Asm-Interop Overhaul Phase 2): free-list-based assignment that
// allows i8 and i16 arguments to share the same underlying registers in any
// order.  Two parallel free-lists are maintained and kept consistent:
//
//   FreeI8  : { A, B, C, D, E, L, H }  (preferred order for 8-bit args)
//   FreeI16 : { HL, DE, BC }           (preferred order for 16-bit args)
//
// When an i8 is taken, we remove the picked register from FreeI8 AND remove
// any 16-bit pair containing it from FreeI16.  When an i16 is taken, we remove
// the pair from FreeI16 AND remove both halves from FreeI8.  Once a list is
// empty the corresponding type spills to the stack.
//
// Examples (same callee signature mapping in caller and callee):
//   foo(i8, i8, i8, i16, i16)      → A, B, C, HL, DE
//   foo(i16, i16, i8, i16)         → HL, DE, A, BC
//   foo(i8, i16, i8, i16)          → A, HL, B, DE
//   foo(i16, i16, i8, i8)          → HL, DE, A, B
//===----------------------------------------------------------------------===//

namespace {
// Free-list register allocator used by both LowerFormalArguments and LowerCall
// to assign physical registers to outgoing/incoming arguments.  Returns 0 when
// the relevant list is exhausted (caller should spill to the stack).
class V6ClangArgAllocator {
  SmallVector<MCPhysReg, 7> FreeI8;
  SmallVector<MCPhysReg, 3> FreeI16;

  // Drop a register from a free-list if present; preserves order.
  static void dropReg(SmallVectorImpl<MCPhysReg> &List, MCPhysReg R) {
    auto It = std::find(List.begin(), List.end(), R);
    if (It != List.end())
      List.erase(It);
  }

  // Map an i16 pair to its two 8-bit halves.  Returns {0,0} for non-paired.
  static std::pair<MCPhysReg, MCPhysReg> halves(MCPhysReg Pair) {
    switch (Pair) {
    case V6CLANG::HL: return {V6CLANG::H, V6CLANG::L};
    case V6CLANG::DE: return {V6CLANG::D, V6CLANG::E};
    case V6CLANG::BC: return {V6CLANG::B, V6CLANG::C};
    default:      return {MCRegister::NoRegister, MCRegister::NoRegister};
    }
  }

  // Map an 8-bit half to its enclosing i16 pair.  Returns 0 when none.
  static MCPhysReg pairOf(MCPhysReg Half) {
    switch (Half) {
    case V6CLANG::H: case V6CLANG::L: return V6CLANG::HL;
    case V6CLANG::D: case V6CLANG::E: return V6CLANG::DE;
    case V6CLANG::B: case V6CLANG::C: return V6CLANG::BC;
    default:                  return MCRegister::NoRegister;
    }
  }

public:
  V6ClangArgAllocator()
      : FreeI8{V6CLANG::A, V6CLANG::B, V6CLANG::C, V6CLANG::D, V6CLANG::E, V6CLANG::L, V6CLANG::H},
        FreeI16{V6CLANG::HL, V6CLANG::DE, V6CLANG::BC} {}

  MCPhysReg takeI8() {
    if (FreeI8.empty())
      return MCRegister::NoRegister;
    MCPhysReg R = FreeI8.front();
    FreeI8.erase(FreeI8.begin());
    if (MCPhysReg P = pairOf(R))
      dropReg(FreeI16, P);
    return R;
  }

  MCPhysReg takeI16() {
    if (FreeI16.empty())
      return MCRegister::NoRegister;
    MCPhysReg P = FreeI16.front();
    FreeI16.erase(FreeI16.begin());
    auto Hs = halves(P);
    dropReg(FreeI8, Hs.first);
    dropReg(FreeI8, Hs.second);
    return P;
  }
};
} // end anonymous namespace

SDValue V6ClangTargetLowering::LowerFormalArguments(
    SDValue Chain, CallingConv::ID CallConv, bool isVarArg,
    const SmallVectorImpl<ISD::InputArg> &Ins, const SDLoc &DL,
    SelectionDAG &DAG, SmallVectorImpl<SDValue> &InVals) const {
  MachineFunction &MF = DAG.getMachineFunction();
  MachineFrameInfo &MFI = MF.getFrameInfo();
  MachineRegisterInfo &RegInfo = MF.getRegInfo();

  V6ClangArgAllocator Alloc;
  // Offset (in bytes) of the next incoming stack argument relative to the
  // outgoing-arg area in the caller's frame. Translated to a callee-SP
  // offset by adding 2 for the return address pushed by CALL.
  unsigned StackOffset = 0;

  for (unsigned i = 0, e = Ins.size(); i != e; ++i) {
    MVT VT = Ins[i].VT;

    MCPhysReg PReg = MCRegister::NoRegister;
    if (VT == MVT::i8)
      PReg = Alloc.takeI8();
    else if (VT == MVT::i16)
      PReg = Alloc.takeI16();
    else
      report_fatal_error("V6CLANG: unsupported argument type");

    if (PReg) {
      // Register argument.
      const TargetRegisterClass *RC =
          (VT == MVT::i8) ? &V6CLANG::GR8RegClass : &V6CLANG::GR16RegClass;
      Register VReg = RegInfo.createVirtualRegister(RC);
      RegInfo.addLiveIn(PReg, VReg);
      SDValue ArgVal = DAG.getCopyFromReg(Chain, DL, VReg, VT);
      InVals.push_back(ArgVal);
    } else {
      // Stack argument. Located above the 2-byte return address pushed by
      // CALL. The eliminateFrameIndex helper adds StackSize to the SPOffset
      // recorded here, so we encode the +2 ret-addr skip plus the running
      // arg offset.
      unsigned Size = VT.getSizeInBits() / 8;
      int FI = MFI.CreateFixedObject(Size,
                                      /*SPOffset=*/2 + StackOffset,
                                      /*IsImmutable=*/true);
      StackOffset += Size;
      SDValue FIN = DAG.getFrameIndex(FI, MVT::i16);
      SDValue ArgVal = DAG.getLoad(VT, DL, Chain, FIN,
                                   MachinePointerInfo::getFixedStack(MF, FI));
      InVals.push_back(ArgVal);
    }
  }

  return Chain;
}

//===----------------------------------------------------------------------===//
// LowerReturn — copy return value to physical registers
//
// Return: i8 → A, i16 → HL, i32 → DE:HL (DE=high, HL=low)
//===----------------------------------------------------------------------===//

SDValue V6ClangTargetLowering::LowerReturn(
    SDValue Chain, CallingConv::ID CallConv, bool isVarArg,
    const SmallVectorImpl<ISD::OutputArg> &Outs,
    const SmallVectorImpl<SDValue> &OutVals, const SDLoc &DL,
    SelectionDAG &DAG) const {
  SmallVector<SDValue, 4> RetOps;
  RetOps.push_back(Chain);

  SDValue Glue;

  // Return register assignment: i8→A, i16→HL (first), DE (second).
  // For i32 returns (type-legalized to two i16), this gives DE:HL.
  static const MCPhysReg RetRegsI16[] = {V6CLANG::HL, V6CLANG::DE};
  unsigned I16RetIdx = 0;

  for (unsigned i = 0, e = Outs.size(); i != e; ++i) {
    MVT VT = Outs[i].VT;
    SDValue Val = OutVals[i];

    if (VT == MVT::i8) {
      Chain = DAG.getCopyToReg(Chain, DL, V6CLANG::A, Val, Glue);
      Glue = Chain.getValue(1);
      RetOps.push_back(DAG.getRegister(V6CLANG::A, MVT::i8));
    } else if (VT == MVT::i16) {
      if (I16RetIdx >= 2)
        report_fatal_error("V6CLANG: too many i16 return values");
      MCPhysReg Reg = RetRegsI16[I16RetIdx++];
      Chain = DAG.getCopyToReg(Chain, DL, Reg, Val, Glue);
      Glue = Chain.getValue(1);
      RetOps.push_back(DAG.getRegister(Reg, MVT::i16));
    } else {
      report_fatal_error("V6CLANG: unsupported return type");
    }
  }

  RetOps[0] = Chain; // Update chain.
  if (Glue.getNode())
    RetOps.push_back(Glue);

  return DAG.getNode(V6ClangISD::RET, DL, MVT::Other, RetOps);
}

//===----------------------------------------------------------------------===//
// LowerCall — function call lowering with full calling convention
//
// V6CLANG_CConv: position-based — see LowerFormalArguments for mapping.
// Stack args pushed right-to-left. Caller cleans up after return.
//===----------------------------------------------------------------------===//

SDValue V6ClangTargetLowering::LowerCall(TargetLowering::CallLoweringInfo &CLI,
                                      SmallVectorImpl<SDValue> &InVals) const {
  // V6CLANG does not support tail calls at the ISel level. Reset the flag so
  // LLVM's generic machinery emits a normal CALL + RET sequence.
  CLI.IsTailCall = false;

  SelectionDAG &DAG = CLI.DAG;
  SDLoc DL = CLI.DL;
  SmallVectorImpl<ISD::OutputArg> &Outs = CLI.Outs;
  SmallVectorImpl<SDValue> &OutVals = CLI.OutVals;
  SmallVectorImpl<ISD::InputArg> &Ins = CLI.Ins;
  SDValue Chain = CLI.Chain;
  SDValue Callee = CLI.Callee;
  CallingConv::ID CallConv = CLI.CallConv;

  SmallVector<std::pair<Register, SDValue>, 4> RegsToPass;
  SmallVector<SDValue, 8> MemOpChains;
  SDValue Glue;

  // Pre-pass: compute total stack bytes needed for overflow arguments using a
  // simulated allocator that mirrors the assignment loop below.
  unsigned NumStackBytes = 0;
  {
    V6ClangArgAllocator SizeAlloc;
    for (unsigned i = 0, e = Outs.size(); i != e; ++i) {
      MVT VT = Outs[i].VT;
      MCPhysReg PReg = (VT == MVT::i8)  ? SizeAlloc.takeI8()
                       : (VT == MVT::i16) ? SizeAlloc.takeI16()
                                          : MCRegister::NoRegister;
      if (!PReg)
        NumStackBytes += VT.getSizeInBits() / 8;
    }
  }

  // ADJCALLSTACKDOWN.
  Chain = DAG.getCALLSEQ_START(Chain, NumStackBytes, 0, DL);

  // Assign arguments: register args first, then stack.
  V6ClangArgAllocator Alloc;
  unsigned StackOffset = 0;
  for (unsigned i = 0, e = Outs.size(); i != e; ++i) {
    MVT VT = Outs[i].VT;
    SDValue Arg = OutVals[i];

    MCPhysReg PReg = MCRegister::NoRegister;
    if (VT == MVT::i8)
      PReg = Alloc.takeI8();
    else if (VT == MVT::i16)
      PReg = Alloc.takeI16();
    else
      report_fatal_error("V6CLANG: unsupported call argument type");

    if (PReg) {
      RegsToPass.push_back(std::make_pair(PReg, Arg));
    } else {
      // Stack argument. Push right-to-left (last arg at highest address).
      // We store to the outgoing argument area of the current frame.
      unsigned Size = VT.getSizeInBits() / 8;
      SDValue PtrOff = DAG.getIntPtrConstant(StackOffset, DL);
      SDValue SPAddr = DAG.getCopyFromReg(Chain, DL, V6CLANG::SP, MVT::i16);
      SDValue Addr = DAG.getNode(ISD::ADD, DL, MVT::i16, SPAddr, PtrOff);
      SDValue Store = DAG.getStore(Chain, DL, Arg, Addr,
                                   MachinePointerInfo());
      MemOpChains.push_back(Store);
      StackOffset += Size;
    }
  }

  // Emit all stores.
  if (!MemOpChains.empty())
    Chain = DAG.getNode(ISD::TokenFactor, DL, MVT::Other, MemOpChains);

  // Emit CopyToReg for each register argument.
  for (auto &Reg : RegsToPass) {
    Chain = DAG.getCopyToReg(Chain, DL, Reg.first, Reg.second, Glue);
    Glue = Chain.getValue(1);
  }

  // If the callee is a GlobalAddress or ExternalSymbol, wrap it.
  if (GlobalAddressSDNode *G = dyn_cast<GlobalAddressSDNode>(Callee))
    Callee = DAG.getTargetGlobalAddress(G->getGlobal(), DL, MVT::i16);
  else if (ExternalSymbolSDNode *E = dyn_cast<ExternalSymbolSDNode>(Callee))
    Callee = DAG.getTargetExternalSymbol(E->getSymbol(), MVT::i16);

  // Build the call node.
  SmallVector<SDValue, 8> Ops;
  Ops.push_back(Chain);
  Ops.push_back(Callee);

  // Add register arguments as implicit operands.
  for (auto &Reg : RegsToPass)
    Ops.push_back(DAG.getRegister(Reg.first,
                                  Reg.second.getValueType()));

  // Add a register mask indicating all registers are clobbered.
  const TargetRegisterInfo *TRI =
      DAG.getMachineFunction().getSubtarget().getRegisterInfo();
  const uint32_t *Mask =
      TRI->getCallPreservedMask(DAG.getMachineFunction(), CallConv);
  Ops.push_back(DAG.getRegisterMask(Mask));

  if (Glue.getNode())
    Ops.push_back(Glue);

  SDVTList NodeTys = DAG.getVTList(MVT::Other, MVT::Glue);
  Chain = DAG.getNode(V6ClangISD::CALL, DL, NodeTys, Ops);
  Glue = Chain.getValue(1);

  // ADJCALLSTACKUP.
  Chain = DAG.getCALLSEQ_END(Chain, NumStackBytes, 0, Glue, DL);
  Glue = Chain.getValue(1);

  // Copy return values from physical registers.
  for (unsigned i = 0, e = Ins.size(); i != e; ++i) {
    MVT VT = Ins[i].VT;
    MCPhysReg RetReg;
    if (VT == MVT::i8)
      RetReg = V6CLANG::A;
    else if (VT == MVT::i16)
      RetReg = V6CLANG::HL;
    else
      report_fatal_error("V6CLANG: unsupported call return type");

    Chain = DAG.getCopyFromReg(Chain, DL, RetReg, VT, Glue).getValue(1);
    InVals.push_back(Chain.getValue(0));
    Glue = Chain.getValue(2);
  }

  return Chain;
}

//===----------------------------------------------------------------------===//
// EmitInstrWithCustomInserter — expand pseudo-instructions
//===----------------------------------------------------------------------===//

/// Return true if physical register Reg is dead (no uses before the next def)
/// starting from the instruction following MI in MBB.
/// Mirrors isRegDeadAtMI in V6ClangInstrInfo.cpp. (O81)
static bool isPhysRegDeadAtMI(unsigned Reg, const MachineInstr &MI,
                               MachineBasicBlock &MBB,
                               const TargetRegisterInfo *TRI) {
  for (auto I = std::next(MI.getIterator()); I != MBB.end(); ++I) {
    bool usesReg = false, defsReg = false;
    for (const MachineOperand &MO : I->operands()) {
      if (!MO.isReg() || !TRI->regsOverlap(MO.getReg(), Reg)) continue;
      if (MO.isUse() && !MO.isUndef()) usesReg = true;
      if (MO.isDef()) defsReg = true;
    }
    if (usesReg) return false;
    if (defsReg) return true;
  }
  for (MachineBasicBlock *Succ : MBB.successors())
    for (MCRegAliasIterator AI(Reg, TRI, true); AI.isValid(); ++AI)
      if (Succ->isLiveIn(*AI)) return false;
  return true;
}

MachineBasicBlock *
V6ClangTargetLowering::EmitInstrWithCustomInserter(MachineInstr &MI,
                                                MachineBasicBlock *BB) const {
  switch (MI.getOpcode()) {
  default:
    llvm_unreachable("Unexpected instr type to insert");
  case V6CLANG::V6CLANG_SELECT_CC:
  case V6CLANG::V6CLANG_SELECT_CC16: {
    // Expand V6CLANG_SELECT_CC into a diamond control flow:
    //   BB:
    //     ... (FLAGS set by preceding CMP)
    //     J_inv SinkBB        ; branch on inverted condition (false path)
    //   TrueBB:               ; fallthrough from BB (true path)
    //     ... = TrueVal
    //   SinkBB:               ; fallthrough from TrueBB
    //     ... = PHI(TrueVal from TrueBB, FalseVal from BB)

    const TargetInstrInfo &TII = *BB->getParent()->getSubtarget().getInstrInfo();
    DebugLoc DL = MI.getDebugLoc();

    Register DstReg = MI.getOperand(0).getReg();
    Register TrueReg = MI.getOperand(1).getReg();
    Register FalseReg = MI.getOperand(2).getReg();
    int64_t CC = MI.getOperand(3).getImm();

    // Create new basic blocks.
    MachineFunction *MF = BB->getParent();

    // O81: if this is an i8 select with both arms being rematerializable
    // constants and A is dead at the select, route through physreg A using
    // a 4-block diamond. This allows the O55 peephole (MVI A,0 → XRA A)
    // to fire on the zero arm, saving 1B / 4cc in HL-destination loops.
    MachineRegisterInfo &MRI = MF->getRegInfo();
    const TargetRegisterInfo *TRI =
        BB->getParent()->getSubtarget().getRegisterInfo();

    auto isImmRemat = [&](Register R) -> MachineInstr * {
      if (!R.isVirtual()) return nullptr;
      MachineInstr *Def = MRI.getUniqueVRegDef(R);
      if (!Def || Def->getParent() != BB) return nullptr;
      if (Def->getOpcode() != V6CLANG::MVIr) return nullptr;
      if (!MRI.hasOneNonDBGUse(R)) return nullptr;
      return Def;
    };

    if (MI.getOpcode() == V6CLANG::V6CLANG_SELECT_CC) {
      MachineInstr *TrueDef  = isImmRemat(TrueReg);
      MachineInstr *FalseDef = isImmRemat(FalseReg);
      if (TrueDef && FalseDef && isPhysRegDeadAtMI(V6CLANG::A, MI, *BB, TRI)) {
        int64_t TrueImm  = TrueDef->getOperand(1).getImm();
        int64_t FalseImm = FalseDef->getOperand(1).getImm();

        MachineBasicBlock *FalseBBNew = MF->CreateMachineBasicBlock();
        MachineBasicBlock *TrueBBNew  = MF->CreateMachineBasicBlock();
        MachineBasicBlock *SinkBB     = MF->CreateMachineBasicBlock();
        MachineFunction::iterator It = ++BB->getIterator();
        MF->insert(It, FalseBBNew);
        MF->insert(It, TrueBBNew);
        MF->insert(It, SinkBB);

        SinkBB->splice(SinkBB->begin(), BB,
                       std::next(MachineBasicBlock::iterator(MI)), BB->end());
        SinkBB->transferSuccessorsAndUpdatePHIs(BB);

        // Erase the original MVIr defs from BB (single-use, only the select).
        TrueDef->eraseFromParent();
        FalseDef->eraseFromParent();

        // BB: un-inverted branch to TrueBBNew; fall through to FalseBBNew.
        unsigned JccOpc;
        switch (CC) {
        default: llvm_unreachable("Unknown V6CLANG condition code");
        case V6ClangCC::COND_NZ: JccOpc = V6CLANG::JNZ; break;
        case V6ClangCC::COND_Z:  JccOpc = V6CLANG::JZ;  break;
        case V6ClangCC::COND_NC: JccOpc = V6CLANG::JNC; break;
        case V6ClangCC::COND_C:  JccOpc = V6CLANG::JC;  break;
        case V6ClangCC::COND_PO: JccOpc = V6CLANG::JPO; break;
        case V6ClangCC::COND_PE: JccOpc = V6CLANG::JPE; break;
        case V6ClangCC::COND_P:  JccOpc = V6CLANG::JP;  break;
        case V6ClangCC::COND_M:  JccOpc = V6CLANG::JM;  break;
        }
        BuildMI(BB, DL, TII.get(JccOpc)).addMBB(TrueBBNew);
        BB->addSuccessor(FalseBBNew);
        BB->addSuccessor(TrueBBNew);

        // FalseBB: materialize false arm into A, then jump to SinkBB.
        BuildMI(FalseBBNew, DL, TII.get(V6CLANG::MVIr), V6CLANG::A).addImm(FalseImm);
        BuildMI(FalseBBNew, DL, TII.get(V6CLANG::JMP)).addMBB(SinkBB);
        FalseBBNew->addSuccessor(SinkBB);

        // TrueBB: materialize true arm into A; fall through to SinkBB.
        BuildMI(TrueBBNew, DL, TII.get(V6CLANG::MVIr), V6CLANG::A).addImm(TrueImm);
        TrueBBNew->addSuccessor(SinkBB);

        // SinkBB: COPY physreg A → vreg DstReg (RegisterCoalescer eliminates).
        SinkBB->addLiveIn(V6CLANG::A);
        BuildMI(*SinkBB, SinkBB->begin(), DL,
                TII.get(TargetOpcode::COPY), DstReg)
            .addReg(V6CLANG::A, RegState::Kill);

        MI.eraseFromParent();
        return SinkBB;
      }
    }

    // General case: 3-block diamond with PHI.
    MachineBasicBlock *TrueBB = MF->CreateMachineBasicBlock();
    MachineBasicBlock *SinkBB = MF->CreateMachineBasicBlock();

    MachineFunction::iterator It = ++BB->getIterator();
    MF->insert(It, TrueBB);
    MF->insert(It, SinkBB);

    // Transfer successors and remaining instructions to SinkBB.
    SinkBB->splice(SinkBB->begin(), BB,
                   std::next(MachineBasicBlock::iterator(MI)), BB->end());
    SinkBB->transferSuccessorsAndUpdatePHIs(BB);

    // BB: emit inverted conditional branch to SinkBB (false path).
    // Layout is BB → TrueBB → SinkBB, so TrueBB is the fallthrough.
    // Branch on the INVERTED condition to SinkBB; fall through to TrueBB.
    unsigned InvJccOpc;
    switch (CC) {
    default: llvm_unreachable("Unknown V6CLANG condition code");
    case V6ClangCC::COND_NZ: InvJccOpc = V6CLANG::JZ;  break;
    case V6ClangCC::COND_Z:  InvJccOpc = V6CLANG::JNZ; break;
    case V6ClangCC::COND_NC: InvJccOpc = V6CLANG::JC;  break;
    case V6ClangCC::COND_C:  InvJccOpc = V6CLANG::JNC; break;
    case V6ClangCC::COND_PO: InvJccOpc = V6CLANG::JPE; break;
    case V6ClangCC::COND_PE: InvJccOpc = V6CLANG::JPO; break;
    case V6ClangCC::COND_P:  InvJccOpc = V6CLANG::JM;  break;
    case V6ClangCC::COND_M:  InvJccOpc = V6CLANG::JP;  break;
    }

    BuildMI(BB, DL, TII.get(InvJccOpc)).addMBB(SinkBB);
    BB->addSuccessor(TrueBB);
    BB->addSuccessor(SinkBB);

    // TrueBB: just falls through to SinkBB (value comes from TrueReg).
    TrueBB->addSuccessor(SinkBB);

    // SinkBB: PHI node merges TrueReg and FalseReg.
    BuildMI(*SinkBB, SinkBB->begin(), DL, TII.get(TargetOpcode::PHI), DstReg)
        .addReg(TrueReg).addMBB(TrueBB)
        .addReg(FalseReg).addMBB(BB);

    MI.eraseFromParent();
    return SinkBB;
  }
  }
}

//===----------------------------------------------------------------------===//
// Inline assembly support
//===----------------------------------------------------------------------===//

TargetLowering::ConstraintType
V6ClangTargetLowering::getConstraintType(StringRef Constraint) const {
  if (Constraint.size() == 1) {
    switch (Constraint[0]) {
    case 'a': // Accumulator (A)
    case 'r': // Any 8-bit GPR
    case 'p': // 16-bit register pair
      return C_RegisterClass;
    case 'I': // 8-bit unsigned immediate
    case 'J': // 16-bit unsigned immediate
      return C_Immediate;
    default:
      break;
    }
  }
  return TargetLowering::getConstraintType(Constraint);
}

std::pair<unsigned, const TargetRegisterClass *>
V6ClangTargetLowering::getRegForInlineAsmConstraint(
    const TargetRegisterInfo *TRI, StringRef Constraint, MVT VT) const {
  if (Constraint.size() == 1) {
    switch (Constraint[0]) {
    case 'a': // Accumulator
      return std::make_pair(V6CLANG::A, &V6CLANG::AccRegClass);
    case 'r': // Any 8-bit GPR
      if (VT == MVT::i16)
        return std::make_pair(0U, &V6CLANG::GR16RegClass);
      return std::make_pair(0U, &V6CLANG::GR8RegClass);
    case 'p': // 16-bit register pair
      return std::make_pair(0U, &V6CLANG::GR16RegClass);
    default:
      break;
    }
  }
  return TargetLowering::getRegForInlineAsmConstraint(TRI, Constraint, VT);
}
