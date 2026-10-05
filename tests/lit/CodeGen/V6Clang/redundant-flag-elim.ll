; RUN: llc -march=v6clang -v6clang-disable-peephole < %s | FileCheck %s

; Test V6ClangRedundantFlagElim: ORA A should be eliminated when the preceding
; ALU instruction already set the Z flag based on A's value.
; Peephole is disabled so that ZeroTestOpt creates ORA A from CPI 0,
; and O17 (redundant-flag-elim) is the one that eliminates it.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@g_out = external global i8

; --- Test 1: DCR A + ORA A → ORA A eliminated ---
; DCR sets Z flag, so ORA A after it is redundant.
; CHECK-LABEL: test_decr_loop:
; CHECK:       DCR A
; CHECK-NOT:   ORA A
; CHECK-NEXT:  JNZ
define void @test_decr_loop(i8 %n) {
entry:
  %cmp = icmp eq i8 %n, 0
  br i1 %cmp, label %exit, label %loop

loop:
  %i = phi i8 [ %n, %entry ], [ %dec, %loop ]
  store volatile i8 %i, ptr @g_out
  %dec = add i8 %i, -1
  %done = icmp eq i8 %dec, 0
  br i1 %done, label %exit, label %loop

exit:
  ret void
}

; --- Test 2: SUB sets Z, no redundant ORA A needed ---
; CHECK-LABEL: test_sub_branch:
; CHECK:       SUB
; CHECK-NOT:   ORA A
; CHECK:       JZ
define i8 @test_sub_branch(i8 %a, i8 %b) {
entry:
  %diff = sub i8 %a, %b
  %cmp = icmp eq i8 %diff, 0
  br i1 %cmp, label %eq, label %ne

eq:
  ret i8 1

ne:
  ret i8 0
}
