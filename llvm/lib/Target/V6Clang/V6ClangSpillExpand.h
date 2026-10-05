//===-- V6ClangSpillExpand.h - Shared i8 spill/reload expander ----*- C++ -*-===//
//
// Part of the V6CLANG backend for LLVM.
//
// Shared decision-ladder expander for V6CLANG_SPILL8 / V6CLANG_RELOAD8 when the
// slot address resolves to a static storage site (either a static-stack
// GlobalAddress from V6ClangStaticStackAlloc, or a patch-point MCSymbol from
// O61 / V6ClangSpillPatchedReload). Callers supply the final address operand
// via AppendAddrFn so the same ladder handles both address kinds.
//
// O64 (Liveness-Aware i8 Spill/Reload Lowering, Shapes B & C).
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_V6CLANG_V6ClangSPILLEXPAND_H
#define LLVM_LIB_TARGET_V6CLANG_V6ClangSPILLEXPAND_H

#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/CodeGen/MachineBasicBlock.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/Register.h"

namespace llvm {

class MachineInstr;
class TargetInstrInfo;
class TargetRegisterInfo;

/// Check if a physical register is dead after MI. Scans forward from
/// MI (exclusive) to end of MBB, then checks successor live-ins.
bool isRegDeadAfterMI(unsigned Reg, const MachineInstr &MI,
                      MachineBasicBlock &MBB,
                      const TargetRegisterInfo *TRI);

/// Pair-aware variant: returns true only if BOTH 8-bit halves of the
/// pair register are dead after MI. Use this at expansion sites that
/// want to clobber the whole pair without restoring it.
///
/// `isRegDeadAfterMI(V6CLANG::HL, ...)` is unsafe at such sites: it treats
/// the pair as a single value, so a later instruction that defines just
/// L (or just H) makes it report dead even when the other half is still
/// read downstream. See `plan_O81_pair_deadness_fix.md`.
bool isPairDeadAfterMI(unsigned PairReg, const MachineInstr &MI,
                       MachineBasicBlock &MBB,
                       const TargetRegisterInfo *TRI);

/// Return the first register in {B, C, D, E}, excluding any register
/// whose aliases overlap `Excluded`, that is dead after MI. Returns a
/// default-constructed Register() if none qualifies.
Register findDeadSpareGPR8(Register Excluded, const MachineInstr &MI,
                           MachineBasicBlock &MBB,
                           const TargetRegisterInfo *TRI);

/// Callback: append the final address operand to an LXI/STA/LDA builder.
/// The same ladder body is used for both static-stack (GlobalAddress +
/// offset) and O61 patch-point (MCSymbol + MO_PATCH_IMM) address kinds.
using AppendAddrFn = llvm::function_ref<void(MachineInstrBuilder &)>;

/// Emit the O64 decision ladder for a V6CLANG_SPILL8 at `InsertBefore`.
///
/// The caller is expected to handle Shape A (SrcReg == A) inline with a
/// single STA. This helper covers Shape B (SrcReg in {B,C,D,E}) and
/// Shape C (SrcReg in {H, L}). Does NOT erase `MI` — caller owns it.
void expandSpill8Static(MachineInstr &MI,
                        MachineBasicBlock::iterator InsertBefore,
                        Register SrcReg, bool SrcIsKill,
                        const TargetInstrInfo &TII,
                        const TargetRegisterInfo *TRI,
                        AppendAddrFn AppendAddr);

/// Emit the O64 decision ladder for a V6CLANG_RELOAD8 at `InsertBefore`.
///
/// The caller is expected to handle Shape A (DstReg == A) inline with a
/// single LDA. This helper covers Shape B (DstReg in {B,C,D,E}) and
/// Shape C (DstReg in {H, L}). Does NOT erase `MI` — caller owns it.
void expandReload8Static(MachineInstr &MI,
                         MachineBasicBlock::iterator InsertBefore,
                         Register DstReg,
                         const TargetInstrInfo &TII,
                         const TargetRegisterInfo *TRI,
                         AppendAddrFn AppendAddr);

} // end namespace llvm

#endif // LLVM_LIB_TARGET_V6CLANG_V6ClangSPILLEXPAND_H
