// V6CLANG.td - Top-level TableGen description for the V6CLANG (Vector 06c) target
//
// This is the root TableGen file for the Intel 8080-based Vector 06c backend.
// It includes all target-specific definitions: registers, instructions,
// calling conventions, and scheduling model.

include "llvm/Target/Target.td"

//===----------------------------------------------------------------------===//
// Included definitions
//===----------------------------------------------------------------------===//

include "V6ClangRegisterInfo.td"
include "V6ClangSchedule.td"
include "V6ClangInstrInfo.td"
include "V6ClangCallingConv.td"

//===----------------------------------------------------------------------===//
// V6CLANG Target Definition
//===----------------------------------------------------------------------===//

def V6ClangInstrInfo : InstrInfo;

//===----------------------------------------------------------------------===//
// V6CLANG Processor Definition
//===----------------------------------------------------------------------===//

def : ProcessorModel<"i8080", V6ClangModel, []>;

def V6ClangAsmWriter : AsmWriter {
  string AsmWriterClassName = "InstPrinter";
  int PassSubtarget = 0;
  int Variant = 0;
}

def V6ClangAsmParser : AsmParser {
  // Operands of the V6CLANG asm dialect are space- or comma-separated; tokens
  // such as "M" appear as literal mnemonic text in the .td asm strings.
}

def V6CLANG : Target {
  let InstructionSet = V6ClangInstrInfo;
  let AssemblyWriters = [V6ClangAsmWriter];
  let AssemblyParsers = [V6ClangAsmParser];
}
