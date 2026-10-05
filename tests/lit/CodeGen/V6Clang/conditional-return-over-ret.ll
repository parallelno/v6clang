; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 -v6clang-disable-branch-opt < %s | FileCheck %s --check-prefix=DISABLED

; Test V6ClangBranchOpt: Jcc-over-RET ??? inverted Rcc (O35).
; When a conditional branch jumps over a fallthrough RET to the layout
; successor, replace Jcc+RET with the inverted conditional return.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare i16 @bar(i16)

; Test 1: Jcc jumps over multi-instruction block to a non-JMP-only tail-call.
; Pattern: if (x == 0) return bar(y); return 0;
; The target block has XCHG+JMP (setup argument from DE to HL), so
; branch threading cannot reduce it.
; NOTE: O37 (constant sinking) moves LXI HL,0 past the branch, so the
; Jcc-over-RET ??? Rcc (O35) pattern no longer fires. Instead we get a
; direct zero-test on HL with LXI deferred to the NZ fallthrough path.
;
; CHECK-LABEL: test_jcc_over_ret:
; CHECK:       MOV A, H
; CHECK-NEXT:  ORA L
; CHECK-NEXT:  JZ
; CHECK:       LXI H, 0
; CHECK-NEXT:  RET
; CHECK:       XCHG
; CHECK-NEXT:  JMP	bar
;
; DISABLED-LABEL: test_jcc_over_ret:
; DISABLED:       JZ
; DISABLED:       RET
define i16 @test_jcc_over_ret(i16 %x, i16 %y) {
entry:
  %cmp = icmp eq i16 %x, 0
  br i1 %cmp, label %then, label %ret

then:
  %r = tail call i16 @bar(i16 %y)
  br label %ret

ret:
  %rv = phi i16 [ %r, %then ], [ 0, %entry ]
  ret i16 %rv
}

; Test 2: JMP-only target ??? O35 defers to threading (no RNZ from O35).
; Pattern: if (x == 0) return bar(0); return 0;
; Target block is just JMP bar ??? threading handles it better.
; Result: JZ bar (threaded) + RET.
define i16 @test_defer_to_threading(i16 %x) {
; CHECK-LABEL: test_defer_to_threading:
; CHECK:       JZ	bar
; CHECK:       RET
entry:
  %cmp = icmp eq i16 %x, 0
  br i1 %cmp, label %then, label %ret

then:
  %r = tail call i16 @bar(i16 0)
  br label %ret

ret:
  %rv = phi i16 [ %r, %then ], [ 0, %entry ]
  ret i16 %rv
}
