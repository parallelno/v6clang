; RUN: llc -march=v6clang < %s | FileCheck %s

; CHECK-LABEL: add_i16:
; CHECK:       DAD D
; CHECK-NEXT:  RET
define i16 @add_i16(i16 %a, i16 %b) {
  %r = add i16 %a, %b
  ret i16 %r
}

; CHECK-LABEL: add_i16_stack_args:
; CHECK:       LXI H, 2
; CHECK:       DAD SP
; CHECK:       MOV C, M
; CHECK:       INX H
; CHECK:       MOV B, M
; CHECK:       XCHG
; CHECK-NEXT:  DAD B
; CHECK-NEXT:  XCHG
; CHECK:       RET
define i16 @add_i16_stack_args(i16 %x, i16 %y, i16 %z, i16 %w, i16 %a) norecurse {
entry:
  %s1 = add i16 %y, %x
  %s2 = add i16 %s1, %z
  %s3 = add i16 %s2, %w
  %s4 = add i16 %s3, %a
  ret i16 %s4
}
