//===-- V6ClangTargetMachine.cpp - Define TargetMachine for V6CLANG ---------------===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#include "V6ClangTargetMachine.h"
#include "V6ClangTargetObjectFile.h"
#include "V6ClangTargetTransformInfo.h"

#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/Passes.h"
#include "llvm/CodeGen/TargetPassConfig.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/CommandLine.h"

#include "V6Clang.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "TargetInfo/V6ClangTargetInfo.h"

#include <optional>

static llvm::cl::opt<unsigned> V6ClangStartAddress(
    "mv6clang-start-address",
    llvm::cl::desc("Start address for V6CLANG binary (default: 0x0100)"),
    llvm::cl::init(0x0100));

static llvm::cl::opt<bool> V6ClangStaticStack(
    "mv6clang-static-stack",
    llvm::cl::desc("Use static memory for non-reentrant function stack frames"),
    llvm::cl::init(true));

static llvm::cl::opt<bool> V6ClangNoStaticStack(
    "mv6clang-no-static-stack",
    llvm::cl::desc("Disable static stack allocation"),
    llvm::cl::init(false));

static llvm::cl::opt<bool> V6ClangAnnotatePseudos(
    "mv6clang-annotate-pseudos",
    llvm::cl::desc("Add asm comments showing pseudo expansion origins"),
    llvm::cl::init(false));

static llvm::cl::opt<bool> V6ClangPrintRTHelpers(
    "mv6clang-print-rt-helpers",
    llvm::cl::desc("Emit auto-included v6clang_arith.h runtime helpers "
                   "(__mulqi3, __mulhi3, __udivhi3, ...) into asm output. "
                   "Off by default to keep `.s` readable; the helpers are "
                   "still generated into the object file regardless."),
    llvm::cl::init(false));

static llvm::cl::opt<bool> V6ClangSpillPatchedReload(
    "mv6clang-spill-patched-reload",
    llvm::cl::desc("O61: rewrite HL spill/reload pairs as patched LXI HL "
                   "(self-modifying code, static-stack only)"),
    llvm::cl::init(true), llvm::cl::Hidden);

static llvm::cl::opt<bool> V6ClangNoSpillPatchedReload(
    "mv6clang-no-spill-patched-reload",
    llvm::cl::desc("Disable O61 spill-patched-reload rewriting"),
    llvm::cl::init(false));

namespace llvm {

unsigned getV6ClangStartAddress() { return V6ClangStartAddress; }
bool getV6ClangStaticStackEnabled() { return V6ClangStaticStack && !V6ClangNoStaticStack; }
bool getV6ClangAnnotatePseudosEnabled() { return V6ClangAnnotatePseudos; }
bool getV6ClangPrintRTHelpersEnabled() { return V6ClangPrintRTHelpers; }
bool getV6ClangSpillPatchedReloadEnabled() {
  return V6ClangSpillPatchedReload && !V6ClangNoSpillPatchedReload;
}

// Data layout: little-endian, 16-bit pointers (8-bit aligned),
// all types 8-bit aligned, native integer widths 8 and 16, stack alignment 8.
static const char *V6ClangDataLayout =
    "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8";

static StringRef getCPU(StringRef CPU) {
  if (CPU.empty() || CPU == "generic")
    return "i8080";
  return CPU;
}

static Reloc::Model getEffectiveRelocModel(std::optional<Reloc::Model> RM) {
  return RM.value_or(Reloc::Static);
}

V6ClangTargetMachine::V6ClangTargetMachine(const Target &T, const Triple &TT,
                                    StringRef CPU, StringRef FS,
                                    const TargetOptions &Options,
                                    std::optional<Reloc::Model> RM,
                                    std::optional<CodeModel::Model> CM,
                                    CodeGenOptLevel OL, bool JIT)
    : LLVMTargetMachine(T, V6ClangDataLayout, TT, getCPU(CPU), FS, Options,
                        getEffectiveRelocModel(RM),
                        getEffectiveCodeModel(CM, CodeModel::Small), OL),
      SubTarget(TT, std::string(getCPU(CPU)), std::string(FS), *this) {
  TLOF = std::make_unique<V6ClangTargetObjectFile>();
  initAsmInfo();
}

V6ClangTargetMachine::~V6ClangTargetMachine() = default;

namespace {

// Debug-only verifier: every V6CLANG CALL MachineInstr must carry a register mask
// operand after instruction selection.  Without a mask, IPRA cannot narrow
// the call-site clobber set and the allocator silently under-spills.
#ifndef NDEBUG
class V6ClangCallRegMaskVerifier : public MachineFunctionPass {
public:
  static char ID;
  V6ClangCallRegMaskVerifier() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG CALL register-mask verifier (debug)";
  }

  bool runOnMachineFunction(MachineFunction &MF) override {
    for (const MachineBasicBlock &MBB : MF) {
      for (const MachineInstr &MI : MBB) {
        if (!MI.isCall())
          continue;
        bool HasMask = false;
        for (const MachineOperand &MO : MI.operands()) {
          if (MO.isRegMask()) {
            HasMask = true;
            break;
          }
        }
        assert(HasMask &&
               "V6CLANG CALL instruction missing register mask operand; "
               "IPRA requires every call to carry a mask (see O39).");
      }
    }
    return false;
  }
};

char V6ClangCallRegMaskVerifier::ID = 0;
#endif // NDEBUG

class V6ClangPassConfig : public TargetPassConfig {
public:
  V6ClangPassConfig(V6ClangTargetMachine &TM, PassManagerBase &PM)
      : TargetPassConfig(TM, PM) {}

  V6ClangTargetMachine &getV6ClangTargetMachine() const {
    return getTM<V6ClangTargetMachine>();
  }

  bool addInstSelector() override {
    addPass(createV6ClangISelDag(getV6ClangTargetMachine(),
                              getOptLevel()));
    return false;
  }

  void addPreRegAlloc() override {
    addPass(createV6ClangDeadPhiConstPass());
    addPass(createV6ClangConstantSinkingPass());
#ifndef NDEBUG
    addPass(new V6ClangCallRegMaskVerifier());
#endif
  }

  void addPostRegAlloc() override {
    if (getV6ClangStaticStackEnabled())
      addPass(createV6ClangStaticStackAllocPass());
    if (getV6ClangSpillPatchedReloadEnabled())
      addPass(createV6ClangSpillPatchedReloadPass());
    addPass(createV6ClangSpillForwardingPass());
    addPass(createV6ClangDebugFrameIndexPass());
  }

  void addPreEmitPass() override {
    // Post-RA optimization pipeline per design §8.1 Phase 3.
    // Order: AccumulatorPlanning → Peephole → LoadImmCombine → LoadStoreOpt →
    //        XchgOpt → BranchOpt → ZeroTestOpt → RedundantFlagElim →
    //        SPTrickOpt → StaticDebugValues → CFI
    addPass(createV6ClangAccumulatorPlanningPass());
    addPass(createV6ClangPeepholePass());
    addPass(createV6ClangLoadImmCombinePass());
    addPass(createV6ClangLoadStoreOptPass());
    addPass(createV6ClangXchgOptPass());
    addPass(createV6ClangBranchOptPass());
    addPass(createV6ClangZeroTestOptPass());
    addPass(createV6ClangRegValueForwardingPass());
    addPass(createV6ClangRedundantFlagElimPass());
    addPass(createV6ClangSPTrickOptPass());
    addPass(createV6ClangStaticDebugValuesPass());
    // Must run last: CFI describes the final optimized instruction stream.
    addPass(createV6ClangCFIPass());
  }

  void addIRPasses() override {
    TargetPassConfig::addIRPasses();
    addPass(createV6ClangLoopPointerInductionPass());
    addPass(createV6ClangTypeNarrowingPass());
    // Run last so it sees the final IR shape: alloca uses promoted from
    // the optimized loops above turn into immediate `LXI HL, @gv+offset`
    // forms in ISel, avoiding the V6ClangISD::DAD XCHG dance for stack-local
    // pointer arithmetic.
    addPass(createV6ClangAllocaPromotePass());
  }
};

} // namespace

TargetPassConfig *V6ClangTargetMachine::createPassConfig(PassManagerBase &PM) {
  return new V6ClangPassConfig(*this, PM);
}

TargetTransformInfo
V6ClangTargetMachine::getTargetTransformInfo(const Function &F) const {
  return TargetTransformInfo(V6ClangTTIImpl(this, F));
}

const V6ClangSubtarget *V6ClangTargetMachine::getSubtargetImpl() const {
  return &SubTarget;
}

const V6ClangSubtarget *
V6ClangTargetMachine::getSubtargetImpl(const Function &) const {
  return &SubTarget;
}

extern "C" LLVM_EXTERNAL_VISIBILITY void LLVMInitializeV6ClangTarget() {
  RegisterTargetMachine<V6ClangTargetMachine> X(getTheV6ClangTarget());
}

} // namespace llvm
