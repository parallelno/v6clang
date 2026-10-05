; RUN: llc -march=v6clang < %s | FileCheck %s

; Test O41: Pre-RA INX/DCX pseudos for small-constant i16 arithmetic.
; Constants ??1..??3 should use INX/DCX instead of LXI+ADD16/DAD.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; add i16 %x, 1 ??? INX (general context, not pointer).
; CHECK-LABEL: add1:
; CHECK:       INX H
; CHECK-NOT:   LXI
; CHECK-NOT:   ADD
; CHECK:       RET
define i16 @add1(i16 %x) {
  %r = add i16 %x, 1
  ret i16 %r
}

; add i16 %x, 3 ??? 3??INX.
; CHECK-LABEL: add3:
; CHECK:       INX H
; CHECK-NEXT:  INX H
; CHECK-NEXT:  INX H
; CHECK-NOT:   LXI
; CHECK:       RET
define i16 @add3(i16 %x) {
  %r = add i16 %x, 3
  ret i16 %r
}

; sub i16 %x, 1 ??? DCX.
; CHECK-LABEL: sub1:
; CHECK:       DCX H
; CHECK-NOT:   LXI
; CHECK-NOT:   SUB
; CHECK:       RET
define i16 @sub1(i16 %x) {
  %r = sub i16 %x, 1
  ret i16 %r
}

; sub i16 %x, 2 ??? 2??DCX.
; CHECK-LABEL: sub2:
; CHECK:       DCX H
; CHECK-NEXT:  DCX H
; CHECK-NOT:   LXI
; CHECK:       RET
define i16 @sub2(i16 %x) {
  %r = sub i16 %x, 2
  ret i16 %r
}

; GEP ptr, 1 (pointer context) ??? INX.
; CHECK-LABEL: gep1:
; CHECK:       INX H
; CHECK-NOT:   DAD
; CHECK:       MOV A, M
; CHECK:       RET
define i8 @gep1(ptr %p) {
  %q = getelementptr i8, ptr %p, i16 1
  %v = load i8, ptr %q
  ret i8 %v
}

; add i16 %x, 4 ??? NOT INX (should fall through to ADD16 or DAD).
; CHECK-LABEL: add4:
; CHECK-NOT:   INX
; CHECK:       RET
define i16 @add4(i16 %x) {
  %r = add i16 %x, 4
  ret i16 %r
}

; add i16 %x, -1 (i.e. 0xFFFF) ??? DCX.
; CHECK-LABEL: add_neg1:
; CHECK:       DCX H
; CHECK-NOT:   LXI
; CHECK:       RET
define i16 @add_neg1(i16 %x) {
  %r = add i16 %x, -1
  ret i16 %r
}

@buf = global [100 x i8] zeroinitializer

; Loop store with pointer increment ??? INX inside loop, no LXI for constant.
; CHECK-LABEL: fill_loop:
; CHECK-NOT:   LXI{{.*}}1
; CHECK:       .LBB{{[0-9]+}}_{{[0-9]+}}:
; CHECK:       INX
define void @fill_loop(i8 %val) {
entry:
  br label %loop

loop:
  %iv = phi i16 [ 0, %entry ], [ %iv.next, %loop ]
  %ptr = getelementptr i8, ptr @buf, i16 %iv
  store i8 %val, ptr %ptr
  %iv.next = add i16 %iv, 1
  %cmp = icmp eq i16 %iv.next, 100
  br i1 %cmp, label %exit, label %loop

exit:
  ret void
}
