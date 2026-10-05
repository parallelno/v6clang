//===-- V6ClangISelDAGToDAG.cpp - V6CLANG DAG->DAG instruction selection -----------===//
//
// Part of the V6CLANG backend for LLVM.
//
// M5: Frame Lowering & Calling Convention.
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "V6ClangISelLowering.h"
#include "V6ClangSubtarget.h"
#include "V6ClangTargetMachine.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "llvm/CodeGen/SelectionDAGISel.h"
#include "llvm/Support/CommandLine.h"

using namespace llvm;

#define DEBUG_TYPE "v6clang-isel"

namespace {

class V6ClangDAGToDAGISel : public SelectionDAGISel {
  static char ID;

public:
  V6ClangDAGToDAGISel(V6ClangTargetMachine &TM, CodeGenOptLevel OptLevel)
      : SelectionDAGISel(ID, TM, OptLevel) {}

  StringRef getPassName() const override {
    return "V6CLANG DAG->DAG Instruction Selection";
  }

  void Select(SDNode *N) override;

  // TableGen-generated code.
  #include "V6ClangGenDAGISel.inc"
};

char V6ClangDAGToDAGISel::ID = 0;

void V6ClangDAGToDAGISel::Select(SDNode *N) {
  // If already selected, do nothing.
  if (N->isMachineOpcode()) {
    N->setNodeId(-1);
    return;
  }

  SDLoc DL(N);
  unsigned Opc = N->getOpcode();

  switch (Opc) {
  default:
    break;

  case ISD::LOAD: {
    auto *LD = cast<LoadSDNode>(N);
    if (LD->getExtensionType() != ISD::NON_EXTLOAD)
      break;
    MVT VT = LD->getSimpleValueType(0);
    if (VT != MVT::i8 && VT != MVT::i16)
      break;
    auto *FI = dyn_cast<FrameIndexSDNode>(LD->getBasePtr());
    if (!FI)
      break;

    SDValue TFI = CurDAG->getTargetFrameIndex(FI->getIndex(), MVT::i16);
    SmallVector<SDValue, 2> Ops = {TFI, LD->getChain()};
    unsigned LoadOpc = (VT == MVT::i8) ? V6CLANG::V6CLANG_LOAD8_FI
                                       : V6CLANG::V6CLANG_LOAD16_FI;
    SDNode *Load = CurDAG->getMachineNode(
        LoadOpc, DL, CurDAG->getVTList(VT, MVT::Other), Ops);
    CurDAG->setNodeMemRefs(cast<MachineSDNode>(Load), {LD->getMemOperand()});
    ReplaceNode(N, Load);
    return;
  }

  case ISD::STORE: {
    auto *ST = cast<StoreSDNode>(N);
    if (ST->isTruncatingStore())
      break;
    MVT VT = ST->getMemoryVT().getSimpleVT();
    if (VT != MVT::i8 && VT != MVT::i16)
      break;
    auto *FI = dyn_cast<FrameIndexSDNode>(ST->getBasePtr());
    if (!FI)
      break;

    SDValue TFI = CurDAG->getTargetFrameIndex(FI->getIndex(), MVT::i16);
    SmallVector<SDValue, 3> Ops = {ST->getValue(), TFI, ST->getChain()};
    unsigned StoreOpc = (VT == MVT::i8) ? V6CLANG::V6CLANG_STORE8_FI
                                        : V6CLANG::V6CLANG_STORE16_FI;
    SDNode *Store = CurDAG->getMachineNode(StoreOpc, DL, MVT::Other, Ops);
    CurDAG->setNodeMemRefs(cast<MachineSDNode>(Store), {ST->getMemOperand()});
    ReplaceNode(N, Store);
    return;
  }

  case ISD::FrameIndex: {
    int FI = cast<FrameIndexSDNode>(N)->getIndex();
    SDValue TFI = CurDAG->getTargetFrameIndex(FI, MVT::i16);
    ReplaceNode(N, CurDAG->getMachineNode(V6CLANG::V6CLANG_LEA_FI, DL,
                                           MVT::i16, TFI));
    return;
  }

  case ISD::CALLSEQ_START: {
    SDValue Amt  = N->getOperand(1);
    SDValue Amt2 = N->getOperand(2);
    SDValue Chain = N->getOperand(0);
    SmallVector<SDValue, 4> Ops = {Amt, Amt2, Chain};
    ReplaceNode(N, CurDAG->getMachineNode(V6CLANG::ADJCALLSTACKDOWN, DL,
                                           MVT::Other, MVT::Glue, Ops));
    return;
  }

  case ISD::CALLSEQ_END: {
    SmallVector<SDValue, 4> Ops;
    Ops.push_back(N->getOperand(1)); // Amt
    Ops.push_back(N->getOperand(2)); // Amt2
    Ops.push_back(N->getOperand(0)); // Chain
    // Optional incoming glue.
    if (N->getNumOperands() > 3 &&
        N->getOperand(N->getNumOperands() - 1).getValueType() == MVT::Glue)
      Ops.push_back(N->getOperand(N->getNumOperands() - 1));
    ReplaceNode(N, CurDAG->getMachineNode(V6CLANG::ADJCALLSTACKUP, DL,
                                           MVT::Other, MVT::Glue, Ops));
    return;
  }

  case V6ClangISD::CALL: {
    // CALL node operands: chain, callee, [implicit reg uses...], RegisterMask, [glue]
    SDValue Chain  = N->getOperand(0);
    SDValue Callee = N->getOperand(1);

    SmallVector<SDValue, 8> Ops;
    Ops.push_back(Callee);

    // Copy implicit register uses and RegisterMask (skip chain and callee,
    // and skip trailing glue if present).
    unsigned NumOps = N->getNumOperands();
    bool HasGlue = N->getOperand(NumOps - 1).getValueType() == MVT::Glue;
    unsigned End = HasGlue ? NumOps - 1 : NumOps;
    for (unsigned i = 2; i < End; ++i)
      Ops.push_back(N->getOperand(i));

    // Chain, then optional glue.
    Ops.push_back(Chain);
    if (HasGlue)
      Ops.push_back(N->getOperand(NumOps - 1));

    SDNode *Call = CurDAG->getMachineNode(
        V6CLANG::CALL, DL, MVT::Other, MVT::Glue, Ops);
    ReplaceNode(N, Call);
    return;
  }

  case V6ClangISD::BR_CC16: {
    // Fused 16-bit compare + branch.
    // Operands: chain, lhs(i16), rhs(i16), cc(i8), dest(bb)
    SDValue Chain = N->getOperand(0);
    SDValue LHS   = N->getOperand(1);
    SDValue RHS   = N->getOperand(2);
    SDValue CC    = N->getOperand(3);
    SDValue Dest  = N->getOperand(4);

    // Check if RHS (or LHS) is a constant or wrapped global address.
    // If so, use V6CLANG_BR_CC16_IMM to avoid allocating a register pair.
    unsigned Opc = V6CLANG::V6CLANG_BR_CC16;
    SDValue RhsOp = RHS;

    auto CCVal = cast<ConstantSDNode>(CC)->getZExtValue();

    // EQ/NE: constant on RHS → use IMM variant directly.
    if (CCVal == V6ClangCC::COND_Z || CCVal == V6ClangCC::COND_NZ) {
      if (RHS.getOpcode() == V6ClangISD::Wrapper &&
          (isa<GlobalAddressSDNode>(RHS.getOperand(0)) ||
           isa<ExternalSymbolSDNode>(RHS.getOperand(0)))) {
        Opc = V6CLANG::V6CLANG_BR_CC16_IMM;
        RhsOp = RHS.getOperand(0);
      } else if (auto *C = dyn_cast<ConstantSDNode>(RHS)) {
        Opc = V6CLANG::V6CLANG_BR_CC16_IMM;
        RhsOp = CurDAG->getTargetConstant(C->getSExtValue(), DL, MVT::i16);
      }
    }

    // O24: Ordering conditions (C/NC/M/P) with immediate operand.
    // MVI+SUB/SBB doesn't need a register pair for the constant.
    if (CCVal == V6ClangCC::COND_C || CCVal == V6ClangCC::COND_NC ||
        CCVal == V6ClangCC::COND_M || CCVal == V6ClangCC::COND_P) {
      // Case A: Constant on LHS (from GT/LE swap in LowerBR_CC).
      // MVI+SUB computes const-reg, which matches the register path's
      // direction after the swap. Keep CC unchanged.
      if (auto *CL = dyn_cast<ConstantSDNode>(LHS)) {
        Opc = V6CLANG::V6CLANG_BR_CC16_IMM;
        RhsOp = CurDAG->getTargetConstant(CL->getSExtValue(), DL, MVT::i16);
        LHS = RHS; // register becomes $lhs
      } else if (LHS.getOpcode() == V6ClangISD::Wrapper &&
                 (isa<GlobalAddressSDNode>(LHS.getOperand(0)) ||
                  isa<ExternalSymbolSDNode>(LHS.getOperand(0)))) {
        Opc = V6CLANG::V6CLANG_BR_CC16_IMM;
        RhsOp = LHS.getOperand(0);
        LHS = RHS;
      }
      // Case B: Constant on RHS (natural ULT/UGE/SLT/SGE).
      // MVI+SUB computes const-reg but register path computes reg-const.
      // Adjust: K → K-1, invert CC (C↔NC, M↔P).
      else if (auto *CR = dyn_cast<ConstantSDNode>(RHS)) {
        int64_t K = CR->getSExtValue();
        bool IsUnsigned = (CCVal == V6ClangCC::COND_C || CCVal == V6ClangCC::COND_NC);
        // Guard: K=0 (unsigned) or K=0x8000 (signed) would underflow.
        bool CanAdjust = IsUnsigned ? ((K & 0xFFFF) != 0)
                                    : ((K & 0xFFFF) != 0x8000);
        if (CanAdjust) {
          Opc = V6CLANG::V6CLANG_BR_CC16_IMM;
          int64_t Km1 = (K - 1) & 0xFFFF;
          RhsOp = CurDAG->getTargetConstant(Km1, DL, MVT::i16);
          // Invert CC: C↔NC, M↔P
          unsigned NewCC;
          switch (CCVal) {
          case V6ClangCC::COND_C:  NewCC = V6ClangCC::COND_NC; break;
          case V6ClangCC::COND_NC: NewCC = V6ClangCC::COND_C;  break;
          case V6ClangCC::COND_M:  NewCC = V6ClangCC::COND_P;  break;
          case V6ClangCC::COND_P:  NewCC = V6ClangCC::COND_M;  break;
          default: llvm_unreachable("unexpected CC");
          }
          CC = CurDAG->getTargetConstant(NewCC, DL, MVT::i8);
        }
      } else if (RHS.getOpcode() == V6ClangISD::Wrapper &&
                 isa<GlobalAddressSDNode>(RHS.getOperand(0))) {
        // Global address on RHS: adjust offset by -1.
        auto *GA = cast<GlobalAddressSDNode>(RHS.getOperand(0));
        int64_t Offset = GA->getOffset();
        if (Offset != 0 || true) { // Always valid for globals (address > 0)
          Opc = V6CLANG::V6CLANG_BR_CC16_IMM;
          RhsOp = CurDAG->getTargetGlobalAddress(
              GA->getGlobal(), DL, MVT::i16, Offset - 1);
          unsigned NewCC;
          switch (CCVal) {
          case V6ClangCC::COND_C:  NewCC = V6ClangCC::COND_NC; break;
          case V6ClangCC::COND_NC: NewCC = V6ClangCC::COND_C;  break;
          case V6ClangCC::COND_M:  NewCC = V6ClangCC::COND_P;  break;
          case V6ClangCC::COND_P:  NewCC = V6ClangCC::COND_M;  break;
          default: llvm_unreachable("unexpected CC");
          }
          CC = CurDAG->getTargetConstant(NewCC, DL, MVT::i8);
        }
      }
    }

    SmallVector<SDValue, 5> Ops;
    Ops.push_back(LHS);
    Ops.push_back(RhsOp);
    Ops.push_back(CC);
    Ops.push_back(Dest);
    Ops.push_back(Chain);

    SDVTList VTs = CurDAG->getVTList(MVT::Other);
    SDNode *BrCC = CurDAG->getMachineNode(Opc, DL, VTs, Ops);
    ReplaceNode(N, BrCC);
    return;
  }

  case ISD::BUILD_PAIR: {
    // Combine two i8 values into an i16 register pair.
    SDValue Lo = N->getOperand(0);
    SDValue Hi = N->getOperand(1);
    SDNode *Pair = CurDAG->getMachineNode(V6CLANG::V6CLANG_BUILD_PAIR, DL,
                                           MVT::i16, Lo, Hi);
    ReplaceNode(N, Pair);
    return;
  }

  case V6ClangISD::CMP: {
    // O24: For i16 comparisons with constant/global RHS, use V6CLANG_CMP16_IMM
    // to avoid allocating a register pair. The K→K-1 + CC inversion was
    // already done in LowerSELECT_CC.
    //
    // O75 Phase A: V6ClangISD::CMP now produces FLAGS as an SSA-typed i8
    // value (not glue). Emit V6CLANG_CMP16_IMM (which implicit-defs FLAGS),
    // glue it to a CopyFromReg(FLAGS, MVT::i8) so that consumers of the
    // i8 FLAGS value are correctly fed.
    SDValue LHS = N->getOperand(0);
    SDValue RHS = N->getOperand(1);

    auto emitCmp16Imm = [&](SDValue ImmOp) {
      SDNode *CmpImm = CurDAG->getMachineNode(V6CLANG::V6CLANG_CMP16_IMM, DL,
                                                MVT::Glue, LHS, ImmOp);
      SDValue Flags = CurDAG->getCopyFromReg(CurDAG->getEntryNode(), DL,
                                              V6CLANG::FLAGS, MVT::i8,
                                              SDValue(CmpImm, 0));
      ReplaceUses(SDValue(N, 0), Flags);
      CurDAG->RemoveDeadNode(N);
    };

    if (LHS.getValueType() == MVT::i16) {
      if (auto *C = dyn_cast<ConstantSDNode>(RHS)) {
        SDValue ImmOp = CurDAG->getTargetConstant(C->getSExtValue(), DL,
                                                    MVT::i16);
        emitCmp16Imm(ImmOp);
        return;
      }
      if (RHS.getOpcode() == V6ClangISD::Wrapper &&
          (isa<GlobalAddressSDNode>(RHS.getOperand(0)) ||
           isa<ExternalSymbolSDNode>(RHS.getOperand(0)))) {
        emitCmp16Imm(RHS.getOperand(0));
        return;
      }
    }
    break;
  }
  }

  // Try TableGen patterns.
  SelectCode(N);
}

} // namespace

namespace llvm {

FunctionPass *createV6ClangISelDag(V6ClangTargetMachine &TM,
                                CodeGenOptLevel OptLevel) {
  return new V6ClangDAGToDAGISel(TM, OptLevel);
}

} // namespace llvm
