; RUN: llc -march=v6clang < %s | FileCheck %s

; CHECK-LABEL: xor_reg:
; CHECK:       XRA B
; CHECK-NEXT:  RET
define i8 @xor_reg(i8 %a, i8 %b) {
  %r = xor i8 %a, %b
  ret i8 %r
}

; CHECK-LABEL: xor_imm:
; CHECK:       XRI 0x55
; CHECK-NEXT:  RET
define i8 @xor_imm(i8 %a) {
  %r = xor i8 %a, 85
  ret i8 %r
}

; CHECK-LABEL: not_a:
; CHECK:       CMA
; CHECK-NEXT:  RET
define i8 @not_a(i8 %a) {
  %r = xor i8 %a, -1
  ret i8 %r
}
