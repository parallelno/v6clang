; RUN: llc -march=v6clang < %s | FileCheck %s

; Test ADD16 DAD-based expansion paths (O40).
; The V6CLANG calling convention: 1st i16 in HL, 2nd in DE, 3rd in BC.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; Existing path: HL = HL + DE ??? DAD DE (12cc, 1B)
; CHECK-LABEL: test_hl_eq_hl_plus_de:
; CHECK:       DAD D
; CHECK-NEXT:  RET
define i16 @test_hl_eq_hl_plus_de(i16 %a, i16 %b) {
  %r = add i16 %a, %b
  ret i16 %r
}

; B1-DE: HL = DE + BC. DE is dead after (not used again).
; Should use XCHG; DAD BC (16cc, 2B) instead of MOV pair + DAD.
; CHECK-LABEL: test_b1_de:
; CHECK:       XCHG
; CHECK-NEXT:  DAD B
; CHECK-NEXT:  RET
define i16 @test_b1_de(i16 %a, i16 %b, i16 %c) {
  %r = add i16 %b, %c
  ret i16 %r
}

; Existing path: HL = HL + HL (add to self) ??? DAD HL (12cc, 1B)
; CHECK-LABEL: test_hl_eq_hl_plus_hl:
; CHECK:       DAD H
; CHECK-NEXT:  RET
define i16 @test_hl_eq_hl_plus_hl(i16 %a) {
  %r = add i16 %a, %a
  ret i16 %r
}
