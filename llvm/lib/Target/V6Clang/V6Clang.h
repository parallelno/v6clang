//===-- V6Clang.h - Top-level interface for V6CLANG representation ------*- C++ -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_V6CLANG_V6CLANG_H
#define LLVM_LIB_TARGET_V6CLANG_V6CLANG_H

#include "llvm/Target/TargetMachine.h"

namespace llvm {

class V6ClangTargetMachine;
class FunctionPass;
class ModulePass;

FunctionPass *createV6ClangISelDag(V6ClangTargetMachine &TM,
                                CodeGenOptLevel OptLevel);

/// Get the configured V6CLANG start address (-mv6clang-start-address, default 0x0100).
unsigned getV6ClangStartAddress();

/// Whether static stack allocation is enabled (-mv6clang-static-stack).
bool getV6ClangStaticStackEnabled();

/// Whether pseudo expansion annotation comments are enabled.
bool getV6ClangAnnotatePseudosEnabled();

/// Whether v6clang_arith.h runtime helpers should be emitted into asm output.
bool getV6ClangPrintRTHelpersEnabled();

/// Whether the O61 spill-patched-reload rewrite is enabled.
bool getV6ClangSpillPatchedReloadEnabled();

/// Pre-RA optimization pass: constant sinking past branches (O37).
FunctionPass *createV6ClangConstantSinkingPass();

/// Pre-RA optimization pass: dead PHI-constant elimination (O31).
FunctionPass *createV6ClangDeadPhiConstPass();

/// Post-RA optimization passes (M8).
FunctionPass *createV6ClangZeroTestOptPass();
FunctionPass *createV6ClangRedundantFlagElimPass();
FunctionPass *createV6ClangXchgOptPass();
FunctionPass *createV6ClangPeepholePass();
FunctionPass *createV6ClangBranchOptPass();
FunctionPass *createV6ClangLoadStoreOptPass();
FunctionPass *createV6ClangAccumulatorPlanningPass();
FunctionPass *createV6ClangLoadImmCombinePass();
FunctionPass *createV6ClangSPTrickOptPass();

/// Post-O61 pass: replace debug frame indices with final static or patch-byte
/// locations before generic PEI lowers remaining stack references.
FunctionPass *createV6ClangDebugFrameIndexPass();

/// Final pass: salvage globals created by V6CLANG alloca promotion as locations.
FunctionPass *createV6ClangStaticDebugValuesPass();

/// Final pass: emit precise DWARF call-frame rules from the optimized stream.
FunctionPass *createV6ClangCFIPass();

/// Post-RA pass: unified cross-BB physical-register value forwarding (O92).
FunctionPass *createV6ClangRegValueForwardingPass();

/// IR-level optimization pass (M8).
FunctionPass *createV6ClangTypeNarrowingPass();

/// IR-level pass: convert loop base+counter to running pointer induction.
FunctionPass *createV6ClangLoopPointerInductionPass();

/// Post-RA pass: static stack allocation for non-reentrant functions (O10).
FunctionPass *createV6ClangStaticStackAllocPass();

/// IR-level pass: promote allocas of non-reentrant functions to per-function
/// globals before SelectionDAG ISel (companion to V6ClangStaticStackAlloc).
ModulePass *createV6ClangAllocaPromotePass();

/// Post-RA pass: spill forwarding (O16).
FunctionPass *createV6ClangSpillForwardingPass();

/// Post-RA pass: O61 Stage 1 - rewrite HL spill/reload pairs as patched LXI.
FunctionPass *createV6ClangSpillPatchedReloadPass();

} // namespace llvm

extern "C" void LLVMInitializeV6ClangAsmParser();

#endif // LLVM_LIB_TARGET_V6CLANG_V6CLANG_H
