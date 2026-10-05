; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare i16 @bar(i16)
declare i16 @baz(i16)

; Test 1: Pattern A — conditional tail call (if (x) return bar(x); return 0)
; The CALL in the conditional block should become JMP (cross-block tail call).
define i16 @cond_tail_a(i16 %x) {
; CHECK-LABEL: cond_tail_a:
; CHECK-NOT:   CALL{{[[:space:]]}}bar
; CHECK:       JMP	bar
entry:
  %cmp = icmp eq i16 %x, 0
  br i1 %cmp, label %ret, label %then

then:
  %r = call i16 @bar(i16 %x)
  br label %ret

ret:
  %rv = phi i16 [ %r, %then ], [ 0, %entry ]
  ret i16 %rv
}

; Test 2: Pattern B — fallthrough tail call (if (x) return 0; return bar(x))
; The CALL in the fallthrough block should become JMP, then branch threading
; redirects the conditional branch directly to bar.
define i16 @cond_tail_b(i16 %x) {
; CHECK-LABEL: cond_tail_b:
; CHECK-NOT:   CALL{{[[:space:]]}}bar
; CHECK:       JZ	bar
entry:
  %cmp = icmp eq i16 %x, 0
  br i1 %cmp, label %call, label %ret

call:
  %r = call i16 @bar(i16 0)
  br label %ret

ret:
  %rv = phi i16 [ %r, %call ], [ 0, %entry ]
  ret i16 %rv
}

; Test 3: Negative — work after call, NOT a tail call.
; CALL must remain because there's an add after it.
define i16 @not_cond_tail(i16 %x) {
; CHECK-LABEL: not_cond_tail:
; CHECK:       CALL	bar
; CHECK:       RET
entry:
  %cmp = icmp eq i16 %x, 0
  br i1 %cmp, label %ret, label %then

then:
  %r = call i16 @bar(i16 %x)
  %r2 = add i16 %r, 1
  br label %ret

ret:
  %rv = phi i16 [ %r2, %then ], [ 0, %entry ]
  ret i16 %rv
}
