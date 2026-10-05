; RUN: llc -mtriple=i8080-unknown-v6clang -verify-machineinstrs < %s | FileCheck %s

; Test that i16 multiply generates an efficient tail call to __mulhi3 with no
; operand shuffling.  The HL-sourced first argument must map directly to the
; physical HL register required by the V6CLANG calling convention so that zero
; copy instructions are emitted before the JMP.

define i16 @test_mul_i16(i16 %a, i16 %b) {
; CHECK-LABEL: test_mul_i16:
; Verify no MOV or XCHG appears between the function label and the JMP —
; that would be an unnecessary HL↔DE register shuffle (5 instructions).
; CHECK-NOT: MOV
; CHECK-NOT: XCHG
; CHECK:     JMP __mulhi3
  %r = mul i16 %a, %b
  ret i16 %r
}

; Same with operands reversed at the IR level: the DAG combine must
; re-canonicalize so the HL-sourced value (%a) is again first arg.

define i16 @test_mul_i16_rev(i16 %a, i16 %b) {
; CHECK-LABEL: test_mul_i16_rev:
; CHECK-NOT: MOV
; CHECK-NOT: XCHG
; CHECK:     JMP __mulhi3
  %r = mul i16 %b, %a
  ret i16 %r
}

; Test that i16 signed divide generates a call to __divhi3

define i16 @test_sdiv_i16(i16 %a, i16 %b) {
; CHECK-LABEL: test_sdiv_i16:
; CHECK: JMP __divhi3
  %r = sdiv i16 %a, %b
  ret i16 %r
}

; Test that i16 unsigned divide generates a call to __udivhi3

define i16 @test_udiv_i16(i16 %a, i16 %b) {
; CHECK-LABEL: test_udiv_i16:
; CHECK: JMP __udivhi3
  %r = udiv i16 %a, %b
  ret i16 %r
}

; Test that i16 signed remainder generates a call to __modhi3

define i16 @test_srem_i16(i16 %a, i16 %b) {
; CHECK-LABEL: test_srem_i16:
; CHECK: JMP __modhi3
  %r = srem i16 %a, %b
  ret i16 %r
}

; Test that i16 unsigned remainder generates a call to __umodhi3

define i16 @test_urem_i16(i16 %a, i16 %b) {
; CHECK-LABEL: test_urem_i16:
; CHECK: JMP __umodhi3
  %r = urem i16 %a, %b
  ret i16 %r
}
