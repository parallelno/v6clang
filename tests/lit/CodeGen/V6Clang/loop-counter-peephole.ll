; RUN: llc -march=v6clang < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@g = external global i8

; Test Pattern A: DCR A; (ORA A / CPI 0); JNZ → DCR A; JNZ
; The volatile store forces the loop to not be optimized away and
; keeps the counter in A.
;
; CHECK-LABEL: dcr_a_loop:
; CHECK:       .LBB0_1:
; CHECK:       STA g
; CHECK-NEXT:  DCR A
; CHECK-NEXT:  JNZ .LBB0_1
; CHECK-NOT:   ORA
; CHECK-NOT:   CPI
define void @dcr_a_loop(i8 %n) {
entry:
  %cmp = icmp ne i8 %n, 0
  br i1 %cmp, label %loop, label %exit

loop:
  %counter = phi i8 [ %n, %entry ], [ %dec, %loop ]
  store volatile i8 %counter, ptr @g
  %dec = add i8 %counter, -1
  %test = icmp ne i8 %dec, 0
  br i1 %test, label %loop, label %exit

exit:
  ret void
}

; Test Pattern A with JZ: DCR A; (ORA A / CPI 0); JZ → DCR A; JZ
; Inverted condition: branch to exit when zero, fall through to loop.
;
; CHECK-LABEL: dcr_a_jz:
; CHECK:       DCR A
; CHECK-NEXT:  RZ
; CHECK-NOT:   ORA
; CHECK-NOT:   CPI
define void @dcr_a_jz(i8 %n) {
entry:
  br label %loop

loop:
  %counter = phi i8 [ %n, %entry ], [ %dec, %body ]
  %dec = add i8 %counter, -1
  %test = icmp eq i8 %dec, 0
  br i1 %test, label %exit, label %body

body:
  store volatile i8 %dec, ptr @g
  br label %loop

exit:
  ret void
}

; Test INR pattern: INR A; (ORA A / CPI 0); JNZ → INR A; JNZ
;
; CHECK-LABEL: inr_a_loop:
; CHECK:       .LBB2_1:
; CHECK:       INR A
; CHECK-NEXT:  JNZ .LBB2_1
; CHECK-NOT:   ORA
; CHECK-NOT:   CPI
define void @inr_a_loop(i8 %n) {
entry:
  %cmp = icmp ne i8 %n, 0
  br i1 %cmp, label %loop, label %exit

loop:
  %counter = phi i8 [ %n, %entry ], [ %inc, %loop ]
  store volatile i8 %counter, ptr @g
  %inc = add i8 %counter, 1
  %test = icmp ne i8 %inc, 0
  br i1 %test, label %loop, label %exit

exit:
  ret void
}
