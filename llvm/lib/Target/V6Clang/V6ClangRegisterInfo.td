//===-- V6ClangRegisterInfo.td - V6CLANG Register Definitions ------*- tablegen -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
// Register definitions for the Intel 8080 / KR580VM80A CPU.
// See design.md §3 for register architecture details.
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// Sub-register indices
//===----------------------------------------------------------------------===//

let Namespace = "V6CLANG" in {
  def sub_lo : SubRegIndex<8>;       // Low byte (offset 0)
  def sub_hi : SubRegIndex<8, 8>;    // High byte (offset 8)
}

//===----------------------------------------------------------------------===//
// Register alternate-name indices
//===----------------------------------------------------------------------===//

// Pair8080 — i8080-canonical pair-form mnemonics used by every instruction
// that takes a register-pair operand (PUSH, POP, INX, DCX, DAD, LXI, LDAX,
// STAX). Maps BC->"B", DE->"D", HL->"H", SP->"SP", PSW->"PSW".
def Pair8080 : RegAltNameIndex;

//===----------------------------------------------------------------------===//
// 8-bit Registers
//===----------------------------------------------------------------------===//

// HWEncoding matches the 8080 3-bit register encoding:
//   B=000, C=001, D=010, E=011, H=100, L=101, (M=110), A=111
class V6ClangReg<bits<16> Enc, string n> : Register<n> {
  let HWEncoding = Enc;
  let Namespace = "V6CLANG";
}

def B : V6ClangReg<0, "B">, DwarfRegNum<[1]>;
def C : V6ClangReg<1, "C">, DwarfRegNum<[2]>;
def D : V6ClangReg<2, "D">, DwarfRegNum<[3]>;
def E : V6ClangReg<3, "E">, DwarfRegNum<[4]>;
def H : V6ClangReg<4, "H">, DwarfRegNum<[5]>;
def L : V6ClangReg<5, "L">, DwarfRegNum<[6]>;
def A : V6ClangReg<7, "A">, DwarfRegNum<[0]>;

// FLAGS register (not directly addressable by 8080 instructions).
def FLAGS : V6ClangReg<6, "FLAGS">;

//===----------------------------------------------------------------------===//
// 16-bit Register Pairs
//===----------------------------------------------------------------------===//

// HWEncoding for pairs uses the 2-bit register-pair field:
//   BC=00, DE=01, HL=10, SP=11
class V6ClangRegPair<bits<16> Enc, string n, list<Register> subregs>
    : RegisterWithSubRegs<n, subregs> {
  let HWEncoding = Enc;
  let Namespace = "V6CLANG";
  let SubRegIndices = [sub_lo, sub_hi];
  let CoveredBySubRegs = 1;
}

// Note: subregs = [lo, hi] following LLVM convention
let RegAltNameIndices = [Pair8080] in {
  def BC  : V6ClangRegPair<0, "BC",  [C, B]>, DwarfRegNum<[7]>
                                                { let AltNames = ["B"];   }
  def DE  : V6ClangRegPair<1, "DE",  [E, D]>, DwarfRegNum<[8]>
                                                { let AltNames = ["D"];   }
  def HL  : V6ClangRegPair<2, "HL",  [L, H]>, DwarfRegNum<[9]>
                                                { let AltNames = ["H"];   }
  def PSW : V6ClangRegPair<3, "PSW", [FLAGS, A]> { let AltNames = ["PSW"]; }
}

// SP is a standalone 16-bit register (not a sub-register pair).
let RegAltNameIndices = [Pair8080] in
def SP : V6ClangReg<3, "SP">, DwarfRegNum<[10]> { let AltNames = ["SP"]; }

// PC is implicit and non-allocatable. It exists so DWARF CFI has a stable
// return-address column.
def PC : V6ClangReg<0, "PC">, DwarfRegNum<[11]>;

//===----------------------------------------------------------------------===//
// Register Classes (per design §3.2)
//===----------------------------------------------------------------------===//

// GR8 — General 8-bit registers.
// Allocation order: A, L, H, E, D, C, B (per design §3.4).
def GR8 : RegisterClass<"V6CLANG", [i8], 8, (add A, L, H, E, D, C, B)>;

// GR8NoA — All 8-bit GPRs except the accumulator.
def GR8NoA : RegisterClass<"V6CLANG", [i8], 8, (add L, H, E, D, C, B)>;

// GR8NoHL — 8-bit GPRs excluding H/L, used by stack-relative stores whose
// expansion uses HL as an address scratch before reading the source operand.
def GR8NoHL : RegisterClass<"V6CLANG", [i8], 8, (add A, E, D, C, B)>;

// Acc — Singleton accumulator class.
def Acc : RegisterClass<"V6CLANG", [i8], 8, (add A)>;

// GR16 — General 16-bit register pairs (BC, DE, HL).
def GR16 : RegisterClass<"V6CLANG", [i16], 8, (add HL, DE, BC)>;

// GR16Ptr — Memory pointer (HL only, for M operand).
def GR16Ptr : RegisterClass<"V6CLANG", [i16], 8, (add HL)>;

// GR16Idx — Index pairs for LDAX/STAX (BC, DE only).
def GR16Idx : RegisterClass<"V6CLANG", [i16], 8, (add BC, DE)>;

// GR16SP — Stack pointer only.
def GR16SP : RegisterClass<"V6CLANG", [i16], 8, (add SP)>;

// GR16All — All 16-bit operands including SP (for LXI, INX, DCX, DAD).
def GR16All : RegisterClass<"V6CLANG", [i16], 8, (add HL, DE, BC, SP)>;

// GR16Stack — Operand class for PUSH/POP (encoding RP=11 means PSW, not SP).
// 8080 valid operands: BC, DE, HL, PSW. Non-allocatable; all uses come from
// frame-lowering / pseudo-expansion with pre-assigned physregs.
def GR16Stack : RegisterClass<"V6CLANG", [i16], 8, (add HL, DE, BC, PSW)> {
  let CopyCost = -1;
  let isAllocatable = 0;
}

// FlagReg — Implicit def/use on ALU/compare instructions.
def FlagReg : RegisterClass<"V6CLANG", [i8], 8, (add FLAGS)> {
  let CopyCost = -1;
  let isAllocatable = 0;
}
