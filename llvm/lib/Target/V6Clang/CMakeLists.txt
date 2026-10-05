# V6CLANG Target — CMakeLists.txt
#
# Build the V6CLANG (Vector 06c / Intel 8080) LLVM backend.
# Enable with: cmake ... -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD="V6CLANG"

add_llvm_component_group(V6CLANG)

set(LLVM_TARGET_DEFINITIONS V6CLANG.td)

tablegen(LLVM V6ClangGenRegisterInfo.inc   -gen-register-info)
tablegen(LLVM V6ClangGenInstrInfo.inc      -gen-instr-info)
tablegen(LLVM V6ClangGenSubtargetInfo.inc  -gen-subtarget)
tablegen(LLVM V6ClangGenDAGISel.inc        -gen-dag-isel)
tablegen(LLVM V6ClangGenAsmWriter.inc      -gen-asm-writer)
tablegen(LLVM V6ClangGenAsmMatcher.inc     -gen-asm-matcher)
tablegen(LLVM V6ClangGenCallingConv.inc    -gen-callingconv)
tablegen(LLVM V6ClangGenMCCodeEmitter.inc  -gen-emitter)

add_public_tablegen_target(V6ClangCommonTableGen)

add_llvm_target(V6ClangCodeGen
  V6ClangAccumulatorPlanning.cpp
  V6ClangAsmPrinter.cpp
  V6ClangBranchOpt.cpp
  V6ClangCFI.cpp
  V6ClangConstantSinking.cpp
  V6ClangDeadPhiConst.cpp
  V6ClangDebugFrameIndex.cpp
  V6ClangFrameLowering.cpp
  V6ClangISelDAGToDAG.cpp
  V6ClangISelLowering.cpp
  V6ClangInstrInfo.cpp
  V6ClangLoadImmCombine.cpp
  V6ClangLoadStoreOpt.cpp
  V6ClangLoopPointerInduction.cpp
  V6ClangMCInstLower.cpp
  V6ClangPeephole.cpp
  V6ClangRedundantFlagElim.cpp
  V6ClangRegisterInfo.cpp
  V6ClangRegValueForwarding.cpp
  V6ClangSPTrickOpt.cpp
  V6ClangStaticDebugValues.cpp
  V6ClangSpillExpand.cpp
  V6ClangSpillForwarding.cpp
  V6ClangSpillPatchedReload.cpp
  V6ClangStaticStackAlloc.cpp
  V6ClangAllocaPromote.cpp
  V6ClangSubtarget.cpp
  V6ClangTargetMachine.cpp
  V6ClangTargetTransformInfo.cpp
  V6ClangTypeNarrowing.cpp
  V6ClangXchgOpt.cpp
  V6ClangZeroTestOpt.cpp

  LINK_COMPONENTS
    Analysis
    AsmPrinter
    CodeGen
    CodeGenTypes
    Core
    MC
    SelectionDAG
    Support
    Target
    V6ClangDesc
    V6ClangInfo

  ADD_TO_COMPONENT
    V6CLANG
)

add_subdirectory(AsmParser)
add_subdirectory(MCTargetDesc)
add_subdirectory(TargetInfo)
