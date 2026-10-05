//===-- V6ClangISelLowering.h - V6CLANG DAG Lowering Interface ----------*- C++ -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
// M4: i8 Operations & Basic Lowering.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_V6CLANG_V6ClangISELLOWERING_H
#define LLVM_LIB_TARGET_V6CLANG_V6ClangISELLOWERING_H

#include "llvm/CodeGen/SelectionDAG.h"
#include "llvm/CodeGen/TargetLowering.h"

namespace llvm {

namespace V6ClangISD {
enum NodeType : unsigned {
  FIRST_NUMBER = ISD::BUILTIN_OP_END,
  RET,        // Return from function (with optional glue).
  CALL,       // Function call.
  CMP,        // Compare two values, produces FLAGS as SSA-typed i8.
  CMP_ZERO,   // Zero-test a single i16 value, produces FLAGS as i8.
  CMP_SIGN,   // Sign-test a single i16 value, produces FLAGS as i8.
  BRCOND,     // Conditional branch on FLAGS (FLAGS as last i8 operand).
  SELECT_CC,  // Conditional select on FLAGS (FLAGS as last i8 operand).
  Wrapper,    // GlobalAddress / ExternalSymbol wrapper.
  BR_CC16,    // Fused 16-bit compare + conditional branch.
  SEXT,       // Sign-extend i8 to i16 (pseudo, expands to RLC+SBB).
  NEG8,       // Result-only i8 negate from canonical sub 0, x.
  SHL16_DAD,      // Logical left shift i16 via repeated DAD H.
  SHL16_BYTE,     // Logical left shift i16 by 8 via byte-lane move.
  SHL16_RAM_HI,   // Logical left shift i16 via A-domain byte specialization.
  SRL16_RAR,      // Logical right shift i16 via per-bit RAR loop.
  SRL16_24BIT,    // Logical right shift i16 via the 24-bit DAD/ADC trick.
  SRL16_BYTE,     // Logical right shift i16 by 8 via byte-lane move.
  SRL16_RAM_LO,   // Logical right shift i16 via rotate-and-mask.
  SRA16_RAR,      // Arithmetic right shift i16 via per-bit RAR loop.
  SRA16_24BIT,    // Arithmetic right shift i16 via sign-seeded 24-bit trick.
  SRA16_BYTE,     // Arithmetic right shift i16 by 8 via byte/sign move.
  SRA16_RAM_LO,   // Arithmetic right shift i16 via rotate-and-mask.
  DAD,        // 16-bit add constrained to HL (maps to DAD rp).
  INX16,      // 16-bit increment by immediate count (1..3), no flag set.
  DCX16,      // 16-bit decrement by immediate count (1..3), no flag set.
  ROTL8,      // 1-bit accumulator rotate left  (RLC).
  ROTR8,      // 1-bit accumulator rotate right (RRC).
  ROTL16_1,   // i16 rotate-left by 1, lowered via DAD H + ACI 0 carry-fold
              // (O68 Phase 2). Single-result, HL-constrained at the pseudo
              // level. CY chains internally inside the post-RA expansion.

  // O75 Phase B: flag-producing arithmetic SDNodes. Each returns
  // (i8 value, i8 flags). Pattern-bound to the same machine instructions
  // as the plain ISD ops, but the second result (FLAGS) is exposed so a
  // downstream BR_CC/SELECT_CC can consume the flags directly without
  // emitting a redundant CMP/CPI.
  //
  // Keep this range contiguous and end with DECF — `LowerBR_CC`'s
  // short-circuit relies on a [ADDF, DECF] range check.
  ADDF,        // (val, flags) = ADDF(lhs, rhs)        — register form.
  SUBF,        // (val, flags) = SUBF(lhs, rhs)
  ANDF,        // (val, flags) = ANDF(lhs, rhs)
  ORF,         // (val, flags) = ORF(lhs, rhs)
  XORF,        // (val, flags) = XORF(lhs, rhs)
  ADDF_IMM,    // (val, flags) = ADDF_IMM(lhs, i8 imm) — immediate form.
  SUBF_IMM,    // (val, flags) = SUBF_IMM(lhs, i8 imm)
  ANDF_IMM,    // (val, flags) = ANDF_IMM(lhs, i8 imm)
  ORF_IMM,     // (val, flags) = ORF_IMM(lhs, i8 imm)
  XORF_IMM,    // (val, flags) = XORF_IMM(lhs, i8 imm)
  INCF,        // (val, flags) = INCF(src)             — INR r.
  DECF,        // (val, flags) = DECF(src)             — DCR r.
};
} // namespace V6ClangISD

// V6CLANG condition codes matching 8080 Jcc/Ccc/Rcc 3-bit encoding.
namespace V6ClangCC {
enum CondCode : unsigned {
  COND_NZ = 0, // Not zero
  COND_Z  = 1, // Zero
  COND_NC = 2, // No carry
  COND_C  = 3, // Carry
  COND_PO = 4, // Parity odd
  COND_PE = 5, // Parity even
  COND_P  = 6, // Plus (positive)
  COND_M  = 7, // Minus (negative)
};
} // namespace V6ClangCC

class V6ClangSubtarget;
class V6ClangTargetMachine;

class V6ClangTargetLowering : public TargetLowering {
public:
  explicit V6ClangTargetLowering(const V6ClangTargetMachine &TM,
                              const V6ClangSubtarget &STI);

  const char *getTargetNodeName(unsigned Opcode) const override;

  SDValue LowerOperation(SDValue Op, SelectionDAG &DAG) const override;

  MachineBasicBlock *
  EmitInstrWithCustomInserter(MachineInstr &MI,
                              MachineBasicBlock *BB) const override;

  EVT getSetCCResultType(const DataLayout &DL, LLVMContext &C,
                         EVT VT) const override;

  /// i8080 has no barrel shifter; multi-bit shifts are still expensive even
  /// with the strategy-specific post-RA families. Suppress
  /// DAGCombiner folds that rewrite `(x & pow2) ? C : 0` style selects into
  /// shift+and idioms, because the resulting wide shift is dramatically more
  /// expensive than the branch produced by LowerSELECT_CC.
  bool shouldAvoidTransformToShift(EVT VT, unsigned Amount) const override {
    if (VT == MVT::i8 || VT == MVT::i16)
      return Amount >= 2;
    return false;
  }

private:
  SDValue LowerFormalArguments(SDValue Chain, CallingConv::ID CallConv,
                               bool isVarArg,
                               const SmallVectorImpl<ISD::InputArg> &Ins,
                               const SDLoc &DL, SelectionDAG &DAG,
                               SmallVectorImpl<SDValue> &InVals) const override;

  SDValue LowerReturn(SDValue Chain, CallingConv::ID CallConv, bool isVarArg,
                      const SmallVectorImpl<ISD::OutputArg> &Outs,
                      const SmallVectorImpl<SDValue> &OutVals, const SDLoc &DL,
                      SelectionDAG &DAG) const override;

  SDValue LowerCall(TargetLowering::CallLoweringInfo &CLI,
                    SmallVectorImpl<SDValue> &InVals) const override;

  SDValue LowerGlobalAddress(SDValue Op, SelectionDAG &DAG) const;
  SDValue LowerExternalSymbol(SDValue Op, SelectionDAG &DAG) const;
  SDValue LowerBR_CC(SDValue Op, SelectionDAG &DAG) const;
  SDValue LowerSELECT_CC(SDValue Op, SelectionDAG &DAG) const;
  SDValue LowerSHL(SDValue Op, SelectionDAG &DAG) const;
  SDValue LowerSRL(SDValue Op, SelectionDAG &DAG) const;
  SDValue LowerSRA(SDValue Op, SelectionDAG &DAG) const;
  SDValue LowerSHL_i16(SDValue Op, SelectionDAG &DAG) const;
  SDValue LowerSRL_i16(SDValue Op, SelectionDAG &DAG) const;
  SDValue LowerSRA_i16(SDValue Op, SelectionDAG &DAG) const;
  SDValue LowerROTL(SDValue Op, SelectionDAG &DAG) const;
  SDValue LowerROTR(SDValue Op, SelectionDAG &DAG) const;
  SDValue LowerZERO_EXTEND(SDValue Op, SelectionDAG &DAG) const;
  SDValue LowerSIGN_EXTEND(SDValue Op, SelectionDAG &DAG) const;
  SDValue LowerANY_EXTEND(SDValue Op, SelectionDAG &DAG) const;

  // O75 Phase B: lower i8 ADD/SUB/AND/OR/XOR to flag-producing *F nodes.
  SDValue LowerArithF(SDValue Op, SelectionDAG &DAG) const;

  SDValue PerformDAGCombine(SDNode *N,
                            DAGCombinerInfo &DCI) const override;

  // Inline assembly support.
  ConstraintType getConstraintType(StringRef Constraint) const override;
  std::pair<unsigned, const TargetRegisterClass *>
  getRegForInlineAsmConstraint(const TargetRegisterInfo *TRI,
                               StringRef Constraint, MVT VT) const override;
};

} // namespace llvm

#endif // LLVM_LIB_TARGET_V6CLANG_V6ClangISELLOWERING_H
