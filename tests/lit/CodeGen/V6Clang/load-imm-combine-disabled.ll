; RUN: llc -march=v6clang -v6clang-disable-load-imm-combine < %s | FileCheck %s

; Test that -v6clang-disable-load-imm-combine preserves original MVI instructions.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@g_out8 = external global i8

; When disabled, MVI A, 0xb should remain (not INR A).
; CHECK-LABEL: test_disabled:
; CHECK:       MVI A, 0xa
; CHECK:       STA g_out8
; CHECK-NEXT:  MVI A, 0xb
; CHECK-NEXT:  STA g_out8
define void @test_disabled() {
  store volatile i8 10, ptr @g_out8
  store volatile i8 11, ptr @g_out8
  ret void
}
