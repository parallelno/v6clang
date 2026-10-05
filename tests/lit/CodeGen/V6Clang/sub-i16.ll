; RUN: llc -march=v6clang < %s | FileCheck %s

; CHECK-LABEL: sub_i16:
; CHECK:       MOV A, L
; CHECK-NEXT:  SUB E
; CHECK-NEXT:  MOV L, A
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  SBB D
; CHECK-NEXT:  MOV H, A
; CHECK-NEXT:  RET
define i16 @sub_i16(i16 %a, i16 %b) {
  %r = sub i16 %a, %b
  ret i16 %r
}
