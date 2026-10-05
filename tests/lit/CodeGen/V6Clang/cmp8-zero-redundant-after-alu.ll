; RUN: llc -march=v6clang < %s | FileCheck %s

; O91: V6ClangRedundantFlagElim -- eliminate the XRA A + CMP R bridge pattern
; emitted by V6CLANG_CMP8_ZERO shape 2 when R holds A's value from the last
; flag-setting ALU op (Z is already valid from the ALU op).
;
; The pattern arises from i16 xor/and/or with hi-byte dead (O89) and then
; CMP8_ZERO shape 2 (XRA A; CMP R) to test the lo-byte result:
;
;   <ALU op>          ; A = lo-result; Z = (lo-result == 0) <- Z ALREADY VALID
;   MOV  R, A         ; R = lo-result; FLAGS untouched
;   XRA  A            ; <- CMP8_ZERO shape 2 start  -- REDUNDANT
;   CMP  R            ; <- REDUNDANT
;
; After O91: MOV R,A + XRA A + CMP R are eliminated.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; --- Test 1: (i16 xor) truncated to i8, compare to zero ---
; hi-byte is dead -> O89 emits only lo-byte ALU; O91 removes MOV+XRA A+CMP.
; CHECK-LABEL: test_xor16_cmp_zero:
; CHECK:       XRA
; CHECK-NOT:   XRA A
; CHECK-NOT:   CMP
; CHECK:       J{{Z|NZ}}
define i8 @test_xor16_cmp_zero(i16 %a, i16 %b) {
  %xor  = xor i16 %a, %b
  %lo   = trunc i16 %xor to i8
  %cmp  = icmp eq i8 %lo, 0
  %res  = zext i1 %cmp to i8
  ret i8 %res
}

; --- Test 2: (i16 and) truncated to i8, compare to zero ---
; CHECK-LABEL: test_and16_cmp_zero:
; CHECK:       ANA
; CHECK-NOT:   XRA A
; CHECK-NOT:   CMP
; CHECK:       J{{Z|NZ}}
define i8 @test_and16_cmp_zero(i16 %a, i16 %b) {
  %and  = and i16 %a, %b
  %lo   = trunc i16 %and to i8
  %cmp  = icmp eq i8 %lo, 0
  %res  = zext i1 %cmp to i8
  ret i8 %res
}

; --- Test 3: (i16 or) truncated to i8, compare to zero ---
; CHECK-LABEL: test_or16_cmp_zero:
; CHECK:       ORA
; CHECK-NOT:   XRA A
; CHECK-NOT:   CMP
; CHECK:       J{{Z|NZ}}
define i8 @test_or16_cmp_zero(i16 %a, i16 %b) {
  %or   = or i16 %a, %b
  %lo   = trunc i16 %or to i8
  %cmp  = icmp eq i8 %lo, 0
  %res  = zext i1 %cmp to i8
  ret i8 %res
}

; --- Test 4: control -- full i16 xor used, no zero-test, O91 must NOT fire ---
; Both bytes live -> O89 does not elide hi-byte; O91 has nothing to erase.
; CHECK-LABEL: test_xor16_full:
; CHECK:       XRA
; CHECK:       MOV
; CHECK:       XRA
; CHECK:       MOV
; CHECK:       RET
define i16 @test_xor16_full(i16 %a, i16 %b) {
  %xor = xor i16 %a, %b
  ret i16 %xor
}
