//===-- V6ClangStaticStackAlloc.cpp - Static Stack for Non-Reentrant Fns ------===//
//
// Part of the V6CLANG backend for LLVM.
//
// O10: Static Stack Allocation for Non-Reentrant Functions.
//
// For functions that are provably non-reentrant (norecurse, not reachable
// from interrupt handlers, address not taken), replace the stack frame
// with a statically-allocated global memory region.  This turns expensive
// SP-relative spill/reload sequences (52cc+) into direct global memory
// accesses via STA/LDA/SHLD/LHLD (16-24cc).
//
// Algorithm:
//   1. On first invocation, compute interrupt reachability via BFS from
//      all interrupt-attributed functions.
//   2. For each eligible function: create a per-function global
//      @__v6clang_ss.<funcname>, record the frame-index-to-offset mapping
//      in V6ClangMachineFunctionInfo, and zero out frame object sizes so PEI
//      skips prologue/epilogue SP adjustment.
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "V6ClangMachineFunctionInfo.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"

#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Debug.h"

#include <queue>

using namespace llvm;

#define DEBUG_TYPE "v6clang-static-stack-alloc"

static cl::opt<bool> DisableStaticStackAlloc(
    "v6clang-disable-static-stack-alloc",
    cl::desc("Disable V6CLANG static stack allocation (O10)"),
    cl::init(false), cl::Hidden);

namespace {

class V6ClangStaticStackAlloc : public MachineFunctionPass {
public:
  static char ID;
  V6ClangStaticStackAlloc() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Static Stack Allocation (O10)";
  }

  void getAnalysisUsage(AnalysisUsage &AU) const override {
    AU.addRequired<MachineModuleInfoWrapperPass>();
    AU.setPreservesAll();
    MachineFunctionPass::getAnalysisUsage(AU);
  }

  bool runOnMachineFunction(MachineFunction &MF) override;

private:
  /// Whether module-level analysis has been performed.
  bool ModuleAnalyzed = false;

  /// Set of functions reachable from interrupt handlers.
  SmallPtrSet<const Function *, 16> InterruptReachable;

  void analyzeInterruptReachability(Module &M);
  bool isFunctionEligible(const Function &F, const MachineFunction &MF) const;
  bool hasNoCallbackEvidence(const Function &F) const;
};

} // end anonymous namespace

char V6ClangStaticStackAlloc::ID = 0;

/// Local check: F cannot be re-entered transitively through any of its
/// callees, even though LLVM's SCC pass did not infer `norecurse`.
///
/// LLVM is conservative when inferring `norecurse`: any inline-asm callsite
/// or any call to an intrinsic that lacks `nocallback` causes the SCC pass
/// to give up and not mark callers as norecurse. That blocks every function
/// that uses `__asm__ volatile(...)` or a target intrinsic from getting
/// static-stack allocation, even when the callee provably cannot transfer
/// control back into the caller.
///
/// We fill the gap with a local check: F is safe iff every CallBase in F
/// (and, transitively, in every callee whose body is visible) is one of:
///   - an inline-asm call (the asm string cannot reference C symbols
///     dynamically, so it cannot recursively re-enter F);
///   - a call where the callee/callsite carries the `nocallback`
///     attribute (intrinsics or normal functions tagged `leaf`);
///   - a call to a `norecurse` callee. `norecurse` is set by
///     PostOrderFunctionAttrs only after SCC analysis proves the callee
///     is not part of any call cycle in the module, so it cannot
///     transitively re-enter F.
///   - a call to a callee whose body is visible and which itself
///     satisfies the same recursive check (with cycle detection).
///
/// The last bullet is what lets a C wrapper such as `draw_circle()` be
/// considered safe when called from `main()`: `draw_circle` has neither
/// `nocallback` (it isn't marked `leaf`) nor `norecurse` (LLVM's SCC pass
/// gives up because one of its callees, `draw_pixel`, has an inline-asm
/// body and is only `nocallback`-tagged, not `norecurse`-tagged). But the
/// body of `draw_circle` only calls `draw_pixel`, which IS `nocallback`,
/// so the chain is safe and we can prove it locally by recursing.
///
/// Cycles in the call graph (including direct self-recursion) abort the
/// recursion and reject the function — that's exactly the case static
/// stack allocation cannot handle.
///
/// Combined with the existing checks (no address taken, not reachable from
/// any interrupt handler), this guarantees F cannot be re-entered while a
/// previous activation is still live, which is the only correctness
/// requirement for static-stack allocation.
static bool
hasNoCallbackEvidenceImpl(const Function &F,
                          SmallPtrSetImpl<const Function *> &Visited) {
  // Cycle in the recursion ⇒ unsafe (covers direct self-recursion too).
  if (!Visited.insert(&F).second)
    return false;

  for (const BasicBlock &BB : F) {
    for (const Instruction &I : BB) {
      const auto *CB = dyn_cast<CallBase>(&I);
      if (!CB)
        continue;

      // Inline asm cannot dynamically dispatch back into the caller.
      if (CB->isInlineAsm())
        continue;

      // Either the callsite or the callee must promise nocallback.
      if (CB->hasFnAttr(Attribute::NoCallback))
        continue;
      const Function *Callee = CB->getCalledFunction();
      if (!Callee)
        return false; // indirect call — unknown target
      if (Callee->hasFnAttribute(Attribute::NoCallback))
        continue;
      if (Callee->hasFnAttribute(Attribute::NoRecurse))
        continue;

      // Transitive check: if the callee's body is visible in this
      // module, recurse into it. This is what lets a C wrapper that
      // only calls `nocallback` leaves be considered safe even when
      // LLVM refuses to propagate any single attribute up.
      if (!Callee->isDeclaration() &&
          hasNoCallbackEvidenceImpl(*Callee, Visited))
        continue;

      // Anything else: be conservative.
      return false;
    }
  }
  return true;
}

bool V6ClangStaticStackAlloc::hasNoCallbackEvidence(const Function &F) const {
  SmallPtrSet<const Function *, 8> Visited;
  return hasNoCallbackEvidenceImpl(F, Visited);
}

/// BFS from interrupt-attributed functions to find all transitively
/// reachable functions.
void V6ClangStaticStackAlloc::analyzeInterruptReachability(Module &M) {
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

  LLVM_DEBUG(dbgs() << "V6ClangStaticStackAlloc: " << InterruptReachable.size()
                    << " functions reachable from interrupt handlers\n");
}

bool V6ClangStaticStackAlloc::isFunctionEligible(
    const Function &F, const MachineFunction &MF) const {
  // The function must be provably non-reentrant. Either LLVM inferred
  // `norecurse` (preferred) or we can locally prove that no callsite in F
  // can transfer control back into F (covers inline-asm and target
  // intrinsics that block SCC norecurse inference).
  if (!F.hasFnAttribute(Attribute::NoRecurse) && !hasNoCallbackEvidence(F))
    return false;

  // Must not be an interrupt handler itself.
  if (F.hasFnAttribute("interrupt"))
    return false;

  // Must not be reachable from any interrupt handler.
  if (InterruptReachable.count(&F))
    return false;

  // Must not have its address taken (could be called via function pointer
  // from interrupt context).
  if (F.hasAddressTaken())
    return false;

  // Must have non-fixed frame objects (spill slots or locals).
  const MachineFrameInfo &MFI = MF.getFrameInfo();
  bool HasNonFixedObjects = false;
  for (int I = 0, E = MFI.getObjectIndexEnd(); I < E; ++I) {
    if (!MFI.isDeadObjectIndex(I) && MFI.getObjectSize(I) > 0) {
      HasNonFixedObjects = true;
      break;
    }
  }
  if (!HasNonFixedObjects)
    return false;

  return true;
}

bool V6ClangStaticStackAlloc::runOnMachineFunction(MachineFunction &MF) {
  if (DisableStaticStackAlloc)
    return false;

  Module &M = *MF.getFunction().getParent();

  // Perform module-level analysis once.
  if (!ModuleAnalyzed) {
    analyzeInterruptReachability(M);
    ModuleAnalyzed = true;
  }

  const Function &F = MF.getFunction();
  if (!isFunctionEligible(F, MF))
    return false;

  MachineFrameInfo &MFI = MF.getFrameInfo();
  auto *FuncInfo = MF.getInfo<V6ClangMachineFunctionInfo>();

  LLVM_DEBUG(dbgs() << "V6ClangStaticStackAlloc: allocating static frame for "
                    << F.getName() << "\n");

  // First pass: compute total size needed for this function's frame objects.
  int64_t TotalSize = 0;
  for (int I = 0, E = MFI.getObjectIndexEnd(); I < E; ++I) {
    if (MFI.isDeadObjectIndex(I))
      continue;
    int64_t ObjSize = MFI.getObjectSize(I);
    if (ObjSize > 0)
      TotalSize += ObjSize;
  }

  if (TotalSize == 0)
    return false;

  // Create a per-function global variable with the exact size needed.
  LLVMContext &Ctx = M.getContext();
  auto *ArrTy = ArrayType::get(Type::getInt8Ty(Ctx), TotalSize);
  std::string GVName = ("__v6clang_ss." + F.getName()).str();
  auto *GV = new GlobalVariable(
      M, ArrTy, /*isConstant=*/false, GlobalValue::InternalLinkage,
      ConstantAggregateZero::get(ArrTy), GVName);
  GV->setAlignment(Align(1));

  // Second pass: assign static offsets for each non-fixed, non-dead
  // frame object.
  int64_t Offset = 0;
  for (int I = 0, E = MFI.getObjectIndexEnd(); I < E; ++I) {
    if (MFI.isDeadObjectIndex(I))
      continue;
    int64_t ObjSize = MFI.getObjectSize(I);
    if (ObjSize <= 0)
      continue;

    FuncInfo->addStaticSlot(I, Offset, ObjSize);
    Offset += ObjSize;

    LLVM_DEBUG(dbgs() << "  FI#" << I << ": size=" << ObjSize
                      << " -> static offset " << Offset - ObjSize << "\n");
  }

  // Mark the function for static stack usage.
  FuncInfo->setStaticStack(GV);

  // Zero out frame object sizes so PEI computes StackSize = 0.
  // This eliminates prologue/epilogue SP adjustment.
  for (int I = 0, E = MFI.getObjectIndexEnd(); I < E; ++I) {
    if (!MFI.isDeadObjectIndex(I) && MFI.getObjectSize(I) > 0) {
      MFI.setObjectSize(I, 0);
    }
  }

  LLVM_DEBUG(dbgs() << "  Static stack size: " << TotalSize << " bytes\n");

  return true;
}

FunctionPass *llvm::createV6ClangStaticStackAllocPass() {
  return new V6ClangStaticStackAlloc();
}
