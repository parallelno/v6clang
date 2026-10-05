; RUN: llc -march=v6clang -O2 < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; O37: Constant sinking past conditional branches.
; When both paths after a zero-test need HL=0, the compiler used to
; hoist LXI HL,0 before the branch, forcing x to be saved to DE.
; The constant sinking pass defers the LXI to each successor,
; letting the zero-test operate on HL directly.

; Positive test: constant is sunk past the branch, eliminating MOV D,H / MOV E,L.
define i16 @test_cond_zero_return_zero(i16 %x) {
; CHECK-LABEL: test_cond_zero_return_zero:
; CHECK-NOT:   MOV D, H
; CHECK-NOT:   MOV E, L
; CHECK:       MOV A, H
; CHECK-NEXT:  ORA L
; CHECK-NEXT:  JZ bar
; CHECK:       LXI H, 0
; CHECK-NEXT:  RET
entry:
  %cmp = icmp eq i16 %x, 0
  br i1 %cmp, label %then, label %else

then:
  %r = tail call i16 @bar(i16 0)
  br label %join

else:
  br label %join

join:
  %ret = phi i16 [ %r, %then ], [ 0, %else ]
  ret i16 %ret
}

; Negative test: constant used locally before branch ??? should NOT be sunk.
define i16 @test_const_used_locally(i16 %x) {
; CHECK-LABEL: test_const_used_locally:
; CHECK:       LXI H, 0
; CHECK:       CALL bar
entry:
  %r = call i16 @bar(i16 0)
  %cmp = icmp eq i16 %x, 0
  br i1 %cmp, label %then, label %else

then:
  ret i16 %r

else:
  ret i16 0
}

; Test: only one path uses zero ??? should still sink.
define i16 @test_one_path_zero(i16 %x) {
; CHECK-LABEL: test_one_path_zero:
; CHECK:       MOV A, H
; CHECK-NEXT:  ORA L
; CHECK-NEXT:  JZ bar
; CHECK-NOT:   LXI H, 0
; CHECK:       RET
entry:
  %cmp = icmp eq i16 %x, 0
  br i1 %cmp, label %then, label %join

then:
  %r = tail call i16 @bar(i16 0)
  br label %join

join:
  %ret = phi i16 [ %r, %then ], [ %x, %entry ]
  ret i16 %ret
}

; Disabled test: pass disabled via CLI flag.
; RUN: llc -march=v6clang -O2 -v6clang-disable-constant-sinking < %s | FileCheck %s --check-prefix=DISABLED

; DISABLED-LABEL: test_cond_zero_return_zero:
; DISABLED:       LXI H, 0
; DISABLED:       JZ bar

declare i16 @bar(i16)
