; RUN: llc -march=v6clang < %s | FileCheck %s
; RUN: llc -march=v6clang -v6clang-disable-branch-opt < %s | FileCheck %s --check-prefix=DISABLED

; Test V6ClangBranchOpt: branch threading through JMP-only blocks.
; A conditional branch targeting a block whose only instruction is JMP
; should be redirected directly to the JMP's target.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare i16 @bar(i16)

; Two conditional branches to the same tail-call block.
; The first Jcc (JNZ) should be threaded to bar directly.
; CHECK-LABEL: test_thread_tailcall:
; CHECK:       JNZ bar
; CHECK-NOT:   JNZ .LBB
;
; DISABLED-LABEL: test_thread_tailcall:
; DISABLED:       JNZ .LBB
define i16 @test_thread_tailcall(i16 %x, i16 %y) {
entry:
  %cmp1 = icmp ne i16 %x, 0
  br i1 %cmp1, label %tailcall, label %check_y

check_y:
  %cmp2 = icmp ne i16 %y, 0
  br i1 %cmp2, label %tailcall, label %ret0

tailcall:
  %r = tail call i16 @bar(i16 %x)
  ret i16 %r

ret0:
  ret i16 0
}

; Negative test: block with more than just JMP is NOT threaded.
; CHECK-LABEL: test_no_thread:
; CHECK:       RET
define i16 @test_no_thread(i16 %x) {
entry:
  %cmp = icmp eq i16 %x, 0
  br i1 %cmp, label %then, label %else

then:
  ret i16 0

else:
  %r = add i16 %x, 1
  ret i16 %r
}
