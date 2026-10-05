; RUN: llc -march=v6clang < %s | FileCheck %s

; CHECK-LABEL: const_zero:
; CHECK:       XRA A
; CHECK-NEXT:  RET
define i8 @const_zero() {
  ret i8 0
}

; 255 printed as sign-extended 64-bit hex by LLVM's default printer.
; CHECK-LABEL: const_ff:
; CHECK:       MVI A,
; CHECK-NEXT:  RET
define i8 @const_ff() {
  ret i8 255
}

; CHECK-LABEL: const_to_reg:
; CHECK:       ADI 0x2a
; CHECK-NEXT:  RET
define i8 @const_to_reg(i8 %a) {
  %r = add i8 %a, 42
  ret i8 %r
}
