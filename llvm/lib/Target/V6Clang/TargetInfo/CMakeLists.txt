add_llvm_component_library(LLVMV6ClangInfo
  V6ClangTargetInfo.cpp

  LINK_COMPONENTS
    MC
    Support

  ADD_TO_COMPONENT
    V6Clang
)
