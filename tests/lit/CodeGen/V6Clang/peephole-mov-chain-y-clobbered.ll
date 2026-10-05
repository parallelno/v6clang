; RUN: llc -march=v6clang < %s | FileCheck %s
; RUN: llc -march=v6clang --v6clang-disable-peephole < %s | FileCheck %s --check-prefix=DISABLED
;
; O93: the 16-bit constant XOR tap of an LFSR hot loop must lower to the
; immediate bitwise pseudo (V6CLANG_XOR16_IMM) — `MVI A, hi ; XRA reg ; MOV reg, A`
; — instead of materialising the constant into a scratch register pair
; (`LXI B, 0xb400` + reg/reg V6CLANG_XOR16).
;
; History: this test previously guarded the collapseMovChain "rewrite-producer"
; transform (O89), which fired when register pressure spilled the 16-bit loop
; state and reloaded its lo-byte through a MOV chain clobbered by a POP H.
; O93 removes the *need* for the scratch constant pair, which lowers register
; pressure enough that this LFSR no longer spills through that MOV chain at all:
; the surviving accumulator spill now reloads straight into A via the O61
; patched landing pad (`.LLo61_0: MVI A, 0 ; ANI 1`).  The rewrite-producer
; transform remains in V6ClangPeephole.cpp (collapseMovChain) and is exercised by
; the C benchmark suite; this test now pins the O93 lowering that obsoleted the
; old spill scenario.
;
; The tap constant is 0xB400 (-19456): the lo byte 0x00 is an XOR identity and
; is folded away, so only the hi byte is emitted.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; O93 lowering: single hi-byte XOR through A, no scratch pair for the constant.
; CHECK-LABEL:     main:
; CHECK-NOT:       LXI     {{[BD]}}, 0xb400
; CHECK:           MVI     A, 0xb4
; CHECK-NEXT:      XRA     [[HI:[BH]]]
; CHECK-NEXT:      MOV     [[HI]], A

; The expansion is independent of the peephole pass: same O93 form with it off.
; DISABLED-LABEL:  main:
; DISABLED-NOT:    LXI     {{[BD]}}, 0xb400
; DISABLED:        MVI     A, 0xb4
; DISABLED-NEXT:   XRA     [[HI:[BH]]]
; DISABLED-NEXT:   MOV     [[HI]], A

define dso_local noundef i16 @main(i16 noundef %0, ptr nocapture noundef readnone %1) local_unnamed_addr {
  %3 = alloca i16, align 2
  call void @llvm.lifetime.start.p0(i64 2, ptr nonnull %3)
  store volatile i16 -21279, ptr %3, align 2
  %4 = load volatile i16, ptr %3, align 2
  br label %5

5:
  %6 = phi i16 [ %4, %2 ], [ %13, %5 ]
  %7 = phi i16 [ 0, %2 ], [ %15, %5 ]
  %8 = phi i16 [ 0, %2 ], [ %14, %5 ]
  %9 = lshr i16 %6, 1
  %10 = and i16 %6, 1
  %11 = icmp eq i16 %10, 0
  %12 = xor i16 %9, -19456
  %13 = select i1 %11, i16 %9, i16 %12
  %14 = xor i16 %13, %8
  %15 = add nuw nsw i16 %7, 1
  %16 = icmp eq i16 %15, 4096
  br i1 %16, label %17, label %5

17:
  %18 = lshr i16 %14, 8
  %19 = xor i16 %18, %14
  %20 = trunc i16 %19 to i8
  tail call void @llvm.v6clang.out(i8 -19, i8 %20)
  tail call void @llvm.v6clang.hlt()
  unreachable
}

declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture)
declare void @llvm.v6clang.out(i8, i8)
declare void @llvm.v6clang.hlt()
