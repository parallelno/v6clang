; RUN: llc -march=v6clang < %s | FileCheck %s

; CHECK-LABEL: add_reg:
; CHECK:       ADD B
; CHECK-NEXT:  RET
define i8 @add_reg(i8 %a, i8 %b) {
  %r = add i8 %a, %b
  ret i8 %r
}

; CHECK-LABEL: add_imm:
; CHECK:       ADI 5
; CHECK-NEXT:  RET
define i8 @add_imm(i8 %a) {
  %r = add i8 %a, 5
  ret i8 %r
}
