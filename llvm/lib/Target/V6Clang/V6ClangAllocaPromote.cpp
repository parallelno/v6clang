//===-- V6ClangAllocaPromote.cpp - Promote allocas to per-function globals -==//
//
// Part of the V6CLANG backend for LLVM.
//
// IR-level companion to V6ClangStaticStackAlloc (O10).
//
// For non-reentrant functions, replaces every static `alloca` in the entry
// block with a constant `getelementptr` into a per-function internal global
// `@__v6clang_a.<func>`. This must run *before* SelectionDAG ISel: once ISel
// sees a FrameIndex it lowers element-address arithmetic (e.g. `&a[i]` for
// a stack-local `a[16]`) through the V6ClangISD::DAD pseudo, which on the 8080
// requires an XCHG/DAD scratch sequence that can clobber the iterator
// pointer when both `&a[0]` and `&a[16]` are needed in the same loop.
//
// By turning the alloca into a GlobalAddress at IR level, the selector
// folds `gep @gv, i16 16` into the `LXI HL, @gv+16` immediate form
// natively, and the XCHG/DAD path is never emitted.
//
// Eligibility mirrors the post-RA V6ClangStaticStackAlloc gate:
//   - `norecurse` (or local "no-callback" evidence: every CallBase is
//     inline-asm or has the `nocallback` attribute, and no direct
//     self-recursion).
//   - not an interrupt handler.
//   - not transitively reachable from any interrupt handler.
//   - address not taken.
//
// The post-RA V6ClangStaticStackAlloc pass still runs and handles register-
// allocator spill slots in a separate `@__v6clang_ss.<func>` global.
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"

#include "llvm/IR/Constants.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/InstIterator.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Pass.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Debug.h"

#include <queue>

using namespace llvm;

#define DEBUG_TYPE "v6clang-alloca-promote"

static cl::opt<bool>
    DisableAllocaPromote("v6clang-disable-alloca-promote",
                         cl::desc("Disable V6CLANG IR-level alloca-to-global promotion"),
                         cl::init(false), cl::Hidden);

namespace {

class V6ClangAllocaPromote : public ModulePass {
public:
  static char ID;
  V6ClangAllocaPromote() : ModulePass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Alloca Promote (pre-ISel)";
  }

  bool runOnModule(Module &M) override;

private:
  SmallPtrSet<const Function *, 16> InterruptReachable;

  void analyzeInterruptReachability(Module &M);
  bool isFunctionEligible(const Function &F) const;
  bool hasNoCallbackEvidence(const Function &F) const;
  bool promoteAllocas(Function &F);
};

} // end anonymous namespace

char V6ClangAllocaPromote::ID = 0;

bool V6ClangAllocaPromote::hasNoCallbackEvidence(const Function &F) const {
  for (const BasicBlock &BB : F) {
    for (const Instruction &I : BB) {
      const auto *CB = dyn_cast<CallBase>(&I);
      if (!CB)
        continue;
      if (CB->isInlineAsm())
        continue;
      if (CB->hasFnAttr(Attribute::NoCallback))
        continue;
      const Function *Callee = CB->getCalledFunction();
      if (!Callee)
        return false; // indirect call
      if (Callee->hasFnAttribute(Attribute::NoCallback))
        continue;
      if (Callee == &F)
        return false; // direct self-recursion
      return false;
    }
  }
  return true;
}

void V6ClangAllocaPromote::analyzeInterruptReachability(Module &M) {
  std::queue<const Function *> Worklist;
  for (const Function &F : M) {
    if (F.hasFnAttribute("interrupt")) {
      InterruptReachable.insert(&F);
      Worklist.push(&F);
    }
  }
  while (!Worklist.empty()) {
    const Function *F = Worklist.front();
    Worklist.pop();
    for (const BasicBlock &BB : *F) {
      for (const Instruction &I : BB) {
        const auto *CB = dyn_cast<CallBase>(&I);
        if (!CB)
          continue;
        const Function *Callee = CB->getCalledFunction();
        if (!Callee || Callee->isDeclaration())
          continue;
        if (InterruptReachable.insert(Callee).second)
          Worklist.push(Callee);
      }
    }
  }
}

bool V6ClangAllocaPromote::isFunctionEligible(const Function &F) const {
  if (F.isDeclaration())
    return false;
  if (!F.hasFnAttribute(Attribute::NoRecurse) && !hasNoCallbackEvidence(F))
    return false;
  if (F.hasFnAttribute("interrupt"))
    return false;
  if (InterruptReachable.count(&F))
    return false;
  if (F.hasAddressTaken())
    return false;
  return true;
}

bool V6ClangAllocaPromote::promoteAllocas(Function &F) {
  // Collect static (constant-size) allocas in the entry block. Only the
  // entry block hosts the static-frame allocas LLVM creates for C locals;
  // dynamic / non-entry-block allocas (alloca with %size, alloca in a
  // loop) cannot be statically laid out.
  SmallVector<AllocaInst *, 8> Static;
  BasicBlock &Entry = F.getEntryBlock();
  const bool HasDebugInfo =
      F.getParent()->getNamedMetadata("llvm.dbg.cu") != nullptr;
  for (Instruction &I : Entry) {
    auto *AI = dyn_cast<AllocaInst>(&I);
    if (!AI)
      continue;
    if (!AI->isStaticAlloca())
      continue;
    Static.push_back(AI);
  }
  if (Static.empty())
    return false;

  Module &M = *F.getParent();
  LLVMContext &Ctx = M.getContext();
  const DataLayout &DL = M.getDataLayout();

  // Lay out each alloca; alignment is 1 on V6CLANG so we can pack densely.
  // Compute total size in bytes, capped at 65535 to fit i16 addressing.
  uint64_t Total = 0;
  SmallVector<uint64_t, 8> Offsets;
  Offsets.reserve(Static.size());
  for (AllocaInst *AI : Static) {
    auto SizeOpt = AI->getAllocationSize(DL);
    if (!SizeOpt)
      return false;
    uint64_t Size = SizeOpt->getFixedValue();
    // Defensively round to at least 1 byte so distinct allocas get
    // distinct addresses.
    if (Size == 0)
      Size = 1;
    Offsets.push_back(Total);
    Total += Size;
    if (Total > 0xFFFF)
      return false; // can't address with i16 — bail out.
  }

  if (Total == 0)
    return false;

  Type *I8 = Type::getInt8Ty(Ctx);
  ArrayType *ArrTy = ArrayType::get(I8, Total);
  std::string GVName = ("__v6clang_a." + F.getName()).str();
  auto *GV = new GlobalVariable(
      M, ArrTy, /*isConstant=*/false, GlobalValue::InternalLinkage,
      ConstantAggregateZero::get(ArrTy), GVName);
  GV->setAlignment(Align(1));

  Type *I16 = Type::getInt16Ty(Ctx);

  auto makeDebugHomeOrdered = [](AllocaInst *AI) {
    SmallVector<Value *, 8> Worklist{AI};
    SmallPtrSet<Value *, 8> Visited;
    while (!Worklist.empty()) {
      Value *V = Worklist.pop_back_val();
      if (!Visited.insert(V).second)
        continue;
      for (User *U : V->users()) {
        if (auto *LI = dyn_cast<LoadInst>(U)) {
          LI->setVolatile(true);
        } else if (auto *SI = dyn_cast<StoreInst>(U)) {
          if (SI->getPointerOperand() == V)
            SI->setVolatile(true);
        } else if (isa<GetElementPtrInst>(U) || isa<BitCastInst>(U) ||
                   isa<AddrSpaceCastInst>(U)) {
          Worklist.push_back(cast<Value>(U));
        }
      }
    }
  };

  // Replace each alloca with `getelementptr inbounds [N x i8], ptr @gv,
  // i16 0, i16 offset`. The result type matches `alloca`'s ptr, so no
  // bitcast is needed in opaque-pointer IR.
  for (size_t I = 0, E = Static.size(); I < E; ++I) {
    AllocaInst *AI = Static[I];
    if (HasDebugInfo)
      makeDebugHomeOrdered(AI);
    Constant *Idx[] = {
        ConstantInt::get(I16, 0),
        ConstantInt::get(I16, Offsets[I]),
    };
    Constant *GEP = ConstantExpr::getInBoundsGetElementPtr(ArrTy, GV, Idx);
    AI->replaceAllUsesWith(GEP);
    AI->eraseFromParent();
  }

  LLVM_DEBUG(dbgs() << "V6ClangAllocaPromote: promoted " << Static.size()
                    << " allocas (" << Total << " bytes) in "
                    << F.getName() << "\n");
  return true;
}

bool V6ClangAllocaPromote::runOnModule(Module &M) {
  if (DisableAllocaPromote || !getV6ClangStaticStackEnabled())
    return false;

  InterruptReachable.clear();
  analyzeInterruptReachability(M);

  bool Changed = false;
  for (Function &F : M) {
    if (!isFunctionEligible(F))
      continue;
    Changed |= promoteAllocas(F);
  }
  return Changed;
}

ModulePass *llvm::createV6ClangAllocaPromotePass() {
  return new V6ClangAllocaPromote();
}
