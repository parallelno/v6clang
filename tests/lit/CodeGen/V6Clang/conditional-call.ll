; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare void @notify()
declare i8 @produce()

@observed = external global i8

; Test 1: equality test -> CZ
; if (x == 0) notify(); return observed + 1;
define i8 @cb_eq(i8 %x) {
; CHECK-LABEL: cb_eq:
; CHECK:       ORA	A
; CHECK-NEXT:  CZ	notify
; CHECK-NOT:   CALL	notify
entry:
  %cmp = icmp eq i8 %x, 0
  br i1 %cmp, label %call, label %tail

call:
  call void @notify()
  br label %tail

tail:
  %v = load i8, ptr @observed
  %r = add i8 %v, 1
  ret i8 %r
}

; Test 2: inequality test -> CNZ
define i8 @cb_ne(i8 %x) {
; CHECK-LABEL: cb_ne:
; CHECK:       ORA	A
; CHECK-NEXT:  CNZ	notify
; CHECK-NOT:   CALL	notify
entry:
  %cmp = icmp ne i8 %x, 0
  br i1 %cmp, label %call, label %tail

call:
  call void @notify()
  br label %tail

tail:
  %v = load i8, ptr @observed
  %r = add i8 %v, 1
  ret i8 %r
}

; Test 3: unsigned LT -> CNC (subtract-and-test lowering)
define i8 @cb_ult(i16 %x) {
; CHECK-LABEL: cb_ult:
; CHECK:       CNC	notify
; CHECK-NOT:   CALL	notify
entry:
  %cmp = icmp ult i16 %x, 100
  br i1 %cmp, label %call, label %tail

call:
  call void @notify()
  br label %tail

tail:
  %v = load i8, ptr @observed
  %r = add i8 %v, 1
  ret i8 %r
}

; Test 4: unsigned GE -> CC
define i8 @cb_uge(i16 %x) {
; CHECK-LABEL: cb_uge:
; CHECK:       CC	notify
; CHECK-NOT:   CALL	notify
entry:
  %cmp = icmp uge i16 %x, 100
  br i1 %cmp, label %call, label %tail

call:
  call void @notify()
  br label %tail

tail:
  %v = load i8, ptr @observed
  %r = add i8 %v, 1
  ret i8 %r
}

; Test 5: signed LT 0 -> CM (sign-test lowering)
define i8 @cb_slt(i16 %x) {
; CHECK-LABEL: cb_slt:
; CHECK:       CM	notify
; CHECK-NOT:   CALL	notify
entry:
  %cmp = icmp slt i16 %x, 0
  br i1 %cmp, label %call, label %tail

call:
  call void @notify()
  br label %tail

tail:
  %v = load i8, ptr @observed
  %r = add i8 %v, 1
  ret i8 %r
}

; Test 6: signed GE 0 -> CP
define i8 @cb_sge(i16 %x) {
; CHECK-LABEL: cb_sge:
; CHECK:       CP	notify
; CHECK-NOT:   CALL	notify
entry:
  %cmp = icmp sge i16 %x, 0
  br i1 %cmp, label %call, label %tail

call:
  call void @notify()
  br label %tail

tail:
  %v = load i8, ptr @observed
  %r = add i8 %v, 1
  ret i8 %r
}

; Test 7 (negative): return value of call is consumed -> the call block
; contains a result COPY in addition to the CALL, so the fold must not
; fire and a regular CALL is emitted.
define i8 @cb_value_used(i8 %x) {
; CHECK-LABEL: cb_value_used:
; CHECK:       CALL	produce
; CHECK-NOT:   C{{[NPMC]?Z?}}	produce
entry:
  %cmp = icmp ne i8 %x, 0
  br i1 %cmp, label %call, label %tail

call:
  %p = call i8 @produce()
  br label %tail

tail:
  %v = phi i8 [ %p, %call ], [ 7, %entry ]
  %m = load i8, ptr @observed
  %r = add i8 %v, %m
  ret i8 %r
}
