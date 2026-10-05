; RUN: llc -march=v6clang < %s | FileCheck %s

; Test calling convention: i8 arg in A, return i8 in A.
; CHECK-LABEL: pass_one_i8:
; CHECK:       RET
define i8 @pass_one_i8(i8 %x) {
  ret i8 %x
}

; Test two i8 args: first in A, second in B.
; CHECK-LABEL: add_two_i8:
; CHECK:       ADD B
; CHECK-NEXT:  RET
define i8 @add_two_i8(i8 %a, i8 %b) {
  %r = add i8 %a, %b
  ret i8 %r
}

; Test three i8 args: A, B, C.
; CHECK-LABEL: add_three_i8:
; CHECK:       ADD B
; CHECK:       ADD C
; CHECK:       RET
define i8 @add_three_i8(i8 %a, i8 %b, i8 %c) {
  %r1 = add i8 %a, %b
  %r2 = add i8 %r1, %c
  ret i8 %r2
}

; Test i16 arg in HL, return i16 in HL.
; CHECK-LABEL: pass_one_i16:
; CHECK:       RET
define i16 @pass_one_i16(i16 %x) {
  ret i16 %x
}
