; RUN: llc -march=v6clang < %s | FileCheck %s

; CHECK-LABEL: and_reg:
; CHECK:       ANA B
; CHECK-NEXT:  RET
define i8 @and_reg(i8 %a, i8 %b) {
  %r = and i8 %a, %b
  ret i8 %r
}

; 240 = 0xF0, printed as sign-extended 64-bit by LLVM's default printer.
; CHECK-LABEL: and_imm:
; CHECK:       ANI
; CHECK-NEXT:  RET
define i8 @and_imm(i8 %a) {
  %r = and i8 %a, 240
  ret i8 %r
}
