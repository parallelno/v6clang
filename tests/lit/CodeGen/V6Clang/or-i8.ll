; RUN: llc -march=v6clang < %s | FileCheck %s

; CHECK-LABEL: or_reg:
; CHECK:       ORA B
; CHECK-NEXT:  RET
define i8 @or_reg(i8 %a, i8 %b) {
  %r = or i8 %a, %b
  ret i8 %r
}

; CHECK-LABEL: or_imm:
; CHECK:       ORI 7
; CHECK-NEXT:  RET
define i8 @or_imm(i8 %a) {
  %r = or i8 %a, 7
  ret i8 %r
}
