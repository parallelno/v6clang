//===-- V6ClangLoopPointerInduction.cpp - Replace base+counter with pointers --===//
//
// Part of the V6CLANG backend for LLVM.
//
// IR-level FunctionPass that converts loop address patterns from
// base+counter form to running pointer form:
//
//   Before: %addr = gep @array, %counter
//           load/store %addr
//
//   After:  %ptr = phi [@array, preheader], [%next, latch]
//           load/store %ptr
//           %next = gep %ptr, 1
//
// On the 8080, base+counter requires LXI+DAD (24cc) per iteration per array,
// while running pointers only need INX (8cc). For a two-array loop this
// saves ~100+ cc per iteration.
//
// This pass runs after LLVM's Loop Strength Reduction, which does not
// generate running-pointer IVs because its DoInitialMatch always decomposes
// AddRecs with non-zero starts into separate loop-invariant + counter
// registers.
//
// Toggle: -v6clang-disable-loop-pointer-induction
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Instructions.h"
#include "llvm/Pass.h"
#include "llvm/Support/CommandLine.h"

using namespace llvm;

#define DEBUG_TYPE "v6clang-loop-pointer-induction"

static cl::opt<bool> DisableLoopPointerInduction(
    "v6clang-disable-loop-pointer-induction",
    cl::desc("Disable V6CLANG loop base+counter to pointer induction conversion"),
    cl::init(false), cl::Hidden);

namespace {

class V6ClangLoopPointerInduction : public FunctionPass {
public:
  static char ID;
  V6ClangLoopPointerInduction() : FunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Loop Pointer Induction";
  }

  bool runOnFunction(Function &F) override;

  void getAnalysisUsage(AnalysisUsage &AU) const override {
    AU.addRequired<LoopInfoWrapperPass>();
  }

private:
  /// Find the integer counter IV: phi [0, preheader], [counter+step, latch].
  /// Returns the phi and its step (must be a positive constant).
  PHINode *findCounterIV(Loop *L, int64_t &Step);

  /// Try to convert a GEP that uses the counter IV into a running pointer.
  bool convertGEP(Loop *L, PHINode *CounterIV, int64_t Step,
                  GetElementPtrInst *GEP, PHINode *&CreatedPhi);

  /// Process a single loop.
  bool processLoop(Loop *L);

  /// Try to rewrite the loop exit condition to use a pointer IV.
  bool rewriteExitCondition(Loop *L, PHINode *CounterIV, int64_t Step,
                            PHINode *PtrPhi, Value *PtrBase);
};

} // end anonymous namespace

char V6ClangLoopPointerInduction::ID = 0;

PHINode *V6ClangLoopPointerInduction::findCounterIV(Loop *L, int64_t &Step) {
  BasicBlock *Header = L->getHeader();
  BasicBlock *Latch = L->getLoopLatch();
  BasicBlock *Preheader = L->getLoopPreheader();
  if (!Latch || !Preheader)
    return nullptr;

  for (PHINode &PN : Header->phis()) {
    if (!PN.getType()->isIntegerTy())
      continue;

    // Check start value from preheader is 0.
    Value *StartVal = PN.getIncomingValueForBlock(Preheader);
    auto *StartCI = dyn_cast<ConstantInt>(StartVal);
    if (!StartCI || !StartCI->isZero())
      continue;

    // Check latch value is counter + constant.
    Value *LatchVal = PN.getIncomingValueForBlock(Latch);
    auto *AddInst = dyn_cast<BinaryOperator>(LatchVal);
    if (!AddInst || AddInst->getOpcode() != Instruction::Add)
      continue;

    // One operand should be the phi, the other a positive constant.
    Value *Other = nullptr;
    if (AddInst->getOperand(0) == &PN)
      Other = AddInst->getOperand(1);
    else if (AddInst->getOperand(1) == &PN)
      Other = AddInst->getOperand(0);
    else
      continue;

    auto *StepCI = dyn_cast<ConstantInt>(Other);
    if (!StepCI || StepCI->isNegative() || StepCI->isZero())
      continue;

    Step = StepCI->getSExtValue();
    return &PN;
  }
  return nullptr;
}

bool V6ClangLoopPointerInduction::convertGEP(Loop *L, PHINode *CounterIV,
                                           int64_t Step,
                                           GetElementPtrInst *GEP,
                                           PHINode *&CreatedPhi) {
  Value *Base = nullptr;
  Value *Index = nullptr;

  // Match: gep i8, ptr @global, i16 %counter  (1-index)
  // or:    gep [N x i8], ptr @global, i16 0, i16 %counter  (2-index)
  if (GEP->getNumIndices() == 1) {
    Base = GEP->getPointerOperand();
    Index = GEP->getOperand(1);
  } else if (GEP->getNumIndices() == 2) {
    Base = GEP->getPointerOperand();
    // First index must be constant 0 (no array-of-arrays offset).
    auto *FirstIdx = dyn_cast<ConstantInt>(GEP->getOperand(1));
    if (!FirstIdx || !FirstIdx->isZero())
      return false;
    Index = GEP->getOperand(2);
  } else {
    return false;
  }

  // The index must be the counter IV.
  if (Index != CounterIV)
    return false;

  // The base must be loop-invariant (typically a global or alloca).
  if (!L->isLoopInvariant(Base))
    return false;

  // All users of the GEP must be in the loop.
  for (User *U : GEP->users()) {
    auto *UI = dyn_cast<Instruction>(U);
    if (!UI || !L->contains(UI))
      return false;
  }

  BasicBlock *Header = L->getHeader();
  BasicBlock *Latch = L->getLoopLatch();
  BasicBlock *Preheader = L->getLoopPreheader();

  // Create the running pointer phi.
  IRBuilder<> Builder(Header, Header->getFirstInsertionPt());
  PHINode *PtrPhi = Builder.CreatePHI(GEP->getType(), 2, "ptr.iv");

  // Start value: the base pointer.
  PtrPhi->addIncoming(Base, Preheader);

  // Step: gep ptr, Step at the end of the latch block.
  IRBuilder<> LatchBuilder(Latch->getTerminator());
  Value *StepVal = LatchBuilder.getInt16(Step);
  Value *NextPtr = LatchBuilder.CreateGEP(
      Type::getInt8Ty(GEP->getContext()), PtrPhi, StepVal, "ptr.next");

  PtrPhi->addIncoming(NextPtr, Latch);

  // Replace all uses of the GEP with the pointer phi.
  GEP->replaceAllUsesWith(PtrPhi);
  GEP->eraseFromParent();

  CreatedPhi = PtrPhi;
  return true;
}

bool V6ClangLoopPointerInduction::rewriteExitCondition(
    Loop *L, PHINode *CounterIV, int64_t Step,
    PHINode *PtrPhi, Value *PtrBase) {
  // Find the increment: counter.next = counter + step
  BasicBlock *Latch = L->getLoopLatch();
  Value *LatchVal = CounterIV->getIncomingValueForBlock(Latch);
  auto *CounterInc = dyn_cast<BinaryOperator>(LatchVal);
  if (!CounterInc)
    return false;

  // Find the icmp using counter.next.
  ICmpInst *ExitCmp = nullptr;
  ConstantInt *ExitLimit = nullptr;
  for (User *U : CounterInc->users()) {
    auto *Cmp = dyn_cast<ICmpInst>(U);
    if (!Cmp)
      continue;
    // Match: icmp eq counter.next, <limit>
    if (Cmp->getPredicate() != ICmpInst::ICMP_EQ &&
        Cmp->getPredicate() != ICmpInst::ICMP_NE)
      continue;
    Value *CmpLimit = (Cmp->getOperand(0) == CounterInc)
                          ? Cmp->getOperand(1)
                          : Cmp->getOperand(0);
    auto *CI = dyn_cast<ConstantInt>(CmpLimit);
    if (!CI)
      continue;
    ExitCmp = Cmp;
    ExitLimit = CI;
    break;
  }

  if (!ExitCmp || !ExitLimit)
    return false;

  // Compute end-of-pointer: PtrBase + ExitLimit.
  // The pointer phi always equals Base + counter, so when counter_next ==
  // ExitLimit the pointer_next == Base + ExitLimit.  Multiplying by Step
  // would be wrong: codegen's LSR may have already folded the original
  // step-1 counter into a step-N counter (e.g. step=2, limit=16 for an
  // 8-iteration loop with stride 2), making ExitLimit the correct byte
  // offset directly.
  int64_t EndOffset = ExitLimit->getSExtValue();

  BasicBlock *Preheader = L->getLoopPreheader();
  IRBuilder<> PreBuilder(Preheader->getTerminator());
  Value *EndOffsetVal = PreBuilder.getInt16(EndOffset);
  Value *EndPtr = PreBuilder.CreateGEP(
      Type::getInt8Ty(ExitCmp->getContext()), PtrBase, EndOffsetVal,
      "ptr.end");

  // Find the pointer increment (ptr.next) corresponding to PtrPhi.
  Value *PtrNext = PtrPhi->getIncomingValueForBlock(Latch);

  // Insert the new icmp right after ptr.next to maintain dominance.
  // ptr.next is a GEP inserted before the latch terminator, and the old
  // ExitCmp may appear earlier in the block.
  auto *PtrNextInst = cast<Instruction>(PtrNext);
  IRBuilder<> CmpBuilder(PtrNextInst->getNextNode());
  Value *NewCmp = CmpBuilder.CreateICmp(ExitCmp->getPredicate(),
                                         PtrNext, EndPtr, "ptr.exit");
  ExitCmp->replaceAllUsesWith(NewCmp);
  ExitCmp->eraseFromParent();

  // Now the counter IV and its increment may be dead.
  // Remove the increment if only used by the counter phi.
  if (CounterInc->hasOneUse()) {
    User *OnlyUser = *CounterInc->user_begin();
    if (OnlyUser == CounterIV) {
      CounterIV->replaceAllUsesWith(UndefValue::get(CounterIV->getType()));
      CounterInc->eraseFromParent();
      CounterIV->eraseFromParent();
    }
  } else if (CounterInc->use_empty()) {
    CounterInc->eraseFromParent();
    if (CounterIV->use_empty())
      CounterIV->eraseFromParent();
  }

  return true;
}

bool V6ClangLoopPointerInduction::runOnFunction(Function &F) {
  if (DisableLoopPointerInduction)
    return false;

  auto &LI = getAnalysis<LoopInfoWrapperPass>().getLoopInfo();

  bool Changed = false;
  // Process innermost loops only (bottom-up order).
  for (Loop *L : LI) {
    SmallVector<Loop *, 4> Worklist;
    for (Loop *Sub : depth_first(L))
      if (Sub->getSubLoops().empty())
        Worklist.push_back(Sub);
    for (Loop *Inner : Worklist)
      Changed |= processLoop(Inner);
  }
  return Changed;
}

bool V6ClangLoopPointerInduction::processLoop(Loop *L) {

  if (!L->getLoopPreheader() || !L->getLoopLatch())
    return false;

  int64_t Step;
  PHINode *CounterIV = findCounterIV(L, Step);
  if (!CounterIV)
    return false;

  // Collect GEPs in the loop that use the counter IV.
  SmallVector<GetElementPtrInst *, 4> GEPs;
  for (BasicBlock *BB : L->blocks()) {
    for (Instruction &I : *BB) {
      if (auto *GEP = dyn_cast<GetElementPtrInst>(&I)) {
        // Match 1-index or 2-index GEPs with the counter as the last index.
        Value *LastIdx = GEP->getOperand(GEP->getNumOperands() - 1);
        if (LastIdx != CounterIV)
          continue;
        if (!L->isLoopInvariant(GEP->getPointerOperand()))
          continue;
        if (GEP->getNumIndices() == 1) {
          GEPs.push_back(GEP);
        } else if (GEP->getNumIndices() == 2) {
          auto *FirstIdx = dyn_cast<ConstantInt>(GEP->getOperand(1));
          if (FirstIdx && FirstIdx->isZero())
            GEPs.push_back(GEP);
        }
      }
    }
  }

  if (GEPs.empty())
    return false;

  PHINode *FirstPtrPhi = nullptr;
  Value *FirstPtrBase = nullptr;
  bool Changed = false;

  for (GetElementPtrInst *GEP : GEPs) {
    Value *Base = GEP->getPointerOperand();
    PHINode *CreatedPhi = nullptr;
    if (convertGEP(L, CounterIV, Step, GEP, CreatedPhi)) {
      Changed = true;
      if (!FirstPtrPhi) {
        FirstPtrPhi = CreatedPhi;
        FirstPtrBase = Base;
      }
    }
  }

  // Try to eliminate the counter IV by rewriting the exit condition.
  if (Changed && FirstPtrPhi)
    rewriteExitCondition(L, CounterIV, Step, FirstPtrPhi, FirstPtrBase);

  return Changed;
}

FunctionPass *llvm::createV6ClangLoopPointerInductionPass() {
  return new V6ClangLoopPointerInduction();
}
