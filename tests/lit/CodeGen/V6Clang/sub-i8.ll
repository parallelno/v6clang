; RUN: llc -march=v6clang < %s | FileCheck %s

; CHECK-LABEL: sub_reg:
; CHECK:       SUB B
; CHECK-NEXT:  RET
define i8 @sub_reg(i8 %a, i8 %b) {
  %r = sub i8 %a, %b
  ret i8 %r
}

; LLVM canonicalizes sub x, C to add x, -C.
; CHECK-LABEL: sub_imm:
; CHECK:       ADI
; CHECK-NEXT:  RET
define i8 @sub_imm(i8 %a) {
  %r = sub i8 %a, 3
  ret i8 %r
}
