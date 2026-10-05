add_llvm_component_library(LLVMV6ClangDesc
  V6ClangAsmBackend.cpp
  V6ClangInstPrinter.cpp
  V6ClangMCAsmInfo.cpp
  V6ClangMCCodeEmitter.cpp
  V6ClangMCExpr.cpp
  V6ClangMCTargetDesc.cpp

  LINK_COMPONENTS
    MC
    Support
    V6ClangInfo

  ADD_TO_COMPONENT
    V6CLANG
)
