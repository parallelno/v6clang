; RUN: llc -march=v6clang < %s | FileCheck %s

; Test that i16 add-by-1 becomes INX instead of 8-bit chain.
; CHECK-LABEL: inc16:
; CHECK:       INX H
; CHECK-NOT:   ADC
; CHECK:       RET
define i16 @inc16(i16 %x) {
  %r = add i16 %x, 1
  ret i16 %r
}

; Test that i16 sub-by-1 becomes DCX.
; CHECK-LABEL: dec16:
; CHECK:       DCX H
; CHECK-NOT:   SBB
; CHECK:       RET
define i16 @dec16(i16 %x) {
  %r = sub i16 %x, 1
  ret i16 %r
}

; Test that add-by-2 becomes an INX chain (2x INX).
; CHECK-LABEL: add_two:
; CHECK:       INX H
; CHECK-NEXT:  INX H
; CHECK-NOT:   ADC
; CHECK:       RET
define i16 @add_two(i16 %x) {
  %r = add i16 %x, 2
  ret i16 %r
}

; Test that sub-by-2 becomes a DCX chain (2x DCX).
; CHECK-LABEL: sub_two:
; CHECK:       DCX H
; CHECK-NEXT:  DCX H
; CHECK-NOT:   SBB
; CHECK:       RET
define i16 @sub_two(i16 %x) {
  %r = sub i16 %x, 2
  ret i16 %r
}

; Test that add-by-3 becomes an INX chain (3x INX).
; CHECK-LABEL: add_three:
; CHECK:       INX H
; CHECK-NEXT:  INX H
; CHECK-NEXT:  INX H
; CHECK-NOT:   ADC
; CHECK:       RET
define i16 @add_three(i16 %x) {
  %r = add i16 %x, 3
  ret i16 %r
}

; Test that sub-by-3 becomes a DCX chain (3x DCX).
; CHECK-LABEL: sub_three:
; CHECK:       DCX H
; CHECK-NEXT:  DCX H
; CHECK-NEXT:  DCX H
; CHECK-NOT:   SBB
; CHECK:       RET
define i16 @sub_three(i16 %x) {
  %r = sub i16 %x, 3
  ret i16 %r
}

; Test that add-by-4 does NOT become an INX chain (beyond +/-3 limit).
; CHECK-LABEL: add_four:
; CHECK-NOT:   INX
; CHECK-NOT:   INX
; CHECK:       DAD
define i16 @add_four(i16 %x) {
  %r = add i16 %x, 4
  ret i16 %r
}
