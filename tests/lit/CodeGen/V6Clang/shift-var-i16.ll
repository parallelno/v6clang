; RUN: llc -mtriple=i8080-unknown-v6clang -verify-machineinstrs < %s | FileCheck %s

; Test that i16 variable shift left generates a call to __ashlhi3

define i16 @test_shl_var(i16 %val, i16 %amt) {
; CHECK-LABEL: test_shl_var:
; CHECK: JMP __ashlhi3
  %r = shl i16 %val, %amt
  ret i16 %r
}

; Test that i16 variable logical right shift generates a call to __lshrhi3

define i16 @test_lshr_var(i16 %val, i16 %amt) {
; CHECK-LABEL: test_lshr_var:
; CHECK: JMP __lshrhi3
  %r = lshr i16 %val, %amt
  ret i16 %r
}

; Test that i16 variable arithmetic right shift generates a call to __ashrhi3

define i16 @test_ashr_var(i16 %val, i16 %amt) {
; CHECK-LABEL: test_ashr_var:
; CHECK: JMP __ashrhi3
  %r = ashr i16 %val, %amt
  ret i16 %r
}

; Test that constant shifts are NOT libcalls (should be unrolled)

define i16 @test_shl_const(i16 %val) {
; CHECK-LABEL: test_shl_const:
; CHECK-NOT: CALL __ashlhi3
; CHECK: DAD H
  %r = shl i16 %val, 1
  ret i16 %r
}
