//===-- V6ClangRegValueForwarding.cpp - Cross-BB physreg value forwarding -----===//
//
// Part of the V6CLANG backend for LLVM.
//
// O92: Unified cross-BB physical-register value-forwarding pass.
//
// A single forward dataflow analysis over the post-RA MIR CFG that tracks,
// for each physical register, whether it provably holds the contents of
// another register (Reg) or a known immediate (Const).  When an instruction
// re-establishes a value the destination register already holds, the write is
// redundant and is erased.  This subsumes three older, partial, block-local
// implementations of the same idea:
//
//   * V6ClangAccumulatorPlanning::eliminateRedundantAccMoves (A-specific, local)
//   * V6ClangPeephole::eliminateRedundantMov                 (adjacent only)
//
// Unlike those, this pass reasons across basic-block edges, including loop
// back-edges, via an iterative fixpoint.  That is what lets it delete a
// `MOV A, D` reload that is loop-invariant and redundant on every iteration
// (the fannkuch / acc-park pattern) — something the local passes and upstream
// machine-cp cannot prove.
//
// Lattice (per physreg):
//
//        Top  (unknown / not in map)
//       /        \
//   Reg(R)        Const(C)
//       \        /
//        Bottom  (conflict — represented as absence after meet)
//
// Soundness notes:
//   * All "defines reg" checks and invalidations are alias-correct via
//     TargetRegisterInfo::regsOverlap, so defining D invalidates DE, writing
//     A invalidates PSW, LXI H invalidates H/L/HL, etc.
//   * O61 patched immediates (a `MVI r, 0` whose imm byte is self-modified at
//     runtime, marked by a pre-instr symbol or MO_PATCH_IMM target flag) are
//     never recorded as Const and never erased.
//   * Only MOVrr / MVIr are ever erased.  Neither defines FLAGS on the 8080,
//     so removing a redundant one cannot disturb a pending compare.
//   * `ORA A` / `ANA A` write A but preserve its value (A|A == A, A&A == A);
//     they are treated as non-clobbering so the common `MOV D, A; ORA A`
//     zero-test prologue does not destroy the A == D equality.
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/PostOrderIterator.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/CodeGen/MachineBasicBlock.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/CodeGen/MachineOperand.h"
#include "llvm/CodeGen/TargetRegisterInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Debug.h"

using namespace llvm;

#define DEBUG_TYPE "v6clang-reg-value-forwarding"

static cl::opt<bool> DisableRegValueForwarding(
    "v6clang-disable-reg-value-forwarding",
    cl::desc("Disable V6CLANG cross-BB physical-register value forwarding (O92)"),
    cl::init(false), cl::Hidden);

namespace {

/// Per-register lattice value.  Top is represented by absence from the map.
struct ValState {
  enum Kind { Reg, Const } K;
  Register R;     // valid when K == Reg: this register equals R's contents
  int64_t C;      // valid when K == Const: this register holds immediate C

  static ValState reg(Register R) { return {Reg, R, 0}; }
  static ValState constant(int64_t C) { return {Const, Register(), C}; }

  bool operator==(const ValState &O) const {
    if (K != O.K)
      return false;
    return K == Reg ? R == O.R : C == O.C;
  }
  bool operator!=(const ValState &O) const { return !(*this == O); }
};

/// Map physreg -> known value.  Absence means Top (unknown).
using StateMap = DenseMap<Register, ValState>;

class V6ClangRegValueForwarding : public MachineFunctionPass {
public:
  static char ID;
  V6ClangRegValueForwarding() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Register Value Forwarding";
  }

  bool runOnMachineFunction(MachineFunction &MF) override;

private:
  const TargetRegisterInfo *TRI = nullptr;

  /// Return the value `R` is known to hold; defaults to Reg(R) (itself).
  ValState getCanon(const StateMap &S, Register R) const {
    auto It = S.find(R);
    if (It != S.end())
      return It->second;
    return ValState::reg(R);
  }

  /// Invalidate `Reg` and everything that aliased or referenced it.
  void clobberReg(StateMap &S, Register Reg) const;

  /// Invalidate every tracked register clobbered by a call's reg-mask.
  void clobberMask(StateMap &S, const uint32_t *Mask) const;

  /// True iff this is an `ORA A` / `ANA A` that preserves A's value.
  static bool isValuePreservingAccOp(const MachineInstr &MI);

  /// Run the transfer function over MBB starting from `In`; returns the
  /// out-state.  When `Transform` is true, redundant MOVrr/MVIr are erased.
  StateMap transfer(MachineBasicBlock &MBB, const StateMap &In,
                    bool Transform, bool &Changed);

  /// Meet (intersection) of two states into `A`.  Returns true if A changed.
  static bool meetInto(StateMap &A, const StateMap &B);
};

} // end anonymous namespace

char V6ClangRegValueForwarding::ID = 0;

/// True if MI is an O61 patched-immediate site: it carries a pre-instr
/// `.LLo61_N:` label (referenced by SHLD/STA spills) and/or its imm operand is
/// flagged MO_PATCH_IMM.  The byte is rewritten at runtime, so its value is
/// not statically known and the instruction must never be erased.
/// (Mirror of the canonical helper in V6ClangPeephole.cpp.)
static bool isO61PatchedImm(const MachineInstr &MI) {
  if (MI.getPreInstrSymbol())
    return true;
  for (const MachineOperand &MO : MI.operands())
    if (MO.getTargetFlags() != 0)
      return true;
  return false;
}

bool V6ClangRegValueForwarding::isValuePreservingAccOp(const MachineInstr &MI) {
  unsigned Op = MI.getOpcode();
  if (Op != V6Clang::ORAr && Op != V6Clang::ANAr)
    return false;
  // Operands: (dst=A, lhs=A, rs).  `ORA A` / `ANA A` iff rs == A.
  return MI.getNumOperands() >= 3 && MI.getOperand(2).isReg() &&
         MI.getOperand(2).getReg() == V6Clang::A;
}

void V6ClangRegValueForwarding::clobberReg(StateMap &S, Register Reg) const {
  SmallVector<Register, 4> ToErase;
  for (const auto &KV : S) {
    if (TRI->regsOverlap(KV.first, Reg) ||
        (KV.second.K == ValState::Reg &&
         TRI->regsOverlap(KV.second.R, Reg)))
      ToErase.push_back(KV.first);
  }
  for (Register R : ToErase)
    S.erase(R);
}

void V6ClangRegValueForwarding::clobberMask(StateMap &S,
                                        const uint32_t *Mask) const {
  SmallVector<Register, 8> ToErase;
  for (const auto &KV : S) {
    bool KeyClobbered = MachineOperand::clobbersPhysReg(Mask, KV.first.asMCReg());
    bool RefClobbered =
        KV.second.K == ValState::Reg &&
        MachineOperand::clobbersPhysReg(Mask, KV.second.R.asMCReg());
    if (KeyClobbered || RefClobbered)
      ToErase.push_back(KV.first);
  }
  for (Register R : ToErase)
    S.erase(R);
}

StateMap V6ClangRegValueForwarding::transfer(MachineBasicBlock &MBB,
                                         const StateMap &In, bool Transform,
                                         bool &Changed) {
  StateMap S = In;

  for (MachineInstr &MI : llvm::make_early_inc_range(MBB)) {
    if (MI.isDebugInstr())
      continue;

    unsigned Op = MI.getOpcode();

    // --- Redundant register-to-register move ---------------------------
    if (Op == V6Clang::MOVrr) {
      Register Rd = MI.getOperand(0).getReg();
      Register Rs = MI.getOperand(1).getReg();
      ValState Cs = getCanon(S, Rs);
      ValState Cd = getCanon(S, Rd);
      if (Cd == Cs) {
        // Rd already holds Rs's value — the move is a no-op.
        if (Transform) {
          LLVM_DEBUG(dbgs() << "  erase redundant " << MI);
          MI.eraseFromParent();
          Changed = true;
        }
        continue; // state unchanged
      }
      clobberReg(S, Rd);
      S[Rd] = Cs;
      continue;
    }

    // --- Redundant immediate load --------------------------------------
    if (Op == V6Clang::MVIr) {
      Register Rd = MI.getOperand(0).getReg();
      if (isO61PatchedImm(MI) || !MI.getOperand(1).isImm()) {
        // Runtime-patched or symbolic: value not statically known.
        clobberReg(S, Rd);
        continue;
      }
      int64_t Imm = MI.getOperand(1).getImm();
      ValState Cd = getCanon(S, Rd);
      if (Cd.K == ValState::Const && Cd.C == Imm) {
        if (Transform) {
          LLVM_DEBUG(dbgs() << "  erase redundant " << MI);
          MI.eraseFromParent();
          Changed = true;
        }
        continue; // state unchanged
      }
      clobberReg(S, Rd);
      S[Rd] = ValState::constant(Imm);
      continue;
    }

    // --- Value-preserving accumulator ops (ORA A / ANA A) --------------
    // These write A and FLAGS but leave A's value unchanged; do not clobber.
    if (isValuePreservingAccOp(MI))
      continue;

    // --- Inline asm: unknown effects, drop everything ------------------
    if (MI.isInlineAsm()) {
      S.clear();
      continue;
    }

    // --- Generic instruction: invalidate all defs and reg-masks --------
    for (const MachineOperand &MO : MI.operands()) {
      if (MO.isRegMask())
        clobberMask(S, MO.getRegMask());
    }
    for (const MachineOperand &MO : MI.operands()) {
      if (MO.isReg() && MO.isDef() && MO.getReg())
        clobberReg(S, MO.getReg());
    }
    for (const MachineOperand &MO : MI.implicit_operands()) {
      if (MO.isReg() && MO.isDef() && MO.getReg())
        clobberReg(S, MO.getReg());
    }
  }

  return S;
}

bool V6ClangRegValueForwarding::meetInto(StateMap &A, const StateMap &B) {
  // Intersection: keep only entries present in both with equal value.
  SmallVector<Register, 8> ToErase;
  for (const auto &KV : A) {
    auto It = B.find(KV.first);
    if (It == B.end() || It->second != KV.second)
      ToErase.push_back(KV.first);
  }
  for (Register R : ToErase)
    A.erase(R);
  return !ToErase.empty();
}

bool V6ClangRegValueForwarding::runOnMachineFunction(MachineFunction &MF) {
  if (DisableRegValueForwarding)
    return false;
  if (MF.empty())
    return false;

  TRI = MF.getSubtarget().getRegisterInfo();

  // Per-block in/out states, keyed by MBB number.
  DenseMap<unsigned, StateMap> InState, OutState;
  DenseMap<unsigned, bool> Computed;

  // Iterate to fixpoint in reverse-post-order using a worklist.  Unvisited
  // predecessors are ignored in the meet (optimistic "must" init), so a
  // loop header retains a forward-edge equality until/unless the converged
  // back-edge actually breaks it.
  ReversePostOrderTraversal<MachineFunction *> RPOT(&MF);
  SmallVector<MachineBasicBlock *, 16> Worklist(RPOT.begin(), RPOT.end());

  // Defensive bound — a monotone worklist converges quickly, but never spin.
  unsigned Budget = (MF.size() + 4) * 8 + 64;

  unsigned Idx = 0;
  while (Idx < Worklist.size()) {
    if (Budget-- == 0)
      break;
    MachineBasicBlock *MBB = Worklist[Idx++];

    // Compute In = meet over already-computed predecessors.
    StateMap In;
    bool First = true;
    for (MachineBasicBlock *Pred : MBB->predecessors()) {
      if (!Computed.lookup(Pred->getNumber()))
        continue;
      if (First) {
        In = OutState[Pred->getNumber()];
        First = false;
      } else {
        meetInto(In, OutState[Pred->getNumber()]);
      }
    }

    bool Dummy = false;
    StateMap Out = transfer(*MBB, In, /*Transform=*/false, Dummy);

    unsigned N = MBB->getNumber();
    bool WasComputed = Computed.lookup(N);
    bool OutChanged = !WasComputed || Out != OutState[N];
    InState[N] = std::move(In);
    OutState[N] = std::move(Out);
    Computed[N] = true;

    if (OutChanged) {
      for (MachineBasicBlock *Succ : MBB->successors())
        Worklist.push_back(Succ);
    }
  }

  // Final transform pass: erase redundant moves using the converged In states.
  bool Changed = false;
  for (MachineBasicBlock &MBB : MF) {
    const StateMap &In = InState[MBB.getNumber()];
    transfer(MBB, In, /*Transform=*/true, Changed);
  }

  return Changed;
}

FunctionPass *llvm::createV6ClangRegValueForwardingPass() {
  return new V6ClangRegValueForwarding();
}
