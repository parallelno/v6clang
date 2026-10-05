//===-- V6ClangRedundantFlagElim.cpp - Remove redundant ORA A / ANA A ---------===//
//
// Part of the V6CLANG backend for LLVM.
//
// Post-RA peephole: Remove ORA A (or ANA A) when the Z flag already reflects
// A's value from a preceding ALU instruction.  Both ORA A and ANA A are
// identity operations (A = A | A = A, A = A & A = A) used solely to set
// flags.  If a prior instruction already wrote A AND set FLAGS, the Z flag
// is still valid and the ORA A / ANA A is provably redundant.
//
// O91 extension: also eliminate the V6CLANG_CMP8_ZERO shape-2 expansion
// (XRA A; CMP R) when R is known to hold A's value from the last
// flag-setting ALU op and ZFlagValid is true.  The typical pattern after
// O89 (dead hi-byte elision):
//
//   <ALU op>          ; A = result; Z = (result==0) -- ZFlagValid=true
//   MOV R, A          ; R = result; FLAGS untouched
//   XRA A             ; ← start of CMP8_ZERO shape 2 -- REDUNDANT
//   CMP R             ; ← REDUNDANT
//
// Track which registers hold A's last ALU value (AValueRegs) and erase
// the triple MOV R,A + XRA A + CMP R when the conditions are met.
//
// Algorithm (per basic block, no inter-BB analysis):
//   ZFlagValid = false;  AValueRegs = {};  AValueSrc = {}
//   for each MI:
//     O17: if ZFlagValid && (ORA A || ANA A): erase
//     O91: if ZFlagValid && XRA A && next is CMP R && R in AValueRegs:
//              erase MOV R,A bridge, XRA A, CMP R
//     update ZFlagValid:
//       ALU writes A+FLAGS → true; clear+refill AValueRegs with {A}
//       MOV R,A while ZFlagValid → add R to AValueRegs
//       writes A w/o FLAGS || writes FLAGS w/o A || ctrl-flow → false; clear
//
//===----------------------------------------------------------------------===/

#include "V6Clang.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallSet.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/Support/CommandLine.h"

using namespace llvm;

#define DEBUG_TYPE "v6clang-redundant-flag-elim"

static cl::opt<bool> DisableRedundantFlagElim(
    "v6clang-disable-redundant-flag-elim",
    cl::desc("Disable V6CLANG redundant ORA A / ANA A elimination"),
    cl::init(false), cl::Hidden);

namespace {

class V6ClangRedundantFlagElim : public MachineFunctionPass {
public:
  static char ID;
  V6ClangRedundantFlagElim() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Redundant Flag-Setting Elimination";
  }

  bool runOnMachineFunction(MachineFunction &MF) override;

private:
  /// Return true if MI is ORA A (identity OR on accumulator).
  static bool isOraA(const MachineInstr &MI) {
    if (MI.getOpcode() != V6CLANG::ORAr)
      return false;
    // ORAr operands: (outs Acc:$dst), (ins Acc:$lhs, GR8:$rs)
    // ORA A means $rs is A.
    return MI.getOperand(2).getReg() == V6CLANG::A;
  }

  /// Return true if MI is ANA A (identity AND on accumulator).
  static bool isAnaA(const MachineInstr &MI) {
    if (MI.getOpcode() != V6CLANG::ANAr)
      return false;
    // ANAr operands: (outs Acc:$dst), (ins Acc:$lhs, GR8:$rs)
    // ANA A means $rs is A.
    return MI.getOperand(2).getReg() == V6CLANG::A;
  }

  /// Return true if MI is an ALU instruction that writes A AND sets FLAGS.
  /// After such an instruction, Z reflects A's value → ZFlagValid = true.
  static bool isAluWritesAAndFlags(const MachineInstr &MI) {
    switch (MI.getOpcode()) {
    // Register-source ALU ops (A = A op r, sets FLAGS)
    case V6CLANG::ADDr:
    case V6CLANG::ADCr:
    case V6CLANG::SUBr:
    case V6CLANG::SBBr:
    case V6CLANG::ANAr:
    case V6CLANG::XRAr:
    case V6CLANG::ORAr:
    // Memory-source ALU ops (A = A op [HL], sets FLAGS)
    case V6CLANG::ADDM:
    case V6CLANG::ADCM:
    case V6CLANG::SUBM:
    case V6CLANG::SBBM:
    case V6CLANG::ANAM:
    case V6CLANG::XRAM:
    case V6CLANG::ORAM:
    // Immediate ALU ops (A = A op imm, sets FLAGS)
    case V6CLANG::ADI:
    case V6CLANG::ACI:
    case V6CLANG::SUI:
    case V6CLANG::SBI:
    case V6CLANG::ANI:
    case V6CLANG::XRI:
    case V6CLANG::ORI:
      return true;

    // INR/DCR with dst=A: writes A and sets FLAGS (except CY, but Z is set)
    case V6CLANG::INRr:
    case V6CLANG::DCRr:
      return MI.getOperand(0).getReg() == V6CLANG::A;

    default:
      return false;
    }
  }

  /// Return true if MI writes A without setting FLAGS.
  /// After such an instruction, A's value changed but Z is stale.
  static bool isWritesANoFlags(const MachineInstr &MI) {
    switch (MI.getOpcode()) {
    // MOV A, r / MOV A, M / MVI A, imm / LDA addr / LDAX rp / POP PSW
    case V6CLANG::MOVrr:
      return MI.getOperand(0).getReg() == V6CLANG::A;
    case V6CLANG::MOVrM:
      return MI.getOperand(0).getReg() == V6CLANG::A;
    case V6CLANG::MVIr:
      return MI.getOperand(0).getReg() == V6CLANG::A;
    case V6CLANG::LDA:
      return true; // Always writes A
    case V6CLANG::LDAX:
      return true; // Always writes A
    default:
      break;
    }

    // POP PSW writes both A and FLAGS, but the Z flag after POP PSW
    // reflects the saved flags, not necessarily A's new value.
    // Conservatively invalidate.
    if (MI.getOpcode() == V6CLANG::POP) {
      Register Reg = MI.getOperand(0).getReg();
      return Reg == V6CLANG::PSW;
    }

    return false;
  }

  /// Return true if MI modifies FLAGS without writing A.
  /// After such an instruction, Z no longer reflects A.
  static bool isWritesFlagsNoA(const MachineInstr &MI) {
    switch (MI.getOpcode()) {
    // INR/DCR on non-A register: sets FLAGS, doesn't touch A
    case V6CLANG::INRr:
    case V6CLANG::DCRr:
      return MI.getOperand(0).getReg() != V6CLANG::A;

    // INR M / DCR M: sets FLAGS, doesn't touch A
    case V6CLANG::INRM:
    case V6CLANG::DCRM:
      return true;

    // DAD: sets CY flag (and on real 8080, only CY — but we model Defs=[FLAGS])
    case V6CLANG::DAD:
      return true;

    // CMP/CMPM/CPI: set FLAGS based on A-operand comparison, don't write A.
    // Z reflects comparison result, not A's own value.
    case V6CLANG::CMPr:
    case V6CLANG::CMPM:
    case V6CLANG::CPI:
      return true;

    // Rotate instructions: modify A and set CY
    // These both write A AND set FLAGS, but only CY — Z is unchanged on 8080.
    // However, our TableGen models them as Defs=[FLAGS], so conservatively
    // treat as FLAGS-modifying.
    case V6CLANG::RLC:
    case V6CLANG::RRC:
    case V6CLANG::RAL:
    case V6CLANG::RAR:
      return true;

    // STC/CMC: only affect CY
    case V6CLANG::STC:
    case V6CLANG::CMC:
      return true;

    default:
      return false;
    }
  }

  /// Return true if MI is a control flow instruction (branch/call/return).
  static bool isControlFlow(const MachineInstr &MI) {
    return MI.isCall() || MI.isReturn() || MI.isBranch();
  }

  /// Return true if MI is XRA A (XOR accumulator with itself — zero A).
  static bool isXraA(const MachineInstr &MI) {
    if (MI.getOpcode() != V6CLANG::XRAr)
      return false;
    // XRAr: (outs Acc:$dst), (ins Acc:$lhs, GR8:$rs)
    return MI.getOperand(2).getReg() == V6CLANG::A;
  }

  /// If MI is "MOV R, A" (MOVrr with src=A, dst≠A, no patched-imm target
  /// flags), return the destination register. Otherwise return NoRegister.
  static Register getMOVrADest(const MachineInstr &MI) {
    if (MI.getOpcode() != V6CLANG::MOVrr)
      return Register();
    // MOVrr: (outs GR8:$dst), (ins GR8:$src)
    const MachineOperand &Dst = MI.getOperand(0);
    const MachineOperand &Src = MI.getOperand(1);
    if (!Dst.isReg() || !Src.isReg())
      return Register();
    if (Src.getReg() != V6CLANG::A || Dst.getReg() == V6CLANG::A)
      return Register();
    // Skip MOVs that carry a patched-imm target flag (O61 spill-patched).
    if (Src.getTargetFlags() != 0 || Dst.getTargetFlags() != 0)
      return Register();
    return Dst.getReg();
  }

  /// Return true if register R has no reads from After (exclusive) to the
  /// end of MBB and is not live-in to any successor.  Used to confirm that
  /// the MOV R,A bridge is a dead store once CMP R is removed.
  static bool isBridgeDead(Register R,
                           MachineBasicBlock::iterator After,
                           const MachineBasicBlock &MBB) {
    MachineBasicBlock::const_iterator It = std::next(After);
    MachineBasicBlock::const_iterator E = MBB.end();
    for (; It != E; ++It) {
      if (It->readsRegister(R))
        return false;
      if (It->definesRegister(R))
        return true; // redefined before any use → safe
    }
    for (const MachineBasicBlock *Succ : MBB.successors())
      if (Succ->isLiveIn(R))
        return false;
    return true;
  }
};

} // end anonymous namespace

char V6ClangRedundantFlagElim::ID = 0;

bool V6ClangRedundantFlagElim::runOnMachineFunction(MachineFunction &MF) {
  if (DisableRedundantFlagElim)
    return false;

  bool Changed = false;

  for (MachineBasicBlock &MBB : MF) {
    bool ZFlagValid = false;
    // O91: registers known to hold A's value from the last ALU op.
    SmallSet<Register, 4> AValueRegs;
    // O91: maps each register in AValueRegs to the MOV R,A that wrote it.
    DenseMap<Register, MachineInstr *> AValueSrc;

    // Manual iterator loop so we can erase look-ahead instructions (O91)
    // without invalidating the current position.
    MachineBasicBlock::iterator CurMI = MBB.begin();
    while (CurMI != MBB.end()) {
      MachineInstr &MI = *CurMI;
      MachineBasicBlock::iterator NextMI = std::next(CurMI);

      // --- O17: redundant ORA A / ANA A ---
      if (ZFlagValid && (isOraA(MI) || isAnaA(MI))) {
        MI.eraseFromParent();
        Changed = true;
        CurMI = NextMI;
        continue;
      }

      // --- O91: XRA A + CMP R where R holds A's last ALU value ---
      // Pattern: after an ALU op sets Z, code does MOV R,A then
      // V6CLANG_CMP8_ZERO shape 2 (XRA A; CMP R).  Z is already valid,
      // so the entire triple is redundant.
      if (ZFlagValid && isXraA(MI) && NextMI != MBB.end() &&
          NextMI->getOpcode() == V6CLANG::CMPr) {
        // CMPr: (outs), (ins Acc:$lhs, GR8:$rs)
        Register CmpSrc = NextMI->getOperand(1).getReg();
        if (AValueRegs.count(CmpSrc)) {
          // Confirm the bridge MOV R,A is safe to erase: R must be dead
          // after CMP R (i.e. R is not used beyond this comparison).
          MachineInstr *BridgeMI = AValueSrc.lookup(CmpSrc);
          if (!BridgeMI || isBridgeDead(CmpSrc, NextMI, MBB)) {
            // Check no pre-instr symbol on XRA A or CMP R (O61 safety).
            if (!MI.getPreInstrSymbol() && !NextMI->getPreInstrSymbol()) {
              // Save iterator past CMP R before erasing anything.
              MachineBasicBlock::iterator AfterCmp = std::next(NextMI);
              if (BridgeMI)
                BridgeMI->eraseFromParent(); // MOV R,A — dead store
              NextMI->eraseFromParent();     // CMP R
              MI.eraseFromParent();          // XRA A
              Changed = true;
              // ZFlagValid and AValueRegs remain — Z is still valid.
              CurMI = AfterCmp;
              continue;
            }
          }
        }
      }

      // --- State update ---
      if (isAluWritesAAndFlags(MI)) {
        ZFlagValid = true;
        AValueRegs.clear();
        AValueSrc.clear();
        AValueRegs.insert(V6CLANG::A); // A itself holds the fresh result
      } else if (ZFlagValid) {
        // Track MOV R, A copies that propagate the ALU result value.
        Register MovDst = getMOVrADest(MI);
        if (MovDst.isValid()) {
          AValueRegs.insert(MovDst);
          AValueSrc[MovDst] = &MI;
          CurMI = NextMI;
          continue; // do not fall into the reset path below
        }
        // Any other write to a tracked register invalidates it.
        for (const MachineOperand &MO : MI.operands()) {
          if (MO.isReg() && MO.isDef() && MO.getReg().isValid()) {
            AValueRegs.erase(MO.getReg());
            AValueSrc.erase(MO.getReg());
          }
        }
        // Writes to A or FLAGS reset everything.
        if (isWritesANoFlags(MI) || isWritesFlagsNoA(MI) || isControlFlow(MI)) {
          ZFlagValid = false;
          AValueRegs.clear();
          AValueSrc.clear();
        }
      } else if (isWritesANoFlags(MI) || isWritesFlagsNoA(MI) ||
                 isControlFlow(MI)) {
        ZFlagValid = false;
        AValueRegs.clear();
        AValueSrc.clear();
      }
      // else: instruction doesn't touch A or FLAGS → ZFlagValid unchanged

      CurMI = NextMI;
    }
  }

  return Changed;
}

FunctionPass *llvm::createV6ClangRedundantFlagElimPass() {
  return new V6ClangRedundantFlagElim();
}
