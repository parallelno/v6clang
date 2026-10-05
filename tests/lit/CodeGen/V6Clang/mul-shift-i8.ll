; RUN: llc -mtriple=i8080-unknown-v6clang -verify-machineinstrs < %s | FileCheck %s

; O70: i8 multiply now uses its own libcall (__mulqi3, 8 iterations)
; instead of being promoted to i16's __mulhi3 (16 iterations).

define i8 @test_mul_i8(i8 %a, i8 %b) {
; CHECK-LABEL: test_mul_i8:
; CHECK: {{(CALL|JMP)}} __mulqi3
  %r = mul i8 %a, %b
  ret i8 %r
}

; Test that i8 variable shift left (promoted to i16) emits libcall

define i8 @test_shl_i8_var(i8 %val, i8 %amt) {
; CHECK-LABEL: test_shl_i8_var:
; CHECK: CALL __ashlhi3
  %r = shl i8 %val, %amt
  ret i8 %r
}

; Test that i8 variable logical right shift emits libcall

define i8 @test_lshr_i8_var(i8 %val, i8 %amt) {
; CHECK-LABEL: test_lshr_i8_var:
; CHECK: CALL __lshrhi3
  %r = lshr i8 %val, %amt
  ret i8 %r
}

; Test that i8 variable arithmetic right shift emits libcall

define i8 @test_ashr_i8_var(i8 %val, i8 %amt) {
; CHECK-LABEL: test_ashr_i8_var:
; CHECK: CALL __ashrhi3
  %r = ashr i8 %val, %amt
  ret i8 %r
}
