//===-- V6ClangInstrFormats.td - V6CLANG Instruction Formats -------*- tablegen -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
// Encoding formats for the Intel 8080 instruction set.
// See design.md §4.3 for format descriptions.
//
// The 8080 uses a variable-length encoding: 1, 2, or 3 bytes.
// Byte 0 is always the opcode. Bytes 1-2 are immediate/address data.
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// Base instruction class
//===----------------------------------------------------------------------===//

class V6ClangInst<dag outs, dag ins, string asmstr, list<dag> pattern>
    : Instruction {
  let Namespace = "V6CLANG";
  let OutOperandList = outs;
  let InOperandList = ins;
  let AsmString = asmstr;
  let Pattern = pattern;
}

//===----------------------------------------------------------------------===//
// Pseudo-instruction (no encoding; expanded later)
//===----------------------------------------------------------------------===//

class V6ClangPseudo<dag outs, dag ins, string asmstr, list<dag> pattern>
    : V6ClangInst<outs, ins, asmstr, pattern> {
  let isPseudo = 1;
  let isCodeGenOnly = 1;
}

//===----------------------------------------------------------------------===//
// Implied format — 1 byte: [opcode]
// Used by: NOP, RET, XCHG, CMA, STC, CMC, HLT, EI, DI, RLC, RRC, RAL, RAR,
//          DAA, PCHL, SPHL, XTHL, Rcc
//===----------------------------------------------------------------------===//

class V6ClangInstImplied<bits<8> op, dag outs, dag ins, string asmstr,
                     list<dag> pattern>
    : V6ClangInst<outs, ins, asmstr, pattern> {
  field bits<8> Inst;
  let Inst = op;
  let Size = 1;
}

//===----------------------------------------------------------------------===//
// Reg format — 1 byte: [opcode | reg_field]
// The register encoding is placed within specific bit positions of the opcode.
//===----------------------------------------------------------------------===//

// RegDstSrc — MOV r,r — bits [5:3]=dst, bits [2:0]=src
// Opcode template: 01_DDD_SSS
class V6ClangInstRegDstSrc<dag outs, dag ins, string asmstr, list<dag> pattern>
    : V6ClangInst<outs, ins, asmstr, pattern> {
  bits<3> rd;   // destination register encoding
  bits<3> rs;   // source register encoding
  field bits<8> Inst;
  let Inst{7-6} = 0b01;
  let Inst{5-3} = rd;
  let Inst{2-0} = rs;
  let Size = 1;
}

// RegDst — INR r, DCR r — bits [5:3]=reg
// Opcode template: 00_DDD_LLL  (LLL = low 3 bits of opcode)
class V6ClangInstRegDst<bits<3> opc_lo, dag outs, dag ins,
                    string asmstr, list<dag> pattern>
    : V6ClangInst<outs, ins, asmstr, pattern> {
  bits<3> rd;
  field bits<8> Inst;
  let Inst{7-6} = 0b00;
  let Inst{5-3} = rd;
  let Inst{2-0} = opc_lo;
  let Size = 1;
}

// RegSrc — ALU ops (ADD r, SUB r, etc.) — bits [2:0]=src
// Opcode template: 10_OOO_SSS
class V6ClangInstRegSrc<bits<3> opc, dag outs, dag ins, string asmstr,
                    list<dag> pattern>
    : V6ClangInst<outs, ins, asmstr, pattern> {
  bits<3> rs;
  field bits<8> Inst;
  let Inst{7-6} = 0b10;
  let Inst{5-3} = opc;
  let Inst{2-0} = rs;
  let Size = 1;
}

// RegPair — operations on register pairs: bits [5:4]=rp
// Used by: INX rp, DCX rp, DAD rp, PUSH rp, POP rp
class V6ClangInstRegPair<bits<2> hi, bits<4> lo, dag outs, dag ins,
                     string asmstr, list<dag> pattern>
    : V6ClangInst<outs, ins, asmstr, pattern> {
  bits<2> rp;
  field bits<8> Inst;
  let Inst{7-6} = hi;
  let Inst{5-4} = rp;
  let Inst{3-0} = lo;
  let Size = 1;
}

//===----------------------------------------------------------------------===//
// Imm8 format — 2 bytes: [opcode][d8]
// Used by: MVI r,n, ADI, ACI, SUI, SBI, ANI, ORI, XRI, CPI, IN, OUT
//===----------------------------------------------------------------------===//

// Imm8Dst — MVI r,d8 — bits [5:3]=dest reg
// Opcode template: 00_DDD_110
class V6ClangInstImm8Dst<dag outs, dag ins, string asmstr, list<dag> pattern>
    : V6ClangInst<outs, ins, asmstr, pattern> {
  bits<3> rd;
  bits<8> imm;
  field bits<16> Inst;
  let Inst{15-14} = 0b00;
  let Inst{13-11} = rd;
  let Inst{10-8}  = 0b110;
  let Inst{7-0}   = imm;
  let Size = 2;
}

// Imm8Opc — ALU immediate (ADI, SUI, etc.) — fixed opcode + d8
// Opcode template: 11_OOO_110
class V6ClangInstImm8Opc<bits<3> opc, dag outs, dag ins, string asmstr,
                     list<dag> pattern>
    : V6ClangInst<outs, ins, asmstr, pattern> {
  bits<8> imm;
  field bits<16> Inst;
  let Inst{15-14} = 0b11;
  let Inst{13-11} = opc;
  let Inst{10-8}  = 0b110;
  let Inst{7-0}   = imm;
  let Size = 2;
}

//===----------------------------------------------------------------------===//
// Imm16 format — 3 bytes: [opcode][lo][hi]
// Used by: LXI rp,d16, JMP, Jcc, CALL, Ccc
//===----------------------------------------------------------------------===//

// Imm16Pair — LXI rp,d16 — bits [5:4]=rp
// Opcode template: 00_RP_0001
class V6ClangInstImm16Pair<dag outs, dag ins, string asmstr, list<dag> pattern>
    : V6ClangInst<outs, ins, asmstr, pattern> {
  bits<2> rp;
  bits<16> imm;
  field bits<24> Inst;
  let Inst{23-22} = 0b00;
  let Inst{21-20} = rp;
  let Inst{19-16} = 0b0001;
  let Inst{15-8}  = imm{7-0};   // low byte first
  let Inst{7-0}   = imm{15-8};  // high byte second
  let Size = 3;
}

// Imm16Opc — JMP, CALL, Jcc, Ccc — fixed opcode + d16
class V6ClangInstImm16Opc<bits<8> op, dag outs, dag ins, string asmstr,
                      list<dag> pattern>
    : V6ClangInst<outs, ins, asmstr, pattern> {
  bits<16> addr;
  field bits<24> Inst;
  let Inst{23-16} = op;
  let Inst{15-8}  = addr{7-0};   // low byte first
  let Inst{7-0}   = addr{15-8};  // high byte second
  let Size = 3;
}

// Imm16Cond — Conditional branch/call: [11_CCC_x1x][lo][hi]
// CCC=condition code, x bits distinguish JMP/CALL/RET
class V6ClangInstImm16Cond<bits<2> hi, bits<1> mid, bits<2> lo,
                       dag outs, dag ins, string asmstr, list<dag> pattern>
    : V6ClangInst<outs, ins, asmstr, pattern> {
  bits<3> cond;
  bits<16> addr;
  field bits<24> Inst;
  let Inst{23-22} = hi;
  let Inst{21-19} = cond;
  let Inst{18}    = mid;
  let Inst{17-16} = lo;
  let Inst{15-8}  = addr{7-0};
  let Inst{7-0}   = addr{15-8};
  let Size = 3;
}

//===----------------------------------------------------------------------===//
// Direct format — 3 bytes: [opcode][lo][hi]
// Used by: LDA addr, STA addr, LHLD addr, SHLD addr
// Same structure as Imm16Opc with a fixed opcode.
//===----------------------------------------------------------------------===//

// Reuse V6ClangInstImm16Opc for direct addressing instructions.

//===----------------------------------------------------------------------===//
// RST format — 1 byte: [11_NNN_111]
// Used by: RST 0-7
//===----------------------------------------------------------------------===//

class V6ClangInstRST<bits<3> n, dag outs, dag ins, string asmstr,
                 list<dag> pattern>
    : V6ClangInst<outs, ins, asmstr, pattern> {
  field bits<8> Inst;
  let Inst{7-6} = 0b11;
  let Inst{5-3} = n;
  let Inst{2-0} = 0b111;
  let Size = 1;
}

//===----------------------------------------------------------------------===//
// IO format — 2 bytes: [opcode][port]
// Used by: IN port, OUT port
//===----------------------------------------------------------------------===//

class V6ClangInstIO<bits<8> op, dag outs, dag ins, string asmstr,
                list<dag> pattern>
    : V6ClangInst<outs, ins, asmstr, pattern> {
  bits<8> port;
  field bits<16> Inst;
  let Inst{15-8} = op;
  let Inst{7-0}  = port;
  let Size = 2;
}
