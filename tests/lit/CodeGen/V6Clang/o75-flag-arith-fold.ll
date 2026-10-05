; RUN: llc -march=v6clang < %s | FileCheck %s

; O75 Phase B: i8 ADD/SUB/AND/OR/XOR + (icmp eq/ne 0) folds the FLAGS
; produced by the arithmetic into the conditional branch — no CPI 0.

@g_sink = external global i8

;-----------------------------------------------------------------------------
; AND-against-zero: ANI 0xf produces FLAGS, JNZ consumes it.
;-----------------------------------------------------------------------------
define i8 @mask_test(i8 %x) {
; CHECK-LABEL: mask_test:
; CHECK:      ANI 0xf
; CHECK-NEXT: JZ
; CHECK-NOT:  CPI 0
  %m = and i8 %x, 15
  %c = icmp eq i8 %m, 0
  %r = select i1 %c, i8 1, i8 0
  ret i8 %r
}

;-----------------------------------------------------------------------------
; XOR-against-zero (equality test on i8): XRA L produces FLAGS, JZ consumes.
;-----------------------------------------------------------------------------
define i8 @xor_eq(i8 %x, i8 %y) {
; CHECK-LABEL: xor_eq:
; CHECK:      XRA
; CHECK:      JNZ
; CHECK-NOT:  CPI 0
  %z = xor i8 %x, %y
  %c = icmp eq i8 %z, 0
  store volatile i8 %z, ptr @g_sink
  %r = select i1 %c, i8 0, i8 1
  ret i8 %r
}

;-----------------------------------------------------------------------------
; SUB-against-zero (5 == x): ADI 0xfb produces FLAGS, JZ consumes.
;-----------------------------------------------------------------------------
define i8 @sub_eq(i8 %x) {
; CHECK-LABEL: sub_eq:
; CHECK:      ADI 0xfb
; CHECK:      JNZ
; CHECK-NOT:  CPI 0
  %d = sub i8 %x, 5
  %c = icmp eq i8 %d, 0
  store volatile i8 %d, ptr @g_sink
  %r = select i1 %c, i8 0, i8 1
  ret i8 %r
}

;-----------------------------------------------------------------------------
; DCR loop counter: DCR A produces FLAGS, JNZ consumes.
;-----------------------------------------------------------------------------
define void @dec_loop(i8 %n) {
; CHECK-LABEL: dec_loop:
; CHECK:      DCR
; CHECK-NEXT: JNZ
; CHECK-NOT:  CPI 0
entry:
  %t0 = icmp eq i8 %n, 0
  br i1 %t0, label %exit, label %loop

loop:
  %i = phi i8 [ %n, %entry ], [ %dec, %loop ]
  store volatile i8 %i, ptr @g_sink
  %dec = sub i8 %i, 1
  %done = icmp eq i8 %dec, 0
  br i1 %done, label %exit, label %loop

exit:
  ret void
}

;-----------------------------------------------------------------------------
; INR-as-flag: INR r produces FLAGS, JNZ consumes.
;-----------------------------------------------------------------------------
define i8 @inc_test(i8 %x) {
; CHECK-LABEL: inc_test:
; CHECK:      INR
; CHECK:      JZ
; CHECK-NOT:  CPI 0
  %i = add i8 %x, 1
  %c = icmp eq i8 %i, 0
  store volatile i8 %i, ptr @g_sink
  %r = select i1 %c, i8 0, i8 1
  ret i8 %r
}

;-----------------------------------------------------------------------------
; XOR with 0xFF must remain a CMA (does not produce FLAGS).
;-----------------------------------------------------------------------------
define i8 @not_a(i8 %x) {
; CHECK-LABEL: not_a:
; CHECK: CMA
  %r = xor i8 %x, -1
  ret i8 %r
}
