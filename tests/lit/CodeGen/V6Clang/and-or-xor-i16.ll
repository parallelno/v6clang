; RUN: llc -march=v6clang < %s | FileCheck %s

; CHECK-LABEL: and_i16:
; CHECK:       MOV A, L
; CHECK-NEXT:  ANA E
; CHECK-NEXT:  MOV L, A
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  ANA D
; CHECK-NEXT:  MOV H, A
; CHECK-NEXT:  RET
define i16 @and_i16(i16 %a, i16 %b) {
  %r = and i16 %a, %b
  ret i16 %r
}

; CHECK-LABEL: or_i16:
; CHECK:       MOV A, L
; CHECK-NEXT:  ORA E
; CHECK-NEXT:  MOV L, A
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  ORA D
; CHECK-NEXT:  MOV H, A
; CHECK-NEXT:  RET
define i16 @or_i16(i16 %a, i16 %b) {
  %r = or i16 %a, %b
  ret i16 %r
}

; CHECK-LABEL: xor_i16:
; CHECK:       MOV A, L
; CHECK-NEXT:  XRA E
; CHECK-NEXT:  MOV L, A
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  XRA D
; CHECK-NEXT:  MOV H, A
; CHECK-NEXT:  RET
define i16 @xor_i16(i16 %a, i16 %b) {
  %r = xor i16 %a, %b
  ret i16 %r
}
