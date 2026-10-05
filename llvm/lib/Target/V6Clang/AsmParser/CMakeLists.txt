# V6CLANG AsmParser — TableGen-driven assembly parser for the i8080-canonical
# V6CLANG assembly dialect. Built only when V6CLANG is in LLVM_EXPERIMENTAL_TARGETS.

add_llvm_component_library(LLVMV6ClangAsmParser
  V6ClangAsmParser.cpp

  LINK_COMPONENTS
    MC
    MCParser
    Support
    V6ClangDesc
    V6ClangInfo

  ADD_TO_COMPONENT
    V6CLANG
)
