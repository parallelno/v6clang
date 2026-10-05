//===-- V6ClangInstrCost.h - V6CLANG Dual Cost Model --------------------*- C++ -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
//===----------------------------------------------------------------------===//
//
// Dual cost model (Bytes + Cycles) for V6CLANG optimization decisions.
// Inspired by llvm-mos MOSInstrCost.
//
// Usage:
//   V6ClangOptMode Mode = getV6ClangOptMode(MF);
//   V6ClangInstrCost SeqA = V6ClangCost::INX * 3;
//   V6ClangInstrCost SeqB = V6ClangCost::LXI + V6ClangCost::DAD;
//   if (SeqA.isCheaperThan(SeqB, Mode)) { /* use INX chain */ }
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_V6CLANG_V6ClangINSTRCOST_H
#define LLVM_LIB_TARGET_V6CLANG_V6ClangINSTRCOST_H

#include "llvm/CodeGen/MachineFunction.h"
#include <cstdint>

namespace llvm {

/// Optimization mode derived from function attributes.
enum class V6ClangOptMode {
  Speed,    // -O2/-O3: cycles dominate, bytes break ties
  Size,     // -Os/-Oz: bytes dominate, cycles break ties
  Balanced  // -O1 or default: sum of bytes + cycles
};

/// Derive the optimization mode from a MachineFunction's attributes.
inline V6ClangOptMode getV6ClangOptMode(const MachineFunction &MF) {
  const Function &F = MF.getFunction();
  if (F.hasMinSize() || F.hasOptSize())
    return V6ClangOptMode::Size;
  if (MF.getTarget().getOptLevel() >= CodeGenOptLevel::Default)
    return V6ClangOptMode::Speed;
  return V6ClangOptMode::Balanced;
}

/// Dual cost: bytes and cycles for an instruction or sequence.
struct V6ClangInstrCost {
  int32_t Bytes = 0;
  int32_t Cycles = 0;

  constexpr V6ClangInstrCost() = default;
  constexpr V6ClangInstrCost(int32_t B, int32_t C) : Bytes(B), Cycles(C) {}

  /// Compose into a single comparable value based on optimization mode.
  /// - Speed: (Cycles << 16) + Bytes — cycles dominate
  /// - Size:  (Bytes << 16) + Cycles — bytes dominate
  /// - Balanced: Bytes + Cycles
  int64_t value(V6ClangOptMode Mode) const {
    switch (Mode) {
    case V6ClangOptMode::Speed:
      return (static_cast<int64_t>(Cycles) << 16) + Bytes;
    case V6ClangOptMode::Size:
      return (static_cast<int64_t>(Bytes) << 16) + Cycles;
    case V6ClangOptMode::Balanced:
      return static_cast<int64_t>(Bytes) + Cycles;
    }
    llvm_unreachable("invalid V6ClangOptMode");
  }

  bool isCheaperThan(const V6ClangInstrCost &RHS, V6ClangOptMode Mode) const {
    return value(Mode) < RHS.value(Mode);
  }

  bool isCheaperOrEqual(const V6ClangInstrCost &RHS, V6ClangOptMode Mode) const {
    return value(Mode) <= RHS.value(Mode);
  }

  V6ClangInstrCost operator+(const V6ClangInstrCost &RHS) const {
    return {Bytes + RHS.Bytes, Cycles + RHS.Cycles};
  }

  V6ClangInstrCost operator*(int N) const {
    return {Bytes * N, Cycles * N};
  }
};

/// Pre-defined costs for common V6CLANG (8080) instructions.
/// Values from V6ClangSchedule.td and V6ClangInstructionTimings.md.
namespace V6ClangCost {
  constexpr V6ClangInstrCost INX{1, 8};       // INX/DCX rp
  constexpr V6ClangInstrCost LXI{3, 12};      // LXI rp, d16
  constexpr V6ClangInstrCost DAD{1, 12};      // DAD rp
  constexpr V6ClangInstrCost MOVrr{1, 4};     // MOV r, r
  constexpr V6ClangInstrCost MOVrM{1, 8};     // MOV r, M
  constexpr V6ClangInstrCost MOVMr{1, 8};     // MOV M, r
  constexpr V6ClangInstrCost MVI{2, 8};       // MVI r, d8
  constexpr V6ClangInstrCost ALUreg{1, 4};    // ADD/SUB/ANA/ORA/XRA/CMP r
  constexpr V6ClangInstrCost ALUimm{2, 8};    // ADI/SUI/ANI/ORI/XRI/CPI d8
  constexpr V6ClangInstrCost ALUmem{1, 8};    // ADD/SUB/ANA/ORA/XRA/CMP M
  constexpr V6ClangInstrCost INR{1, 8};       // INR/DCR r
  constexpr V6ClangInstrCost PUSH{1, 16};     // PUSH rp
  constexpr V6ClangInstrCost POP{1, 12};      // POP rp
  constexpr V6ClangInstrCost Jcc{3, 12};      // Jcc addr / JMP addr
  constexpr V6ClangInstrCost CALL{3, 24};     // CALL addr
  constexpr V6ClangInstrCost RET{1, 12};      // RET
  constexpr V6ClangInstrCost LDA{3, 16};      // LDA addr
  constexpr V6ClangInstrCost STA{3, 16};      // STA addr
  constexpr V6ClangInstrCost LHLD{3, 20};     // LHLD addr
  constexpr V6ClangInstrCost SHLD{3, 20};     // SHLD addr
  constexpr V6ClangInstrCost XCHG{1, 4};      // XCHG
} // namespace V6ClangCost

} // namespace llvm

#endif // LLVM_LIB_TARGET_V6CLANG_V6ClangINSTRCOST_H
