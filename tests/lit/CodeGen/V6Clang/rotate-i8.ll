; RUN: llc -march=v6clang < %s | FileCheck %s
;
; O67 — i8 rotate ISel via RLC/RRC.
; Constant-amount i8 rotates lower to a chain of 1-bit RLC/RRC,
; with direction canonicalised to the shorter chain.

; CHECK-LABEL: rotl1:
; CHECK:       RLC
; CHECK-NEXT:  RET
; CHECK-NOT:   RAR
; CHECK-NOT:   ORA
define i8 @rotl1(i8 %x) {
  %a = shl i8 %x, 1
  %b = lshr i8 %x, 7
  %r = or i8 %a, %b
  ret i8 %r
}

; CHECK-LABEL: rotr1:
; CHECK:       RRC
; CHECK-NEXT:  RET
; CHECK-NOT:   RAR
define i8 @rotr1(i8 %x) {
  %a = lshr i8 %x, 1
  %b = shl i8 %x, 7
  %r = or i8 %a, %b
  ret i8 %r
}

; CHECK-LABEL: rotl3:
; CHECK:       RLC
; CHECK-NEXT:  RLC
; CHECK-NEXT:  RLC
; CHECK-NEXT:  RET
; CHECK-NOT:   RAR
define i8 @rotl3(i8 %x) {
  %a = shl i8 %x, 3
  %b = lshr i8 %x, 5
  %r = or i8 %a, %b
  ret i8 %r
}

; rotl by 7 == rotr by 1 (canonicalised to the shorter chain).
; CHECK-LABEL: rotl7:
; CHECK:       RRC
; CHECK-NEXT:  RET
; CHECK-NOT:   RLC
define i8 @rotl7(i8 %x) {
  %a = shl i8 %x, 7
  %b = lshr i8 %x, 1
  %r = or i8 %a, %b
  ret i8 %r
}

; rotl by 4: tie (4 left == 4 right) — keep the requested direction.
; CHECK-LABEL: rotl4:
; CHECK:       RLC
; CHECK-NEXT:  RLC
; CHECK-NEXT:  RLC
; CHECK-NEXT:  RLC
; CHECK-NEXT:  RET
define i8 @rotl4(i8 %x) {
  %a = shl i8 %x, 4
  %b = lshr i8 %x, 4
  %r = or i8 %a, %b
  ret i8 %r
}

; rotr by 3.
; CHECK-LABEL: rotr3:
; CHECK:       RRC
; CHECK-NEXT:  RRC
; CHECK-NEXT:  RRC
; CHECK-NEXT:  RET
; CHECK-NOT:   RAR
define i8 @rotr3(i8 %x) {
  %a = lshr i8 %x, 3
  %b = shl i8 %x, 5
  %r = or i8 %a, %b
  ret i8 %r
}
