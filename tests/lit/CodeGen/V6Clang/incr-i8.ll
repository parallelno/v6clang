; RUN: llc -march=v6clang < %s | FileCheck %s

; CHECK-LABEL: incr:
; CHECK:       INR A
; CHECK-NEXT:  RET
define i8 @incr(i8 %a) {
  %r = add i8 %a, 1
  ret i8 %r
}

; CHECK-LABEL: decr:
; CHECK:       DCR A
; CHECK-NEXT:  RET
define i8 @decr(i8 %a) {
  %r = add i8 %a, -1
  ret i8 %r
}
