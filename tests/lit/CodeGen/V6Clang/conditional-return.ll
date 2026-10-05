; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare i16 @bar(i16)

; Test 1: JZ to RET-only block → RZ
; Pattern: if (x) return bar(x); return 0;
; The zero-test branch to the return block should become RZ.
define i16 @cond_ret_z(i16 %x) {
; CHECK-LABEL: cond_ret_z:
; CHECK:       ORA	L
; CHECK-NEXT:  RZ
; CHECK-NOT:   JZ
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

; Test 2: Negative — target block has LXI+RET (not RET-only), should NOT fold.
; The retval block returns a non-trivial constant directly, producing LXI+RET.
define i16 @no_fold_ret_val(i16 %x) {
; CHECK-LABEL: no_fold_ret_val:
; CHECK-NOT:   RZ
; CHECK-NOT:   RNZ
; CHECK:       RET
entry:
  %cmp = icmp eq i16 %x, 0
  br i1 %cmp, label %retval, label %then

then:
  %r = call i16 @bar(i16 %x)
  ret i16 %r

retval:
  ret i16 42
}

; Test 3: Multiple Jcc→RET in same function — both should fold.
; Pattern: two early-return guards before the main call.
define i16 @multi_cond_ret(i16 %x, i16 %y) {
; CHECK-LABEL: multi_cond_ret:
; CHECK:       RZ
; CHECK:       JMP	bar
entry:
  %cmp1 = icmp eq i16 %x, 0
  br i1 %cmp1, label %ret, label %check2

check2:
  %cmp2 = icmp eq i16 %y, 0
  br i1 %cmp2, label %ret, label %work

work:
  %r = call i16 @bar(i16 %x)
  br label %ret

ret:
  %rv = phi i16 [ 0, %entry ], [ 0, %check2 ], [ %r, %work ]
  ret i16 %rv
}
