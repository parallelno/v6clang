//===-- V6ClangSPTrickOpt.cpp - SP-Trick Block Copy Optimization --------------===//
//
// Part of the V6CLANG backend for LLVM.
//
// Post-RA pass: Replace expanded memcpy/memset sequences with the SP-trick
// for copies >= 6 bytes.
//
// The 8080 SP trick exploits POP for fast sequential reads:
//   DI                    ; Disable interrupts (SP is repurposed)
//   LXI H, 0; DAD SP     ; Save old SP in HL
//   XCHG                  ; DE = old SP
//   LXI SP, src           ; Point SP at source data
//   POP H                 ; HL = [src], src += 2  (12cc per 2 bytes)
//   SHLD dst              ; [dst] = HL            (20cc per 2 bytes)
//   ... repeat with dst+2, dst+4, ...
//   XCHG                  ; HL = old SP
//   SPHL                  ; Restore SP
//   EI                    ; Re-enable interrupts
//
// Cost: ~32cc per 2 bytes (POP 12cc + SHLD 20cc) vs 16cc per byte via MOV.
// Break-even at 6 bytes (3 POP+SHLD = 96cc vs 6 MOV pairs = 96cc, but
// SP-trick saves setup cost amortized over larger copies).
//
// This pass is conservative: it only transforms patterns that are provably
// memcpy-like sequences. It wraps the sequence in DI/EI unless the function
// has the interrupt attribute (ISR), in which case the transformation is
// skipped entirely.
//
// Currently this pass recognizes expanded memcpy patterns emitted by the
// compiler (sequences of LXI+MOV pairs doing byte-by-byte copies) and
// replaces them. Since runtime library integration (M11) hasn't happened yet,
// this pass primarily enables future optimization when memcpy lowering is
// wired in.
//
//===----------------------------------------------------------------------===//

#include "V6Clang.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/Support/CommandLine.h"

using namespace llvm;

#define DEBUG_TYPE "v6clang-sp-trick"

static cl::opt<bool> DisableSPTrick(
    "v6clang-disable-sp-trick",
    cl::desc("Disable V6CLANG SP-trick memcpy/memset optimization"),
    cl::init(false), cl::Hidden);

/// Minimum copy size in bytes for which the SP-trick is profitable.
static constexpr unsigned SPTrickMinBytes = 6;

namespace {

class V6ClangSPTrickOpt : public MachineFunctionPass {
public:
  static char ID;
  V6ClangSPTrickOpt() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG SP-Trick Optimization";
  }

  bool runOnMachineFunction(MachineFunction &MF) override;

private:
  /// Try to find an expanded memcpy sequence starting at I and replace it.
  /// Returns true if a transformation was applied.
  bool tryTransformMemcpy(MachineBasicBlock &MBB,
                          MachineBasicBlock::iterator &I,
                          const TargetInstrInfo &TII);

  /// Detect a sequence of:
  ///   LXI HL, src_addr; MOV A, M;  LXI HL, dst_addr; MOV M, A
  /// repeated for consecutive addresses.
  /// Returns the number of bytes being copied (0 if not a recognized pattern).
  struct CopyPair {
    int64_t SrcAddr;
    int64_t DstAddr;
  };
  unsigned detectByteCopySequence(
      MachineBasicBlock::iterator Start,
      MachineBasicBlock::iterator End,
      SmallVectorImpl<CopyPair> &Pairs);
};

} // end anonymous namespace

char V6ClangSPTrickOpt::ID = 0;

unsigned V6ClangSPTrickOpt::detectByteCopySequence(
    MachineBasicBlock::iterator Start,
    MachineBasicBlock::iterator End,
    SmallVectorImpl<CopyPair> &Pairs) {
  Pairs.clear();
  auto I = Start;

  while (I != End) {
    // Pattern: LXI HL, src; MOV A, M; LXI HL, dst; MOV M, A
    if (I->getOpcode() != V6CLANG::LXI || I->getOperand(0).getReg() != V6CLANG::HL)
      break;
    if (!I->getOperand(1).isImm())
      break;
    int64_t SrcAddr = I->getOperand(1).getImm();
    auto Next1 = std::next(I);
    if (Next1 == End)
      break;

    // MOV A, M
    if (Next1->getOpcode() != V6CLANG::MOVrM || Next1->getOperand(0).getReg() != V6CLANG::A)
      break;
    auto Next2 = std::next(Next1);
    if (Next2 == End)
      break;

    // LXI HL, dst
    if (Next2->getOpcode() != V6CLANG::LXI || Next2->getOperand(0).getReg() != V6CLANG::HL)
      break;
    if (!Next2->getOperand(1).isImm())
      break;
    int64_t DstAddr = Next2->getOperand(1).getImm();
    auto Next3 = std::next(Next2);
    if (Next3 == End)
      break;

    // MOV M, A
    if (Next3->getOpcode() != V6CLANG::MOVMr || Next3->getOperand(0).getReg() != V6CLANG::A)
      break;

    Pairs.push_back({SrcAddr, DstAddr});
    I = std::next(Next3);
  }

  return Pairs.size();
}

bool V6ClangSPTrickOpt::tryTransformMemcpy(MachineBasicBlock &MBB,
                                         MachineBasicBlock::iterator &I,
                                         const TargetInstrInfo &TII) {
  SmallVector<CopyPair, 16> Pairs;
  unsigned Count = detectByteCopySequence(I, MBB.end(), Pairs);

  if (Count < SPTrickMinBytes)
    return false;

  // Verify that source addresses and destination addresses are each
  // consecutive (so we can use POP/SHLD efficiently).
  bool SrcConsecutive = true;
  bool DstConsecutive = true;
  for (unsigned i = 1; i < Count; ++i) {
    if (Pairs[i].SrcAddr != Pairs[i - 1].SrcAddr + 1)
      SrcConsecutive = false;
    if (Pairs[i].DstAddr != Pairs[i - 1].DstAddr + 1)
      DstConsecutive = false;
  }

  if (!SrcConsecutive || !DstConsecutive)
    return false;

  // Only optimize even-sized copies for now (POP reads 2 bytes at a time).
  // Odd byte handled with a single MOV at the end could be added later.
  unsigned EvenCount = Count & ~1u;
  if (EvenCount < SPTrickMinBytes)
    return false;

  DebugLoc DL = I->getDebugLoc();
  int64_t SrcBase = Pairs[0].SrcAddr;
  int64_t DstBase = Pairs[0].DstAddr;

  // Erase the original byte-copy instructions.
  auto EraseEnd = I;
  for (unsigned i = 0; i < EvenCount * 4; ++i) {
    if (EraseEnd == MBB.end())
      break;
    ++EraseEnd;
  }

  // Build SP-trick sequence.
  auto InsertPt = I;

  // DI
  BuildMI(MBB, InsertPt, DL, TII.get(V6CLANG::DI));

  // Save SP: LXI H, 0; DAD SP; XCHG → DE = old SP
  BuildMI(MBB, InsertPt, DL, TII.get(V6CLANG::LXI), V6CLANG::HL).addImm(0);
  BuildMI(MBB, InsertPt, DL, TII.get(V6CLANG::DAD)).addReg(V6CLANG::SP);
  BuildMI(MBB, InsertPt, DL, TII.get(V6CLANG::XCHG));

  // LXI SP, src_base
  BuildMI(MBB, InsertPt, DL, TII.get(V6CLANG::LXI), V6CLANG::SP).addImm(SrcBase);

  // For each 2-byte chunk: POP H; SHLD dst
  for (unsigned i = 0; i < EvenCount; i += 2) {
    BuildMI(MBB, InsertPt, DL, TII.get(V6CLANG::POP), V6CLANG::HL);
    BuildMI(MBB, InsertPt, DL, TII.get(V6CLANG::SHLD))
        .addReg(V6CLANG::HL)
        .addImm(DstBase + i);
  }

  // Restore SP: XCHG; SPHL
  BuildMI(MBB, InsertPt, DL, TII.get(V6CLANG::XCHG));
  BuildMI(MBB, InsertPt, DL, TII.get(V6CLANG::SPHL));

  // EI
  BuildMI(MBB, InsertPt, DL, TII.get(V6CLANG::EI));

  // Handle remaining odd byte if any.
  if (Count > EvenCount) {
    int64_t RemSrc = Pairs[EvenCount].SrcAddr;
    int64_t RemDst = Pairs[EvenCount].DstAddr;
    BuildMI(MBB, InsertPt, DL, TII.get(V6CLANG::LXI), V6CLANG::HL).addImm(RemSrc);
    BuildMI(MBB, InsertPt, DL, TII.get(V6CLANG::MOVrM), V6CLANG::A);
    BuildMI(MBB, InsertPt, DL, TII.get(V6CLANG::LXI), V6CLANG::HL).addImm(RemDst);
    BuildMI(MBB, InsertPt, DL, TII.get(V6CLANG::MOVMr)).addReg(V6CLANG::A);
  }

  // Erase original instructions.
  while (I != EraseEnd) {
    auto ToErase = I;
    ++I;
    ToErase->eraseFromParent();
  }

  return true;
}

bool V6ClangSPTrickOpt::runOnMachineFunction(MachineFunction &MF) {
  if (DisableSPTrick)
    return false;

  // Do not apply SP-trick inside ISR functions (interrupts already disabled,
  // and SP manipulation would corrupt the interrupt stack).
  if (MF.getFunction().hasFnAttribute("interrupt"))
    return false;

  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();
  bool Changed = false;

  for (MachineBasicBlock &MBB : MF) {
    for (auto I = MBB.begin(), E = MBB.end(); I != E; ) {
      if (tryTransformMemcpy(MBB, I, TII)) {
        Changed = true;
      } else {
        ++I;
      }
    }
  }

  return Changed;
}

FunctionPass *llvm::createV6ClangSPTrickOptPass() {
  return new V6ClangSPTrickOpt();
}
