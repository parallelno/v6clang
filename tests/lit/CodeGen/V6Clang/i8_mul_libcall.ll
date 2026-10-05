; O70 Step 3.11: i8 mul lowers to __mulqi3 libcall (not __mulhi3 via promotion).
; The trunc after libcall must elide when only low byte is consumed.
;
; RUN: llc -mtriple=i8080-unknown-v6clang < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

define i8 @i8_mul_low(i8 %a, i8 %b) {
; CHECK-LABEL: i8_mul_low:
; CHECK:     {{(CALL|JMP)}} __mulqi3
; CHECK-NOT: __mulhi3
  %r = mul i8 %a, %b
  ret i8 %r
}

define i16 @i8_mul_widen(i8 %a, i8 %b) {
; CHECK-LABEL: i8_mul_widen:
; CHECK:     {{(CALL|JMP)}} __mulhi3
  %za = zext i8 %a to i16
  %zb = zext i8 %b to i16
  %r = mul i16 %za, %zb
  ret i16 %r
}
