//===-- V6ClangInstrInfo.td - V6CLANG Instruction Definitions ------*- tablegen -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
// Complete instruction set for the Intel 8080 / KR580VM80A.
// See design.md §4.2 for instruction categories and modeling notes.
//
// Encoding reference: Intel 8080 opcode map.
// All encodings validated against v6asm output (plan M2 step 9).
//
//===----------------------------------------------------------------------===//

include "V6ClangInstrFormats.td"

//===----------------------------------------------------------------------===//
// Operand types
//===----------------------------------------------------------------------===//

def imm8  : Operand<i8> {
  let PrintMethod = "printImm8Operand";
}
def imm16 : Operand<i16>;
def i8port : Operand<i8> {
  let PrintMethod = "printImm8Operand";
}

// Branch target (16-bit absolute address)
def brtarget : Operand<OtherVT> {
  let PrintMethod = "printBrTarget";
}

// Register-pair operand wrappers that print the i8080-canonical single-letter
// pair name (BC->"B", DE->"D", HL->"H", SP->"SP", PSW->"PSW"). Encoding and
// register-class matching are inherited from the underlying class — only the
// printed mnemonic changes.
def GR16AllPair   : RegisterOperand<GR16All,   "printRegPair8080">;
def GR16IdxPair   : RegisterOperand<GR16Idx,   "printRegPair8080">;
def GR16StackPair : RegisterOperand<GR16Stack, "printRegPair8080">;

//===----------------------------------------------------------------------===//
// 8080 Condition codes (3-bit encoding for Jcc/Ccc/Rcc)
//===----------------------------------------------------------------------===//
//   NZ=000, Z=001, NC=010, C=011, PO=100, PE=101, P=110, M=111

//===----------------------------------------------------------------------===//
// V6CLANG-specific SDNode definitions
//===----------------------------------------------------------------------===//

def SDT_V6ClangRet     : SDTypeProfile<0, 0, []>;
def SDT_V6ClangCall    : SDTypeProfile<0, 1, [SDTCisVT<0, iPTR>]>;

// O75 Phase A: FLAGS travels as an SSA-typed i8 value, not glue. The i8
// "flags" output is bound to the physical FLAGS register at TableGen
// pattern level (see CMPr/CPI/V6Clang_CMP16/V6Clang_BRCOND/V6Clang_SELECT_CC).
//
// V6Clangcmp:     (i8 flags) = cmp(T lhs, T rhs)   ; T is i8 or i16
def SDT_V6ClangCmp     : SDTypeProfile<1, 2, [SDTCisVT<0, i8>,
                                           SDTCisSameAs<1, 2>,
                                           SDTCisInt<1>]>;
// V6Clangbrcond:  brcond(chain, dst, cc, i8 flags)
def SDT_V6ClangBrCond  : SDTypeProfile<0, 3, [SDTCisVT<0, OtherVT>,
                                           SDTCisVT<1, i8>,
                                           SDTCisVT<2, i8>]>;
// V6Clangselectcc: (T) = selectcc(T true, T false, cc, i8 flags)
def SDT_V6ClangSelectCC : SDTypeProfile<1, 4, [SDTCisSameAs<0, 1>,
                                            SDTCisSameAs<1, 2>,
                                            SDTCisVT<3, i8>,
                                            SDTCisVT<4, i8>]>;
def SDT_V6ClangWrapper : SDTypeProfile<1, 1, [SDTCisSameAs<0, 1>,
                                           SDTCisPtrTy<0>]>;

def V6Clangretflag  : SDNode<"V6ClangISD::RET", SDTNone,
                          [SDNPHasChain, SDNPOptInGlue, SDNPVariadic]>;
def V6Clangcall     : SDNode<"V6ClangISD::CALL", SDT_V6ClangCall,
                          [SDNPHasChain, SDNPOutGlue, SDNPOptInGlue,
                           SDNPVariadic]>;
def V6Clangcmp      : SDNode<"V6ClangISD::CMP", SDT_V6ClangCmp, []>;

// CMP_ZERO: zero-test a single i16 value, produces FLAGS (i8 SSA).
def SDT_V6ClangCmpZero : SDTypeProfile<1, 1, [SDTCisVT<0, i8>, SDTCisVT<1, i16>]>;
def V6Clangcmpzero : SDNode<"V6ClangISD::CMP_ZERO", SDT_V6ClangCmpZero, []>;

// CMP_SIGN: sign-test a single i16 value, produces FLAGS (i8 SSA).
def V6Clangcmpsign : SDNode<"V6ClangISD::CMP_SIGN", SDT_V6ClangCmpZero, []>;

def V6Clangbrcond   : SDNode<"V6ClangISD::BRCOND", SDT_V6ClangBrCond,
                          [SDNPHasChain]>;
def V6Clangselectcc : SDNode<"V6ClangISD::SELECT_CC", SDT_V6ClangSelectCC, []>;
def V6Clangwrapper  : SDNode<"V6ClangISD::Wrapper", SDT_V6ClangWrapper>;

// BR_CC16: chain, lhs(i16), rhs(i16), cc(i8), dest(OtherVT) → chain
def SDT_V6ClangBrCC16 : SDTypeProfile<0, 4, [SDTCisVT<0, i16>,
                                          SDTCisVT<1, i16>,
                                          SDTCisVT<2, i8>,
                                          SDTCisVT<3, OtherVT>]>;
def V6Clangbrcc16 : SDNode<"V6ClangISD::BR_CC16", SDT_V6ClangBrCC16,
                        [SDNPHasChain]>;

// O75 Phase B: flag-producing 8-bit arithmetic.
//   *F      : (i8 dst, i8 flags) = OP(i8 lhs, i8 rs)
//   *F_IMM  : (i8 dst, i8 flags) = OP(i8 lhs, i8imm)
//   INCF/DECF: (i8 dst, i8 flags) = OP(i8 src)
def SDT_V6ClangArithF    : SDTypeProfile<2, 2, [SDTCisVT<0, i8>,
                                             SDTCisVT<1, i8>,
                                             SDTCisVT<2, i8>,
                                             SDTCisVT<3, i8>]>;
def SDT_V6ClangIncDecF   : SDTypeProfile<2, 1, [SDTCisVT<0, i8>,
                                             SDTCisVT<1, i8>,
                                             SDTCisVT<2, i8>]>;

def V6Clangaddf      : SDNode<"V6ClangISD::ADDF",     SDT_V6ClangArithF, [SDNPCommutative]>;
def V6Clangsubf      : SDNode<"V6ClangISD::SUBF",     SDT_V6ClangArithF, []>;
def V6Clangandf      : SDNode<"V6ClangISD::ANDF",     SDT_V6ClangArithF, [SDNPCommutative]>;
def V6Clangorf       : SDNode<"V6ClangISD::ORF",      SDT_V6ClangArithF, [SDNPCommutative]>;
def V6Clangxorf      : SDNode<"V6ClangISD::XORF",     SDT_V6ClangArithF, [SDNPCommutative]>;
def V6Clangaddf_imm  : SDNode<"V6ClangISD::ADDF_IMM", SDT_V6ClangArithF, []>;
def V6Clangsubf_imm  : SDNode<"V6ClangISD::SUBF_IMM", SDT_V6ClangArithF, []>;
def V6Clangandf_imm  : SDNode<"V6ClangISD::ANDF_IMM", SDT_V6ClangArithF, []>;
def V6Clangorf_imm   : SDNode<"V6ClangISD::ORF_IMM",  SDT_V6ClangArithF, []>;
def V6Clangxorf_imm  : SDNode<"V6ClangISD::XORF_IMM", SDT_V6ClangArithF, []>;
def V6Clangincf      : SDNode<"V6ClangISD::INCF",     SDT_V6ClangIncDecF, []>;
def V6Clangdecf      : SDNode<"V6ClangISD::DECF",     SDT_V6ClangIncDecF, []>;

// SEXT: sign-extend i8 to i16
def SDT_V6ClangSext : SDTypeProfile<1, 1, [SDTCisVT<0, i16>, SDTCisVT<1, i8>]>;
def V6Clangsext    : SDNode<"V6ClangISD::SEXT", SDT_V6ClangSext>;

// NEG8: result-only i8 negate from canonical sub 0, x.
def SDT_V6ClangNeg8 : SDTypeProfile<1, 1, [SDTCisVT<0, i8>, SDTCisVT<1, i8>]>;
def V6Clangneg8     : SDNode<"V6ClangISD::NEG8", SDT_V6ClangNeg8>;

// Strategy-specific constant i16 shift SDNodes.
def SDT_V6ClangShift16 : SDTypeProfile<1, 2, [SDTCisVT<0, i16>,
                                            SDTCisVT<1, i16>,
                                            SDTCisVT<2, i8>]>;
def V6Clangshl16_dad    : SDNode<"V6ClangISD::SHL16_DAD", SDT_V6ClangShift16>;
def V6Clangshl16_byte   : SDNode<"V6ClangISD::SHL16_BYTE", SDT_V6ClangShift16>;
def V6Clangshl16_ram_hi : SDNode<"V6ClangISD::SHL16_RAM_HI", SDT_V6ClangShift16>;
def V6Clangsrl16_rar    : SDNode<"V6ClangISD::SRL16_RAR", SDT_V6ClangShift16>;
def V6Clangsrl16_24bit  : SDNode<"V6ClangISD::SRL16_24BIT", SDT_V6ClangShift16>;
def V6Clangsrl16_byte   : SDNode<"V6ClangISD::SRL16_BYTE", SDT_V6ClangShift16>;
def V6Clangsrl16_ram_lo : SDNode<"V6ClangISD::SRL16_RAM_LO", SDT_V6ClangShift16>;
def V6Clangsra16_rar    : SDNode<"V6ClangISD::SRA16_RAR", SDT_V6ClangShift16>;
def V6Clangsra16_24bit  : SDNode<"V6ClangISD::SRA16_24BIT", SDT_V6ClangShift16>;
def V6Clangsra16_byte   : SDNode<"V6ClangISD::SRA16_BYTE", SDT_V6ClangShift16>;
def V6Clangsra16_ram_lo : SDNode<"V6ClangISD::SRA16_RAM_LO", SDT_V6ClangShift16>;

// DAD: 16-bit add constrained to HL pair (maps to physical DAD rp).
// SDNPCommutative intentionally absent: the combine canonicalises the
// HL-bound operand as LHS; dropping commutative prevents the DAG combiner
// from swapping the operands back and forcing an unnecessary HL reload.
def V6Clangdad : SDNode<"V6ClangISD::DAD", SDTIntBinOp, []>;

// INX16/DCX16: increment/decrement i16 by immediate i8 count (1..3).
def SDT_V6ClangInxDcx16 : SDTypeProfile<1, 2, [SDTCisVT<0, i16>,
                                             SDTCisVT<1, i16>,
                                             SDTCisVT<2, i8>]>;
def V6Clanginx16 : SDNode<"V6ClangISD::INX16", SDT_V6ClangInxDcx16>;
def V6Clangdcx16 : SDNode<"V6ClangISD::DCX16", SDT_V6ClangInxDcx16>;

// O67: ROTL8/ROTR8 — 1-bit accumulator rotates (RLC/RRC). Custom
// lowering of ISD::ROTL/ROTR i8 emits a chain of these.
def SDT_V6ClangRot8 : SDTypeProfile<1, 1, [SDTCisVT<0, i8>, SDTCisVT<1, i8>]>;
def V6Clangrotl8 : SDNode<"V6ClangISD::ROTL8", SDT_V6ClangRot8>;
def V6Clangrotr8 : SDNode<"V6ClangISD::ROTR8", SDT_V6ClangRot8>;

// O68 Phase 2: ROTL16_1 — i16 rotate-left by 1 (DAD H + ACI 0 fold).
def SDT_V6ClangRotL16_1 : SDTypeProfile<1, 1, [SDTCisVT<0, i16>, SDTCisVT<1, i16>]>;
def V6Clangrotl16_1     : SDNode<"V6ClangISD::ROTL16_1", SDT_V6ClangRotL16_1>;

//===----------------------------------------------------------------------===//
// V6CLANG condition codes (used in BRCOND and SELECT_CC)
//===----------------------------------------------------------------------===//

def V6ClangCC_NZ : PatLeaf<(i8 0)>;   // Not zero
def V6ClangCC_Z  : PatLeaf<(i8 1)>;   // Zero
def V6ClangCC_NC : PatLeaf<(i8 2)>;   // No carry
def V6ClangCC_C  : PatLeaf<(i8 3)>;   // Carry
def V6ClangCC_PO : PatLeaf<(i8 4)>;   // Parity odd
def V6ClangCC_PE : PatLeaf<(i8 5)>;   // Parity even
def V6ClangCC_P  : PatLeaf<(i8 6)>;   // Plus (positive)
def V6ClangCC_M  : PatLeaf<(i8 7)>;   // Minus (negative)

//===----------------------------------------------------------------------===//
// Data Move — MOV, MVI
//===----------------------------------------------------------------------===//

// MOV r,r — 01_DDD_SSS (register-to-register)
def MOVrr : V6ClangInstRegDstSrc<
    (outs GR8:$rd), (ins GR8:$rs),
    "MOV\t$rd, $rs", []>;

// MOV r,M — 01_DDD_110 (memory-to-register, via HL pointer)
let Uses = [HL], mayLoad = 1 in
def MOVrM : V6ClangInstRegDst<0b110,
    (outs GR8:$rd), (ins),
    "MOV\t$rd, M", []> {
  let Inst{7-6} = 0b01;
}

// MOV M,r — 01_110_SSS (register-to-memory, via HL pointer)
let Uses = [HL], mayStore = 1 in
def MOVMr : V6ClangInstRegSrc<0b110,
    (outs), (ins GR8:$rs),
    "MOV\tM, $rs", []> {
  let Inst{7-6} = 0b01;
  let Inst{5-3} = 0b110;
}

// MVI r,d8 — 00_DDD_110 [d8]
let isReMaterializable = 1, isAsCheapAsAMove = 1 in
def MVIr : V6ClangInstImm8Dst<
    (outs GR8:$rd), (ins imm8:$imm),
    "MVI\t$rd, $imm", [(set i8:$rd, (i8 imm:$imm))]>;

// MVI M,d8 — 00_110_110 [d8] = 0x36
let Uses = [HL], mayStore = 1 in
def MVIM : V6ClangInstImm8Opc<0b110,
    (outs), (ins imm8:$imm),
    "MVI\tM, $imm", []> {
  let Inst{15-14} = 0b00;
  let Inst{10-8}  = 0b110;
}

//===----------------------------------------------------------------------===//
// Data Move — LDA, STA, LDAX, STAX, LHLD, SHLD
//===----------------------------------------------------------------------===//

// LDA addr — 0x3A [lo] [hi]
let mayLoad = 1 in
def LDA : V6ClangInstImm16Opc<0x3A,
    (outs Acc:$dst), (ins imm16:$addr),
    "LDA\t$addr", []>;

// STA addr — 0x32 [lo] [hi]
let mayStore = 1 in
def STA : V6ClangInstImm16Opc<0x32,
    (outs), (ins Acc:$src, imm16:$addr),
    "STA\t$addr", []>;

// LDAX rp — 00_RP_1010 (rp = BC or DE)
let mayLoad = 1 in
def LDAX : V6ClangInstRegPair<0b00, 0b1010,
    (outs Acc:$dst), (ins GR16IdxPair:$rp),
    "LDAX\t$rp", []>;

// STAX rp — 00_RP_0010 (rp = BC or DE)
let mayStore = 1 in
def STAX : V6ClangInstRegPair<0b00, 0b0010,
    (outs), (ins Acc:$src, GR16IdxPair:$rp),
    "STAX\t$rp", []>;

// LHLD addr — 0x2A [lo] [hi]
// Always loads into HL (implicit). Modeled with GR16Ptr output for regalloc.
let mayLoad = 1 in
def LHLD : V6ClangInstImm16Opc<0x2A,
    (outs GR16Ptr:$dst), (ins imm16:$addr),
    "LHLD\t$addr", []>;

// SHLD addr — 0x22 [lo] [hi]
// Always stores from HL (implicit). Modeled with GR16Ptr input for regalloc.
let mayStore = 1 in
def SHLD : V6ClangInstImm16Opc<0x22,
    (outs), (ins GR16Ptr:$src, imm16:$addr),
    "SHLD\t$addr", []>;

//===----------------------------------------------------------------------===//
// Data Move — LXI (load immediate 16-bit)
//===----------------------------------------------------------------------===//

// LXI rp,d16 — 00_RP_0001 [lo] [hi]
let isReMaterializable = 1, isAsCheapAsAMove = 1 in
def LXI : V6ClangInstImm16Pair<
    (outs GR16AllPair:$rp), (ins imm16:$imm),
    "LXI\t$rp, $imm", []>;

//===----------------------------------------------------------------------===//
// Data Move — XCHG
//===----------------------------------------------------------------------===//

// XCHG — 0xEB — Exchange DE and HL
let Defs = [DE, HL], Uses = [DE, HL] in
def XCHG : V6ClangInstImplied<0xEB,
    (outs), (ins),
    "XCHG", []>;

//===----------------------------------------------------------------------===//
// Stack Operations — PUSH, POP, SPHL, XTHL
//===----------------------------------------------------------------------===//

// PUSH rp — 11_RP_0101 (rp: BC=00, DE=01, HL=10, PSW=11)
let Uses = [SP], Defs = [SP], mayStore = 1 in
def PUSH : V6ClangInstRegPair<0b11, 0b0101,
    (outs), (ins GR16StackPair:$rp),
    "PUSH\t$rp", []>;

// POP rp — 11_RP_0001 (rp: BC=00, DE=01, HL=10, PSW=11)
let Uses = [SP], Defs = [SP], mayLoad = 1 in
def POP : V6ClangInstRegPair<0b11, 0b0001,
    (outs GR16StackPair:$rp), (ins),
    "POP\t$rp", []>;

// SPHL — 0xF9 — Load SP from HL
let Uses = [HL], Defs = [SP] in
def SPHL : V6ClangInstImplied<0xF9,
    (outs), (ins),
    "SPHL", []>;

// XTHL — 0xE3 — Exchange top-of-stack with HL
let Uses = [SP, HL], Defs = [HL], mayLoad = 1, mayStore = 1 in
def XTHL : V6ClangInstImplied<0xE3,
    (outs), (ins),
    "XTHL", []>;

//===----------------------------------------------------------------------===//
// ALU 8-bit — Register operand: ADD, ADC, SUB, SBB, ANA, ORA, XRA, CMP
// Format: 10_OOO_SSS
//
// OPC encoding: ADD=000, ADC=001, SUB=010, SBB=011,
//               ANA=100, XRA=101, ORA=110, CMP=111
//
// All arithmetic/logic ops use the accumulator (A) as implicit LHS and
// destination.  We model A as an explicit Acc operand so the register
// allocator sees the data-flow.  FLAGS is an implicit def.
//===----------------------------------------------------------------------===//

// --- Register source variants ---

// Ops that read and write A — explicit Acc in/out, FLAGS implicit def.
// O75 Phase B: patterns produce both value and flags via V6ClangISD::*F.
let Defs = [FLAGS] in {
  let Constraints = "$dst = $lhs" in {
    let isCommutable = 1 in
    def ADDr : V6ClangInstRegSrc<0b000,
        (outs Acc:$dst), (ins Acc:$lhs, GR8:$rs),
        "ADD\t$rs", [(set i8:$dst, FLAGS, (V6Clangaddf i8:$lhs, i8:$rs))]>;
    let Uses = [FLAGS] in  // ADC reads CY
    let isCommutable = 1 in
    def ADCr : V6ClangInstRegSrc<0b001,
        (outs Acc:$dst), (ins Acc:$lhs, GR8:$rs),
        "ADC\t$rs", []>;
    def SUBr : V6ClangInstRegSrc<0b010,
        (outs Acc:$dst), (ins Acc:$lhs, GR8:$rs),
        "SUB\t$rs", [(set i8:$dst, FLAGS, (V6Clangsubf i8:$lhs, i8:$rs))]>;
    let Uses = [FLAGS] in  // SBB reads CY
    def SBBr : V6ClangInstRegSrc<0b011,
        (outs Acc:$dst), (ins Acc:$lhs, GR8:$rs),
        "SBB\t$rs", []>;
    let isCommutable = 1 in
    def ANAr : V6ClangInstRegSrc<0b100,
        (outs Acc:$dst), (ins Acc:$lhs, GR8:$rs),
        "ANA\t$rs", [(set i8:$dst, FLAGS, (V6Clangandf i8:$lhs, i8:$rs))]>;
    let isCommutable = 1 in
    def XRAr : V6ClangInstRegSrc<0b101,
        (outs Acc:$dst), (ins Acc:$lhs, GR8:$rs),
        "XRA\t$rs", [(set i8:$dst, FLAGS, (V6Clangxorf i8:$lhs, i8:$rs))]>;
    let isCommutable = 1 in
    def ORAr : V6ClangInstRegSrc<0b110,
        (outs Acc:$dst), (ins Acc:$lhs, GR8:$rs),
        "ORA\t$rs", [(set i8:$dst, FLAGS, (V6Clangorf i8:$lhs, i8:$rs))]>;
  }

  // CMP: reads A but does NOT modify it — no output, sets FLAGS only
  def CMPr : V6ClangInstRegSrc<0b111,
      (outs), (ins Acc:$lhs, GR8:$rs),
      "CMP\t$rs", [(set FLAGS, (V6Clangcmp i8:$lhs, i8:$rs))]>;
}

// --- Memory (M via HL) source variants ---
// Same opcode pattern but src bits = 110 (M)
// Explicit Acc in/out, FLAGS implicit def, HL implicit use.

let Defs = [FLAGS], Uses = [HL], mayLoad = 1 in {
  let Constraints = "$dst = $lhs" in {
    def ADDM : V6ClangInstImplied<0x86, (outs Acc:$dst), (ins Acc:$lhs), "ADD\tM", []>;
    let Uses = [HL, FLAGS] in  // ADC reads CY
    def ADCM : V6ClangInstImplied<0x8E, (outs Acc:$dst), (ins Acc:$lhs), "ADC\tM", []>;
    def SUBM : V6ClangInstImplied<0x96, (outs Acc:$dst), (ins Acc:$lhs), "SUB\tM", []>;
    let Uses = [HL, FLAGS] in  // SBB reads CY
    def SBBM : V6ClangInstImplied<0x9E, (outs Acc:$dst), (ins Acc:$lhs), "SBB\tM", []>;
    def ANAM : V6ClangInstImplied<0xA6, (outs Acc:$dst), (ins Acc:$lhs), "ANA\tM", []>;
    def XRAM : V6ClangInstImplied<0xAE, (outs Acc:$dst), (ins Acc:$lhs), "XRA\tM", []>;
    def ORAM : V6ClangInstImplied<0xB6, (outs Acc:$dst), (ins Acc:$lhs), "ORA\tM", []>;
  }
  // CMP M: reads A, does NOT modify it
  def CMPM : V6ClangInstImplied<0xBE, (outs), (ins Acc:$lhs), "CMP\tM", []>;
}

//===----------------------------------------------------------------------===//
// ALU 8-bit — Immediate: ADI, ACI, SUI, SBI, ANI, ORI, XRI, CPI
// Format: 11_OOO_110 [d8]
//===----------------------------------------------------------------------===//

let Defs = [FLAGS] in {
  let Constraints = "$dst = $lhs" in {
    def ADI : V6ClangInstImm8Opc<0b000,
        (outs Acc:$dst), (ins Acc:$lhs, imm8:$imm),
        "ADI\t$imm",
        [(set i8:$dst, FLAGS, (V6Clangaddf_imm i8:$lhs, (i8 imm:$imm)))]>;
    let Uses = [FLAGS] in  // ACI reads CY
    def ACI : V6ClangInstImm8Opc<0b001,
        (outs Acc:$dst), (ins Acc:$lhs, imm8:$imm),
        "ACI\t$imm", []>;
    def SUI : V6ClangInstImm8Opc<0b010,
        (outs Acc:$dst), (ins Acc:$lhs, imm8:$imm),
        "SUI\t$imm",
        [(set i8:$dst, FLAGS, (V6Clangsubf_imm i8:$lhs, (i8 imm:$imm)))]>;
    let Uses = [FLAGS] in  // SBI reads CY
    def SBI : V6ClangInstImm8Opc<0b011,
        (outs Acc:$dst), (ins Acc:$lhs, imm8:$imm),
        "SBI\t$imm", []>;
    def ANI : V6ClangInstImm8Opc<0b100,
        (outs Acc:$dst), (ins Acc:$lhs, imm8:$imm),
        "ANI\t$imm",
        [(set i8:$dst, FLAGS, (V6Clangandf_imm i8:$lhs, (i8 imm:$imm)))]>;
    def XRI : V6ClangInstImm8Opc<0b101,
        (outs Acc:$dst), (ins Acc:$lhs, imm8:$imm),
        "XRI\t$imm",
        [(set i8:$dst, FLAGS, (V6Clangxorf_imm i8:$lhs, (i8 imm:$imm)))]>;
    def ORI : V6ClangInstImm8Opc<0b110,
        (outs Acc:$dst), (ins Acc:$lhs, imm8:$imm),
        "ORI\t$imm",
        [(set i8:$dst, FLAGS, (V6Clangorf_imm i8:$lhs, (i8 imm:$imm)))]>;
  }
  // CPI: reads A, does NOT modify it — sets FLAGS only
  def CPI : V6ClangInstImm8Opc<0b111,
      (outs), (ins Acc:$lhs, imm8:$imm),
      "CPI\t$imm", [(set FLAGS, (V6Clangcmp i8:$lhs, (i8 imm:$imm)))]>;
}

//===----------------------------------------------------------------------===//
// ALU 16-bit — DAD, INX, DCX
//===----------------------------------------------------------------------===//

// DAD rp — 00_RP_1001 — Add rp to HL
let Defs = [HL, FLAGS], Uses = [HL] in
def DAD : V6ClangInstRegPair<0b00, 0b1001,
    (outs), (ins GR16AllPair:$rp),
    "DAD\t$rp", []>;

// INX rp — 00_RP_0011 — Increment register pair
let Constraints = "$rp = $src" in
def INX : V6ClangInstRegPair<0b00, 0b0011,
    (outs GR16AllPair:$rp), (ins GR16AllPair:$src),
    "INX\t$rp", []>;

// DCX rp — 00_RP_1011 — Decrement register pair
let Constraints = "$rp = $src" in
def DCX : V6ClangInstRegPair<0b00, 0b1011,
    (outs GR16AllPair:$rp), (ins GR16AllPair:$src),
    "DCX\t$rp", []>;

//===----------------------------------------------------------------------===//
// Increment / Decrement 8-bit — INR, DCR
//===----------------------------------------------------------------------===//

// INR r — 00_DDD_100 — Sets all flags except CY
let Defs = [FLAGS] in
def INRr : V6ClangInstRegDst<0b100,
    (outs GR8:$rd), (ins GR8:$src),
    "INR\t$rd", [(set i8:$rd, FLAGS, (V6Clangincf i8:$src))]> {
  let Constraints = "$rd = $src";
}

// DCR r — 00_DDD_101 — Sets all flags except CY
let Defs = [FLAGS] in
def DCRr : V6ClangInstRegDst<0b101,
    (outs GR8:$rd), (ins GR8:$src),
    "DCR\t$rd", [(set i8:$rd, FLAGS, (V6Clangdecf i8:$src))]> {
  let Constraints = "$rd = $src";
}

// INR M — 0x34 — Increment memory at (HL)
let Defs = [FLAGS], Uses = [HL], mayLoad = 1, mayStore = 1 in
def INRM : V6ClangInstImplied<0x34,
    (outs), (ins), "INR\tM", []>;

// DCR M — 0x35 — Decrement memory at (HL)
let Defs = [FLAGS], Uses = [HL], mayLoad = 1, mayStore = 1 in
def DCRM : V6ClangInstImplied<0x35,
    (outs), (ins), "DCR\tM", []>;

//===----------------------------------------------------------------------===//
// Rotate — RLC, RRC, RAL, RAR (accumulator only, 4cc)
//===----------------------------------------------------------------------===//

let Defs = [FLAGS] in {
  let Constraints = "$dst = $src" in {
    def RLC : V6ClangInstImplied<0x07, (outs Acc:$dst), (ins Acc:$src), "RLC", []>;
    def RRC : V6ClangInstImplied<0x0F, (outs Acc:$dst), (ins Acc:$src), "RRC", []>;
    let Uses = [FLAGS] in {  // RAL/RAR rotate through CY
      def RAL : V6ClangInstImplied<0x17, (outs Acc:$dst), (ins Acc:$src), "RAL", []>;
      def RAR : V6ClangInstImplied<0x1F, (outs Acc:$dst), (ins Acc:$src), "RAR", []>;
    }
  }
}

// O67: i8 rotate ISel — V6ClangISD::ROTL8/ROTR8 → RLC/RRC.
def : Pat<(V6Clangrotl8 Acc:$src), (RLC Acc:$src)>;
def : Pat<(V6Clangrotr8 Acc:$src), (RRC Acc:$src)>;

//===----------------------------------------------------------------------===//
// Branch — JMP, Jcc
//===----------------------------------------------------------------------===//

// JMP addr — 0xC3 [lo] [hi]
let isBranch = 1, isTerminator = 1, isBarrier = 1 in
def JMP : V6ClangInstImm16Opc<0xC3,
    (outs), (ins brtarget:$addr),
    "JMP\t$addr", []>;

// Conditional jumps — 11_CCC_010 [lo] [hi]
//   NZ=000, Z=001, NC=010, C=011, PO=100, PE=101, P=110, M=111
let isBranch = 1, isTerminator = 1, Uses = [FLAGS] in {
  def JNZ : V6ClangInstImm16Opc<0xC2, (outs), (ins brtarget:$addr), "JNZ\t$addr", []>;
  def JZ  : V6ClangInstImm16Opc<0xCA, (outs), (ins brtarget:$addr), "JZ\t$addr", []>;
  def JNC : V6ClangInstImm16Opc<0xD2, (outs), (ins brtarget:$addr), "JNC\t$addr", []>;
  def JC  : V6ClangInstImm16Opc<0xDA, (outs), (ins brtarget:$addr), "JC\t$addr", []>;
  def JPO : V6ClangInstImm16Opc<0xE2, (outs), (ins brtarget:$addr), "JPO\t$addr", []>;
  def JPE : V6ClangInstImm16Opc<0xEA, (outs), (ins brtarget:$addr), "JPE\t$addr", []>;
  def JP  : V6ClangInstImm16Opc<0xF2, (outs), (ins brtarget:$addr), "JP\t$addr", []>;
  def JM  : V6ClangInstImm16Opc<0xFA, (outs), (ins brtarget:$addr), "JM\t$addr", []>;
}

// PCHL — 0xE9 — Jump to address in HL
let isBranch = 1, isTerminator = 1, isBarrier = 1, isIndirectBranch = 1,
    Uses = [HL] in
def PCHL : V6ClangInstImplied<0xE9,
    (outs), (ins), "PCHL", []>;

//===----------------------------------------------------------------------===//
// Call — CALL, Ccc
//===----------------------------------------------------------------------===//

// CALL addr — 0xCD [lo] [hi]
// All registers clobbered (no callee-saved per design §6.1).
// The register mask on the MachineInstr (added by LowerCall) handles clobbers;
// Defs here just lists SP (for stack adjustment).
let isCall = 1, Uses = [SP], Defs = [SP] in
def CALL : V6ClangInstImm16Opc<0xCD,
    (outs), (ins brtarget:$addr),
    "CALL\t$addr", []>;

// Conditional calls — 11_CCC_100 [lo] [hi]
let isCall = 1, Uses = [SP, FLAGS], Defs = [SP] in {
  def CNZ : V6ClangInstImm16Opc<0xC4, (outs), (ins brtarget:$addr), "CNZ\t$addr", []>;
  def CZ  : V6ClangInstImm16Opc<0xCC, (outs), (ins brtarget:$addr), "CZ\t$addr", []>;
  def CNC : V6ClangInstImm16Opc<0xD4, (outs), (ins brtarget:$addr), "CNC\t$addr", []>;
  def CC  : V6ClangInstImm16Opc<0xDC, (outs), (ins brtarget:$addr), "CC\t$addr", []>;
  def CPO : V6ClangInstImm16Opc<0xE4, (outs), (ins brtarget:$addr), "CPO\t$addr", []>;
  def CPE : V6ClangInstImm16Opc<0xEC, (outs), (ins brtarget:$addr), "CPE\t$addr", []>;
  def CP  : V6ClangInstImm16Opc<0xF4, (outs), (ins brtarget:$addr), "CP\t$addr", []>;
  def CM  : V6ClangInstImm16Opc<0xFC, (outs), (ins brtarget:$addr), "CM\t$addr", []>;
}

//===----------------------------------------------------------------------===//
// Return — RET, Rcc
//===----------------------------------------------------------------------===//

// RET — 0xC9
let isReturn = 1, isTerminator = 1, isBarrier = 1,
    Uses = [SP], Defs = [SP], mayLoad = 1 in
def RET : V6ClangInstImplied<0xC9,
    (outs), (ins), "RET", [(V6Clangretflag)]>;

// Conditional returns — 11_CCC_000
let isReturn = 1, isTerminator = 1,
    Uses = [SP, FLAGS], Defs = [SP], mayLoad = 1 in {
  def RNZ : V6ClangInstImplied<0xC0, (outs), (ins), "RNZ", []>;
  def RZ  : V6ClangInstImplied<0xC8, (outs), (ins), "RZ", []>;
  def RNC : V6ClangInstImplied<0xD0, (outs), (ins), "RNC", []>;
  def RC  : V6ClangInstImplied<0xD8, (outs), (ins), "RC", []>;
  def RPO : V6ClangInstImplied<0xE0, (outs), (ins), "RPO", []>;
  def RPE : V6ClangInstImplied<0xE8, (outs), (ins), "RPE", []>;
  def RP  : V6ClangInstImplied<0xF0, (outs), (ins), "RP", []>;
  def RM  : V6ClangInstImplied<0xF8, (outs), (ins), "RM", []>;
}

// V6CLANG_TAILJMP — tail call via JMP encoding (0xC3).
// Used by peephole pass: CALL target; RET → V6CLANG_TAILJMP target.
// Marked isReturn (not isBranch) so analyzeBranch/BranchOpt skip it.
let isReturn = 1, isTerminator = 1, isBarrier = 1 in
def V6CLANG_TAILJMP : V6ClangInstImm16Opc<0xC3,
    (outs), (ins brtarget:$addr),
    "JMP\t$addr", []>;

//===----------------------------------------------------------------------===//
// RST — Restart (RST 0-7)
// Encoding: 11_NNN_111
//===----------------------------------------------------------------------===//

let isCall = 1, Uses = [SP], Defs = [SP] in {
  def RST0 : V6ClangInstRST<0, (outs), (ins), "RST\t0", []>;
  def RST1 : V6ClangInstRST<1, (outs), (ins), "RST\t1", []>;
  def RST2 : V6ClangInstRST<2, (outs), (ins), "RST\t2", []>;
  def RST3 : V6ClangInstRST<3, (outs), (ins), "RST\t3", []>;
  def RST4 : V6ClangInstRST<4, (outs), (ins), "RST\t4", []>;
  def RST5 : V6ClangInstRST<5, (outs), (ins), "RST\t5", []>;
  def RST6 : V6ClangInstRST<6, (outs), (ins), "RST\t6", []>;
  def RST7 : V6ClangInstRST<7, (outs), (ins), "RST\t7", []>;
}

//===----------------------------------------------------------------------===//
// Miscellaneous — NOP, HLT, CMA, STC, CMC, DAA, EI, DI
//===----------------------------------------------------------------------===//

def NOP : V6ClangInstImplied<0x00, (outs), (ins), "NOP", []>;

let hasSideEffects = 1 in
def HLT : V6ClangInstImplied<0x76, (outs), (ins), "HLT", []>;

// CMA — Complement A.
// NOTE: do NOT attach the `(not i8:$src)` pattern directly to this tied
// Acc-in/Acc-out instruction.  Because Acc is a subclass of GR8, matching a
// `not` whose value is also used elsewhere would *narrow* that value's vreg
// to the Acc class (register A only) for its entire live range instead of
// inserting a copy.  If another A-resident value (e.g. an LDA result feeding
// ANA/ORA) is live across the complement, both end up pinned to A at the same
// instruction and register allocation fails with "ran out of registers"
// (e.g. `v &= ~mask` where v is loaded once and live across both branches).
// Select `not` through COPY_TO_REGCLASS instead: the source and result live
// in GR8 and only a short-lived Acc temp crosses the CMA.  The coalescer
// removes the copies whenever the value is already in A.
let Constraints = "$dst = $src" in
def CMA : V6ClangInstImplied<0x2F, (outs Acc:$dst), (ins Acc:$src), "CMA", []>;

def : Pat<(not i8:$src),
          (COPY_TO_REGCLASS (CMA (COPY_TO_REGCLASS GR8:$src, Acc)), GR8)>;

// STC — Set carry flag
let Defs = [FLAGS] in
def STC : V6ClangInstImplied<0x37, (outs), (ins), "STC", []>;

// CMC — Complement carry flag
let Defs = [FLAGS], Uses = [FLAGS] in
def CMC : V6ClangInstImplied<0x3F, (outs), (ins), "CMC", []>;

// DAA — Decimal adjust accumulator
let Defs = [FLAGS], Uses = [FLAGS] in
def DAA : V6ClangInstImplied<0x27, (outs Acc:$dst), (ins Acc:$src), "DAA", []> {
  let Constraints = "$dst = $src";
}

// EI — Enable interrupts
let hasSideEffects = 1 in
def EI : V6ClangInstImplied<0xFB, (outs), (ins), "EI", []>;

// DI — Disable interrupts
let hasSideEffects = 1 in
def DI : V6ClangInstImplied<0xF3, (outs), (ins), "DI", []>;

//===----------------------------------------------------------------------===//
// I/O — IN, OUT
//===----------------------------------------------------------------------===//

// IN port — 0xDB [port]
let hasSideEffects = 1 in
def IN : V6ClangInstIO<0xDB,
    (outs Acc:$dst), (ins i8port:$port),
    "IN\t$port", []>;

// OUT port — 0xD3 [port]
let hasSideEffects = 1 in
def OUT : V6ClangInstIO<0xD3,
    (outs), (ins Acc:$src, i8port:$port),
    "OUT\t$port", []>;

//===----------------------------------------------------------------------===//
// Pseudo-instructions for M4 ISel
//===----------------------------------------------------------------------===//

// V6CLANG_BRCOND — Conditional branch. Expanded to Jcc in post-ISel.
// Operand 0: branch target, Operand 1: V6CLANG condition code (i8),
// Operand 2: FLAGS (i8 SSA, bound to physical FLAGS register).
let isBranch = 1, isTerminator = 1, Uses = [FLAGS] in
def V6CLANG_BRCOND : V6ClangPseudo<(outs),
    (ins brtarget:$dst, i8imm:$cc),
    "# V6CLANG_BRCOND $dst, $cc",
    [(V6Clangbrcond bb:$dst, (i8 imm:$cc), FLAGS)]>;

// V6CLANG_SELECT_CC — Conditional select. Expanded to compare+branch sequence.
// Uses FLAGS (set by a preceding V6ClangISD::CMP).
let usesCustomInserter = 1, Uses = [FLAGS] in
def V6CLANG_SELECT_CC : V6ClangPseudo<(outs GR8:$dst),
    (ins GR8:$trueval, GR8:$falseval, i8imm:$cc),
    "# V6CLANG_SELECT_CC $dst, $trueval, $falseval, $cc",
    [(set i8:$dst, (V6Clangselectcc i8:$trueval, i8:$falseval,
                                (i8 imm:$cc), FLAGS))]>;

// V6CLANG_LOAD8_P — Load i8 from i16 pointer (in register pair).
// Expansion preserves HL in all paths (LDAX, PUSH/POP, or direct MOV r,M).
let mayLoad = 1 in
def V6CLANG_LOAD8_P : V6ClangPseudo<(outs GR8:$dst), (ins GR16:$addr),
    "# LOAD8P $dst, ($addr)",
    [(set i8:$dst, (load i16:$addr))]>;

// V6CLANG_STORE8_P — Store i8 to i16 pointer (in register pair).
// Expansion preserves HL in all paths (STAX, PUSH/POP, or direct MOV M,r).
let mayStore = 1 in
def V6CLANG_STORE8_P : V6ClangPseudo<(outs), (ins GR8:$src, GR16:$addr),
    "# STORE8P $src, ($addr)",
    [(store i8:$src, i16:$addr)]>;

//===----------------------------------------------------------------------===//
// O49 — Direct Memory ALU/Store pseudos (M-operand instructions).
// Expansion in V6ClangInstrInfo::expandPostRAPseudo via expandMemOpM() helper.
// addr == HL : direct XXX M
// addr == DE : XCHG; XXX M; XCHG
// addr == BC : [PUSH HL;] MOV L,C; MOV H,B; XXX M; [POP HL]
//              (PUSH/POP skipped when HL dead — O42 liveness-aware).
//===----------------------------------------------------------------------===//

// ALU M read-variants: A = A op [addr].
let mayLoad = 1, Defs = [FLAGS] in {
  let Constraints = "$dst = $lhs" in {
    def V6CLANG_ADD_M_P : V6ClangPseudo<(outs Acc:$dst), (ins Acc:$lhs, GR16:$addr),
        "# ADD_M_P $dst, ($addr)",
        [(set Acc:$dst, FLAGS,
              (V6Clangaddf Acc:$lhs, (i8 (load i16:$addr))))]>;
    def V6CLANG_ADC_M_P : V6ClangPseudo<(outs Acc:$dst), (ins Acc:$lhs, GR16:$addr),
        "# ADC_M_P $dst, ($addr)", []>;
    def V6CLANG_SUB_M_P : V6ClangPseudo<(outs Acc:$dst), (ins Acc:$lhs, GR16:$addr),
        "# SUB_M_P $dst, ($addr)",
        [(set Acc:$dst, FLAGS,
              (V6Clangsubf Acc:$lhs, (i8 (load i16:$addr))))]>;
    def V6CLANG_SBB_M_P : V6ClangPseudo<(outs Acc:$dst), (ins Acc:$lhs, GR16:$addr),
        "# SBB_M_P $dst, ($addr)", []>;
    def V6CLANG_ANA_M_P : V6ClangPseudo<(outs Acc:$dst), (ins Acc:$lhs, GR16:$addr),
        "# ANA_M_P $dst, ($addr)",
        [(set Acc:$dst, FLAGS,
              (V6Clangandf Acc:$lhs, (i8 (load i16:$addr))))]>;
    def V6CLANG_ORA_M_P : V6ClangPseudo<(outs Acc:$dst), (ins Acc:$lhs, GR16:$addr),
        "# ORA_M_P $dst, ($addr)",
        [(set Acc:$dst, FLAGS,
              (V6Clangorf Acc:$lhs, (i8 (load i16:$addr))))]>;
    def V6CLANG_XRA_M_P : V6ClangPseudo<(outs Acc:$dst), (ins Acc:$lhs, GR16:$addr),
        "# XRA_M_P $dst, ($addr)",
        [(set Acc:$dst, FLAGS,
              (V6Clangxorf Acc:$lhs, (i8 (load i16:$addr))))]>;
  }
  // CMP M: reads A, writes FLAGS only.
  def V6CLANG_CMP_M_P : V6ClangPseudo<(outs), (ins Acc:$lhs, GR16:$addr),
      "# CMP_M_P $lhs, ($addr)",
      [(set FLAGS, (V6Clangcmp Acc:$lhs, (i8 (load i16:$addr))))]>;
}

// MVI M, imm8 via register pointer: store an 8-bit immediate.
let mayStore = 1 in
def V6CLANG_STORE8_IMM_P : V6ClangPseudo<(outs), (ins imm8:$imm, GR16:$addr),
    "# STORE8_IMM_P $imm, ($addr)",
    [(store (i8 imm:$imm), i16:$addr)]>;

// INR M / DCR M: read-modify-write byte through a register pointer.
let mayLoad = 1, mayStore = 1, Defs = [FLAGS] in {
  def V6CLANG_INR_M_P : V6ClangPseudo<(outs), (ins GR16:$addr),
      "# INR_M_P ($addr)",
      [(store (V6Clangincf (i8 (load i16:$addr))), i16:$addr)]>;
  def V6CLANG_DCR_M_P : V6ClangPseudo<(outs), (ins GR16:$addr),
      "# DCR_M_P ($addr)",
      [(store (V6Clangdecf (i8 (load i16:$addr))), i16:$addr)]>;
}

// Spill/reload pseudos for register allocation.
// Expanded in eliminateFrameIndex with PUSH/POP preservation.
// Non-H/L: PUSH HL; LXI HL,off+2; DAD SP; MOV M,r / MOV r,M; POP HL
// H/L:     PUSH DE; save other half in D; LXI+DAD; MOV H/L,M; restore; POP DE
// Only FLAGS is clobbered (by DAD SP). All other regs preserved via PUSH/POP.
let mayStore = 1, Defs = [FLAGS] in
def V6CLANG_SPILL8 : V6ClangPseudo<(outs), (ins GR8:$src, i16imm:$fi),
    "# SPILL8 $src, $fi", []>;

let mayLoad = 1, Defs = [FLAGS] in
def V6CLANG_RELOAD8 : V6ClangPseudo<(outs GR8:$dst), (ins i16imm:$fi),
    "# RELOAD8 $dst, $fi", []>;

// 16-bit spill/reload pseudos for register pair allocation.
// Expanded in eliminateFrameIndex with PUSH/POP preservation so that
// registers OTHER than the src/dst are not clobbered.
// Only FLAGS is clobbered (by DAD SP inside the expansion).
let mayStore = 1, Defs = [FLAGS] in
def V6CLANG_SPILL16 : V6ClangPseudo<(outs), (ins GR16:$src, i16imm:$fi),
    "# SPILL16 $src, $fi", []>;

let mayLoad = 1, Defs = [FLAGS] in
def V6CLANG_RELOAD16 : V6ClangPseudo<(outs GR16:$dst), (ins i16imm:$fi),
    "# RELOAD16 $dst, $fi", []>;

//===----------------------------------------------------------------------===//
// Pseudo-instructions (design §5.5)
// These expand to real instructions during or after ISel.
//===----------------------------------------------------------------------===//

// V6CLANG_PSEUDO_COMMENT — Asm annotation marker for pseudo expansion debugging.
// Carries the opcode number of the source pseudo. AsmPrinter converts
// this to an assembly comment like "; --- V6CLANG_RELOAD8 ---".
// Enabled via -mv6clang-annotate-pseudos. No code is generated.
def V6CLANG_PSEUDO_COMMENT : V6ClangPseudo<(outs), (ins i16imm:$opcode),
    "# PSEUDO_COMMENT $opcode", []>;

// Adjcallstackdown / adjcallstackup — frame setup/teardown markers
let Defs = [SP], Uses = [SP], hasSideEffects = 1 in {
  def ADJCALLSTACKDOWN : V6ClangPseudo<(outs), (ins i16imm:$amt, i16imm:$amt2),
                                   "# ADJCALLSTACKDOWN $amt $amt2", []>;
  def ADJCALLSTACKUP   : V6ClangPseudo<(outs), (ins i16imm:$amt, i16imm:$amt2),
                                   "# ADJCALLSTACKUP $amt $amt2", []>;
}

// V6CLANG_LEA_FI — Compute address of a frame index (stack slot).
// Expands in eliminateFrameIndex to:
//   dst = HL: LXI HL, offset; DAD SP
//   dst = DE: LXI HL, offset; DAD SP; XCHG          (HL clobbered w/ old DE)
//   dst = BC: LXI HL, offset; DAD SP; MOV B,H; MOV C,L   (HL clobbered)
// HL is always clobbered because DAD SP writes HL; listed in Defs so the
// register allocator does not keep a live value in HL across this pseudo.
let Defs = [FLAGS, HL] in
def V6CLANG_LEA_FI : V6ClangPseudo<(outs GR16:$dst), (ins i16imm:$fi),
    "# LEA $dst, $fi", []>;

//===----------------------------------------------------------------------===//
// Additional patterns — selected via Pat<> (no encoding change needed)
//===----------------------------------------------------------------------===//

// GlobalAddress lowering: (V6ClangWrapper GA) patterns
def : Pat<(V6Clangwrapper tglobaladdr:$addr), (LXI tglobaladdr:$addr)>;
def : Pat<(V6Clangwrapper texternalsym:$addr), (LXI texternalsym:$addr)>;

// Load i8 from global address via LDA (result always in A)
def : Pat<(i8 (load (V6Clangwrapper tglobaladdr:$addr))),
          (LDA tglobaladdr:$addr)>;

// Store i8 to global address via STA (source must be in A)
def : Pat<(store i8:$val, (V6Clangwrapper tglobaladdr:$addr)),
          (STA i8:$val, tglobaladdr:$addr)>;

// Load i8 from constant integer address via LDA (e.g. memory-mapped I/O)
def : Pat<(i8 (load imm:$addr)), (LDA imm:$addr)>;

// Store i8 to constant integer address via STA
def : Pat<(store i8:$val, imm:$addr), (STA i8:$val, imm:$addr)>;

// Unconditional branch → JMP
def : Pat<(br bb:$dst), (JMP bb:$dst)>;

// i16 constant materialization → LXI
def : Pat<(i16 imm:$val), (LXI imm:$val)>;

//===----------------------------------------------------------------------===//
// M7: i16 Pseudo-instructions
//===----------------------------------------------------------------------===//

// 16-bit arithmetic pseudos. These expand post-RA into 8-bit sequences via A.
// All clobber A (used as temp) and FLAGS.

// V6CLANG_DAD: 16-bit add lowered through physical DAD rp.
// Keep both inputs unconstrained before RA; the post-RA expander chooses an
// operand already in HL when possible, otherwise copies one operand to HL.
// The virtual result may live in any pair; the expander copies out of HL when
// RA picked DE/BC, which avoids multiple HL-only pointer live ranges.
// Does NOT clobber A — only FLAGS — giving better register pressure than
// the general V6CLANG_ADD16 which uses an 8-bit chain through A.
// Selected via V6ClangISD::DAD from PerformDAGCombine when the add result
// is used as a memory address (load/store pointer).
let Defs = [FLAGS] in
def V6CLANG_DAD : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$lhs, GR16All:$rp),
    "# DAD $dst, $lhs, $rp",
    [(set i16:$dst, (V6Clangdad i16:$lhs, i16:$rp))]> {
  let isCommutable = 1;
}

// V6CLANG_INX16: rp += count (1..3) via N copies of INX rp.
// No register pair needed for the constant — count is an immediate.
// Does NOT clobber A or FLAGS (INX sets no flags).
def V6CLANG_INX16 : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src, i8imm:$count),
    "# INX16 $dst, $src, $count",
    [(set i16:$dst, (V6Clanginx16 i16:$src, (i8 timm:$count)))]> {
  let Constraints = "$dst = $src";
}

// V6CLANG_DCX16: rp -= count (1..3) via N copies of DCX rp.
def V6CLANG_DCX16 : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src, i8imm:$count),
    "# DCX16 $dst, $src, $count",
    [(set i16:$dst, (V6Clangdcx16 i16:$src, (i8 timm:$count)))]> {
  let Constraints = "$dst = $src";
}

let Defs = [A, FLAGS] in {
  def V6CLANG_ADD16 : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$lhs, GR16:$rhs),
      "# ADD16 $dst, $lhs, $rhs",
      [(set i16:$dst, (add i16:$lhs, i16:$rhs))]>;
  let AddedComplexity = 10 in
  def V6CLANG_NEG16 : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src),
    "# NEG16 $dst, $src",
    [(set i16:$dst, (sub (i16 0), i16:$src))]>;
  def V6CLANG_SUB16 : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$lhs, GR16:$rhs),
      "# SUB16 $dst, $lhs, $rhs",
      [(set i16:$dst, (sub i16:$lhs, i16:$rhs))]>;
  def V6CLANG_AND16 : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$lhs, GR16:$rhs),
      "# AND16 $dst, $lhs, $rhs",
      [(set i16:$dst, (and i16:$lhs, i16:$rhs))]>;
  def V6CLANG_OR16 : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$lhs, GR16:$rhs),
      "# OR16 $dst, $lhs, $rhs",
      [(set i16:$dst, (or i16:$lhs, i16:$rhs))]>;
  def V6CLANG_XOR16 : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$lhs, GR16:$rhs),
      "# XOR16 $dst, $lhs, $rhs",
      [(set i16:$dst, (xor i16:$lhs, i16:$rhs))]>;

  // O93: Bitwise-16 against a compile-time constant. The immediate is loaded
  // into A byte-wise and the cheaper 4cc register ALU form is applied to the
  // source register (legal because AND/OR/XOR are commutative). No scratch
  // register pair is needed — avoids the LXI + reg-pair cost of the reg/reg
  // form. Higher AddedComplexity so a constant RHS prefers these over the
  // generic reg/reg patterns above. Expanded in expandPostRAPseudo with
  // per-byte 0x00/0xFF identity folding.
  let Constraints = "$dst = $src", AddedComplexity = 20 in {
    def V6CLANG_AND16_IMM : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src, i16imm:$imm),
        "# AND16_IMM $dst, $src, $imm",
        [(set i16:$dst, (and i16:$src, imm:$imm))]>;
    def V6CLANG_OR16_IMM : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src, i16imm:$imm),
        "# OR16_IMM $dst, $src, $imm",
        [(set i16:$dst, (or i16:$src, imm:$imm))]>;
    def V6CLANG_XOR16_IMM : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src, i16imm:$imm),
        "# XOR16_IMM $dst, $src, $imm",
        [(set i16:$dst, (xor i16:$src, imm:$imm))]>;
  }
}

let Defs = [A, FLAGS], AddedComplexity = 10 in
def V6CLANG_NEG8 : V6ClangPseudo<(outs GR8:$dst), (ins GR8:$src),
    "# NEG8 $dst, $src",
    [(set i8:$dst, (V6Clangneg8 i8:$src))]>;

// 16-bit shift pseudos (constant shift amount only).
// Variable shifts are library calls.
let Defs = [FLAGS] in
def V6CLANG_SHL16_DAD : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src, i8imm:$amt),
  "# SHL16_DAD $dst, $src, $amt",
  [(set i16:$dst, (V6Clangshl16_dad i16:$src, (i8 timm:$amt)))]>;

def V6CLANG_SHL16_BYTE : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src, i8imm:$amt),
  "# SHL16_BYTE $dst, $src, $amt",
  [(set i16:$dst, (V6Clangshl16_byte i16:$src, (i8 timm:$amt)))]>;

let Defs = [A, FLAGS] in {
  def V6CLANG_SHL16_RAM_HI : V6ClangPseudo<(outs GR16:$dst),
    (ins GR16:$src, i8imm:$amt),
    "# SHL16_RAM_HI $dst, $src, $amt",
    [(set i16:$dst, (V6Clangshl16_ram_hi i16:$src, (i8 timm:$amt)))]>;
  def V6CLANG_SRL16_RAR : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src, i8imm:$amt),
    "# SRL16_RAR $dst, $src, $amt",
    [(set i16:$dst, (V6Clangsrl16_rar i16:$src, (i8 timm:$amt)))]>;
  def V6CLANG_SRL16_24BIT : V6ClangPseudo<(outs GR16:$dst),
    (ins GR16:$src, i8imm:$amt),
    "# SRL16_24BIT $dst, $src, $amt",
    [(set i16:$dst, (V6Clangsrl16_24bit i16:$src, (i8 timm:$amt)))]>;
  def V6CLANG_SRL16_RAM_LO : V6ClangPseudo<(outs GR16:$dst),
    (ins GR16:$src, i8imm:$amt),
    "# SRL16_RAM_LO $dst, $src, $amt",
    [(set i16:$dst, (V6Clangsrl16_ram_lo i16:$src, (i8 timm:$amt)))]>;
  def V6CLANG_SRA16_RAR : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src, i8imm:$amt),
    "# SRA16_RAR $dst, $src, $amt",
    [(set i16:$dst, (V6Clangsra16_rar i16:$src, (i8 timm:$amt)))]>;
  def V6CLANG_SRA16_24BIT : V6ClangPseudo<(outs GR16:$dst),
    (ins GR16:$src, i8imm:$amt),
    "# SRA16_24BIT $dst, $src, $amt",
    [(set i16:$dst, (V6Clangsra16_24bit i16:$src, (i8 timm:$amt)))]>;
  def V6CLANG_SRA16_BYTE : V6ClangPseudo<(outs GR16:$dst),
    (ins GR16:$src, i8imm:$amt),
    "# SRA16_BYTE $dst, $src, $amt",
    [(set i16:$dst, (V6Clangsra16_byte i16:$src, (i8 timm:$amt)))]>;
  def V6CLANG_SRA16_RAM_LO : V6ClangPseudo<(outs GR16:$dst),
    (ins GR16:$src, i8imm:$amt),
    "# SRA16_RAM_LO $dst, $src, $amt",
    [(set i16:$dst, (V6Clangsra16_ram_lo i16:$src, (i8 timm:$amt)))]>;
}

def V6CLANG_SRL16_BYTE : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src, i8imm:$amt),
  "# SRL16_BYTE $dst, $src, $amt",
  [(set i16:$dst, (V6Clangsrl16_byte i16:$src, (i8 timm:$amt)))]>;

// O68 Phase 2: 16-bit rotate-left by 1.
// HL-constrained via GR16Ptr: post-RA expansion is the literal
// DAD H; MOV A,L; ACI 0; MOV L,A sequence (4 instr / 5 B / 36 cc).
// CY chains internally inside the post-RA expansion; the pseudo
// declares only the externally-observable Defs (A, FLAGS).
let Defs = [A, FLAGS], Constraints = "$dst = $src" in
def V6CLANG_ROTL16_1 : V6ClangPseudo<(outs GR16Ptr:$dst), (ins GR16Ptr:$src),
    "# ROTL16_1 $dst, $src",
    [(set i16:$dst, (V6Clangrotl16_1 i16:$src))]>;

// 16-bit load from pointer (register pair).
// No Defs=[HL]: when addr=DE expansion uses XCHG (preserving HL),
// when addr=BC it preserves HL via PUSH/POP.  This lets the RA freely
// assign DE to the pointer (enabling cheap XCHG) or HL to the result.
let mayLoad = 1 in
def V6CLANG_LOAD16_P : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$addr),
    "# LOAD16P $dst, ($addr)",
    [(set i16:$dst, (load i16:$addr))]>;

// Direct stack/frame-index loads and stores. These are ordinary value memory
// operations, not spill/reload pseudos: they clobber HL while forming the
// address and rely on RA to protect any live value that must survive.
let mayLoad = 1, Defs = [HL, FLAGS] in {
def V6CLANG_LOAD8_FI : V6ClangPseudo<(outs GR8:$dst), (ins i16imm:$fi),
    "# LOAD8FI $dst, $fi", []>;
def V6CLANG_LOAD16_FI : V6ClangPseudo<(outs GR16:$dst), (ins i16imm:$fi),
    "# LOAD16FI $dst, $fi", []>;
}

let mayStore = 1, Defs = [HL, FLAGS] in {
def V6CLANG_STORE8_FI : V6ClangPseudo<(outs), (ins GR8NoHL:$val, i16imm:$fi),
    "# STORE8FI $val, $fi", []>;
def V6CLANG_STORE16_FI : V6ClangPseudo<(outs), (ins GR16Idx:$val, i16imm:$fi),
    "# STORE16FI $val, $fi", []>;
}

// 16-bit store to pointer (register pair).
// O72 — No Defs. The post-RA expander emits truthful per-shape
// preservation (dead-GR8 spare, DCX rp recovery, XCHG for addr=DE,
// PUSH PSW / PUSH H only as last-resort fallbacks). See
// V6ClangInstrInfo::expandPostRAPseudo() and
// design/future_plans/O72_V6CLANG_STORE16_P_redesign.md.
let mayStore = 1 in
def V6CLANG_STORE16_P : V6ClangPseudo<(outs), (ins GR16:$val, GR16:$addr),
    "# STORE16P $val, ($addr)",
    [(store i16:$val, i16:$addr)]>;

// 16-bit load from global address.
// No Defs=[HL] — when $dst != HL the expansion preserves HL via PUSH/POP,
// so the register allocator is free to assign the result to HL (LHLD,
// optimal) or DE/BC (LHLD + copy + HL preservation) under register pressure.
let mayLoad = 1 in
def V6CLANG_LOAD16_G : V6ClangPseudo<(outs GR16:$dst), (ins imm16:$addr),
    "# LOAD16G $dst, $addr", []>;

// 16-bit store to global address.
// No Defs=[HL] — the post-RA expander dispatches per val class
// (HL/DE/BC) and observable HL/A liveness, preserving HL when needed
// via XCHG round-trip, STA-pair (when A is dead), or PUSH/POP. See
// V6ClangInstrInfo::expandPostRAPseudo() and
// design/future_plans/O74_V6CLANG_STORE16_G_redesign.md.
let mayStore = 1 in
def V6CLANG_STORE16_G : V6ClangPseudo<(outs), (ins GR16:$val, imm16:$addr),
    "# STORE16G $val, $addr", []>;

// Load i16 from global address.
// Use V6CLANG_LOAD16_G (GR16 output) instead of LHLD (GR16Ptr = HL-only) so
// the register allocator can pick DE or BC when multiple global loads are
// live simultaneously.  Post-RA expansion emits LHLD when dst happens to
// be HL, or LXI+MOV when dst is DE/BC.
def : Pat<(i16 (load (V6Clangwrapper tglobaladdr:$addr))),
          (V6CLANG_LOAD16_G tglobaladdr:$addr)>;

// Store i16 to global. Routed through V6CLANG_STORE16_G (GR16 input) so the
// register allocator can keep the value in HL/DE/BC; the post-RA
// expander emits SHLD when val is HL, an XCHG-wrapped SHLD when val is
// DE, and one of three BC shapes (HL-dead / A-dead STA-pair /
// PUSH-POP fallback).
def : Pat<(store i16:$val, (V6Clangwrapper tglobaladdr:$addr)),
          (V6CLANG_STORE16_G i16:$val, tglobaladdr:$addr)>;

// BUILD_PAIR: combine two i8 values into i16 register pair.
// Post-RA: expands to pair of MOV instructions.
// Selected via C++ code in V6ClangISelDAGToDAG for BUILD_PAIR nodes.
let isPseudo = 1 in
def V6CLANG_BUILD_PAIR : V6ClangPseudo<(outs GR16:$dst), (ins GR8:$lo, GR8:$hi),
    "# BUILD_PAIR $dst, $lo, $hi", []>;

// SEXT: sign-extend i8 to i16 via RLC+SBB (hi = 0x00 or 0xFF).
let isPseudo = 1, Defs = [A, FLAGS] in
def V6CLANG_SEXT : V6ClangPseudo<(outs GR16:$dst), (ins GR8:$src),
    "# SEXT $dst, $src",
    [(set i16:$dst, (V6Clangsext i8:$src))]>;

// EXTRACT_SUBREG patterns for truncate i16 → i8.
def : Pat<(i8 (trunc i16:$src)),
          (EXTRACT_SUBREG i16:$src, sub_lo)>;

// 16-bit conditional select. Expanded to diamond CFG.
let usesCustomInserter = 1, Uses = [FLAGS] in
def V6CLANG_SELECT_CC16 : V6ClangPseudo<(outs GR16:$dst),
    (ins GR16:$trueval, GR16:$falseval, i8imm:$cc),
    "# V6CLANG_SELECT_CC16 $dst, $trueval, $falseval, $cc",
    [(set i16:$dst, (V6Clangselectcc i16:$trueval, i16:$falseval,
                                 (i8 imm:$cc), FLAGS))]>;

// Fused 16-bit compare + conditional branch.
// Expanded post-RA into 8-bit compare sequence + Jcc.
// EQ/NE uses non-destructive CMP-based expansion with MBB splitting.
// Other conditions use SUB/SBB. Neither path clobbers LHS or RHS.
let isBranch = 1, isTerminator = 1, Defs = [A, FLAGS] in
def V6CLANG_BR_CC16 : V6ClangPseudo<(outs),
    (ins GR16:$lhs, GR16:$rhs, i8imm:$cc, brtarget:$dst),
    "# BR_CC16 $lhs, $rhs, $cc, $dst",
    []>;

// Fused 16-bit compare + conditional branch with immediate RHS.
// Selected when the comparison RHS is a known constant or global address.
// Expanded post-RA into MVI + CMP sequence with lo8/hi8 splitting.
// The immediate is embedded directly — no register pair needed for RHS.
let isBranch = 1, isTerminator = 1, Defs = [A, FLAGS] in
def V6CLANG_BR_CC16_IMM : V6ClangPseudo<(outs),
    (ins GR16:$lhs, imm16:$rhs, i8imm:$cc, brtarget:$dst),
    "# BR_CC16_IMM $lhs, $rhs, $cc, $dst",
    []>;

// O34: 16-bit zero-test comparison (for SELECT_CC against zero).
// Produces FLAGS via MOV A, Hi; ORA Lo — Z=1 iff pair==0.
// Note: FLAGS must precede A in Defs so the [(set FLAGS, ...)] pattern
// binder picks FLAGS (first physreg of matching type i8).
let Defs = [FLAGS, A] in
def V6CLANG_CMP16_ZERO : V6ClangPseudo<(outs), (ins GR16:$src),
    "# CMP16_ZERO $src",
    [(set FLAGS, (V6Clangcmpzero i16:$src))]>;

// Signed compare against zero using only the high byte's sign bit.
// Expansion: XRA A; ADD hi(src). This is only valid for M/P consumers.
let Defs = [FLAGS, A] in
def V6CLANG_CMP16_SIGN : V6ClangPseudo<(outs), (ins GR16:$src),
    "# CMP16_SIGN $src",
    [(set FLAGS, (V6Clangcmpsign i16:$src))]>;

// O80: 8-bit zero-test comparison. Mirrors V6CLANG_CMP16_ZERO for i8.
// Avoids the Acc:$lhs constraint of CPI 0, which forces a MOV A,r
// preamble (and full save/restore when A is live across the test).
// Expanded post-RA in V6ClangInstrInfo::expandPostRAPseudo into one of:
//   src=A          → ORA A                     (1B / 4cc)
//   src≠A, A dead  → XRA A; CMP src            (2B / 8cc, O38 path)
//   src≠A, A live  → INR src; DCR src          (2B / 16cc, A-preserving)
// Defs = [FLAGS] only — the INR/DCR path preserves A. Shape 1/2 do
// touch A, but post-RA expansion adds the def via BuildMI directly.
// Pattern (V6Clangcmp i8, 0) is more specific than CPI's
// (V6Clangcmp i8, imm:$imm), so ISel prefers this pseudo for the
// zero-compare case. AddedComplexity = 10 ensures the disambiguation
// is robust against future pattern reorderings.
let Defs = [FLAGS], AddedComplexity = 10 in
def V6CLANG_CMP8_ZERO : V6ClangPseudo<(outs), (ins GR8:$src),
    "# CMP8_ZERO $src",
    [(set FLAGS, (V6Clangcmp i8:$src, (i8 0)))]>;

// 16-bit comparison (for use in i16 BR_CC lowering).
// Produces FLAGS via subtraction (SUB lo, SBB hi).
// FLAGS first in Defs (see CMP16_ZERO note).
let Defs = [FLAGS, A] in
def V6CLANG_CMP16 : V6ClangPseudo<(outs), (ins GR16:$lhs, GR16:$rhs),
    "# CMP16 $lhs, $rhs",
    [(set FLAGS, (V6Clangcmp i16:$lhs, i16:$rhs))]>;

// O24: 16-bit comparison with immediate RHS (for SELECT_CC ordering).
// Produces FLAGS via MVI+SUB, MVI+SBB — no register pair needed.
// Selected manually in ISel (K→K-1 + CC inversion done in LowerSELECT_CC).
let Defs = [FLAGS, A] in
def V6CLANG_CMP16_IMM : V6ClangPseudo<(outs), (ins GR16:$lhs, imm16:$rhs),
    "# CMP16_IMM $lhs, $rhs",
    []>;

//===----------------------------------------------------------------------===//
// Intrinsic patterns — map LLVM intrinsics to machine instructions
//===----------------------------------------------------------------------===//

// __builtin_v6clang_in(port) → IN port (result in A)
def : Pat<(int_v6clang_in (i8 imm:$port)), (IN imm:$port)>;

// __builtin_v6clang_out(port, val) → OUT port (val must be in A)
def : Pat<(int_v6clang_out (i8 imm:$port), Acc:$val), (OUT Acc:$val, imm:$port)>;

// __builtin_v6clang_di() → DI
def : Pat<(int_v6clang_di), (DI)>;

// __builtin_v6clang_ei() → EI
def : Pat<(int_v6clang_ei), (EI)>;

// __builtin_v6clang_hlt() → HLT
def : Pat<(int_v6clang_hlt), (HLT)>;

// __builtin_v6clang_nop() → NOP
def : Pat<(int_v6clang_nop), (NOP)>;
