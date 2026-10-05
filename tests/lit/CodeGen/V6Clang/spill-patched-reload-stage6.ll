; RUN: llc -march=v6clang -O2 -mv6clang-spill-patched-reload -v6clang-disable-shld-lhld-fold < %s | FileCheck %s
; RUN: llc -march=v6clang -O2 -mv6clang-no-spill-patched-reload -v6clang-disable-shld-lhld-fold < %s | FileCheck %s --check-prefix=DISABLED

; O61 Stage 6: widen the i8 spill-source filter from A-only (Stage 4)
; to any GR8 (A, B, C, D, E, H, L). The A-source fast path (STA Sym+1)
; is unchanged; non-A i8 spills now route through the shared O64
; ladder (expandSpill8Static) with the appender supplying
; <Sym[0] + MO_PATCH_IMM>. The reload-side emitter (MVI r, 0) is
; unchanged from Stage 4.
;
; K-cap rules:
;   * A-source i8 spill: K ??? 2 (Stage 4, unchanged).
;   * non-A i8 spill:    K ??? 1 (Stage 6 hard-cap).

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare i8 @op1(i8)
declare i8 @op2(i8)
declare void @use3(i8, i8, i8)

; Three i8 values across two A/HL-clobbering calls. RA distributes the
; live values across A and non-A GR8; at least one must be held in
; B/C/D/E and spilled through a non-A source. Stage 4 rejected those
; slots (fall-through to classical O64); Stage 6 patches them.
;
; The BC spill of arg2 (%z) uses the Shape B Row-1 ladder (HL dead at
; the spill) terminating in `LXI HL, .LLo61_*+1; MOV M, r`.
; The DE spill of arg1 (%y) uses the same ladder.
; The A spill of %a uses the Stage 4 fast path (STA .LLo61_*+1).
;
; CHECK-LABEL: three_i8:
; CHECK:       LXI     H, .L[[S1:Lo61_[0-9]+]]+1
; CHECK-NEXT:  MOV     M, {{[BCE]}}
; CHECK:       LXI     H, .L[[S2:Lo61_[0-9]+]]+1
; CHECK-NEXT:  MOV     M, {{[BCE]}}
; CHECK:       CALL    op1
; CHECK-NEXT:  STA     .L[[S3:Lo61_[0-9]+]]+1
;
; With the flag off, Stage 5's O64 ladder uses the BSS slot.
; DISABLED-LABEL: three_i8:
; DISABLED-NOT: .LLo61_
; DISABLED:    LXI     H, __v6clang_ss.three_i8
; DISABLED:    STA     __v6clang_ss.three_i8
define i8 @three_i8(i8 %x, i8 %y, i8 %z) norecurse {
entry:
  %a = call i8 @op1(i8 %x)
  %b = call i8 @op2(i8 %y)
  %c = call i8 @op1(i8 %z)
  call void @use3(i8 %a, i8 %b, i8 %c)
  %s1 = add i8 %a, %b
  %s2 = add i8 %s1, %c
  ret i8 %s2
}
