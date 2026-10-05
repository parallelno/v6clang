//===-- V6ClangSchedule.td - V6CLANG Scheduling Definitions --------*- tablegen -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
// Scheduling model for the Intel 8080 / KR580VM80A on Vector 06c.
// See design.md §4.4 for timing details.
//
// The 8080 is strictly in-order, single-issue. We define SchedWrite
// resources to model instruction latencies from the Vector 06c timing
// table (costs in clock cycles / "ticks").
//
//===----------------------------------------------------------------------===//

def V6ClangModel : SchedMachineModel {
  let MicroOpBufferSize = 0;    // Strictly in-order
  let IssueWidth = 1;           // One instruction at a time
  let LoadLatency = 2;          // Memory access latency in cost units
  let CompleteModel = 0;        // Allow instructions without sched info
}

//===----------------------------------------------------------------------===//
// Scheduling write resources — cycle costs
//===----------------------------------------------------------------------===//

def WriteALU4   : SchedWrite;   // 4cc:  ALU reg-reg, MOV r,r, rotate, misc
def WriteALU8   : SchedWrite;   // 8cc:  ALU mem/imm, INR/DCR reg, SPHL, PCHL, HLT
def WriteMOV8   : SchedWrite;   // 8cc:  MOV r,M; MOV M,r; MVI r,d8; LDAX; STAX
def WriteINX8   : SchedWrite;   // 8cc:  INX, DCX
def WriteDAD12  : SchedWrite;   // 12cc: DAD, INR M, DCR M, POP, IN, OUT
def WriteMOV16  : SchedWrite;   // 12cc: MVI M,d8
def WriteLXI12  : SchedWrite;   // 12cc: LXI
def WritePUSH16 : SchedWrite;   // 16cc: PUSH, LDA, STA, RST
def WriteBR12   : SchedWrite;   // 12cc: JMP, conditional branch
def WriteRET12  : SchedWrite;   // 12cc: RET (unconditional)
def WriteCondRET : SchedWrite;  // 8/16cc: Rcc (false/true)
def WriteLHLD20 : SchedWrite;   // 20cc: LHLD, SHLD
def WriteCALL24 : SchedWrite;   // 24cc: CALL, XTHL

let SchedModel = V6ClangModel in {
  def : WriteRes<WriteALU4,   []> { let Latency = 1; }
  def : WriteRes<WriteALU8,   []> { let Latency = 2; }
  def : WriteRes<WriteMOV8,   []> { let Latency = 2; }
  def : WriteRes<WriteINX8,   []> { let Latency = 2; }
  def : WriteRes<WriteDAD12,  []> { let Latency = 3; }
  def : WriteRes<WriteMOV16,  []> { let Latency = 3; }
  def : WriteRes<WriteLXI12,  []> { let Latency = 3; }
  def : WriteRes<WritePUSH16, []> { let Latency = 4; }
  def : WriteRes<WriteBR12,   []> { let Latency = 3; }
  def : WriteRes<WriteRET12,  []> { let Latency = 3; }
  def : WriteRes<WriteCondRET,[]> { let Latency = 4; }
  def : WriteRes<WriteLHLD20, []> { let Latency = 5; }
  def : WriteRes<WriteCALL24, []> { let Latency = 6; }
}
