; RUN: llc -march=v6clang -v6clang-disable-peephole -v6clang-disable-redundant-flag-elim < %s | FileCheck %s

; O75 Phase B made this test trivial:  ISD::ADD i8 with -1 is now Custom-
; lowered to V6ClangISD::DECF (multi-result, value+flags), and LowerBR_CC's
; short-circuit consumes those flags directly — no separate CMP is built
; at SDAG.  Hence even with both the post-RA peephole (O18) and
; redundant-flag-elim (O17) disabled, no `ORA A` ever appears between
; the DCR and the JNZ; the FLAGS chain is correct by construction.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@g_out = external global i8

; CHECK-LABEL: test_decr_loop:
; CHECK:       DCR A
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
