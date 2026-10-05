; RUN: llc -march=v6clang -O2 < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

define i8 @branch_ge_zero(i16 %x) {
; CHECK-LABEL: branch_ge_zero:
; CHECK:       XRA A
; CHECK-NEXT:  ADD H
; CHECK-NEXT:  J{{P|M}}
; CHECK-NOT:   MVI A, 0xff
entry:
  %cmp = icmp sge i16 %x, 0
  br i1 %cmp, label %nonneg, label %neg

nonneg:
  ret i8 1

neg:
  ret i8 0
}

define i8 @branch_lt_zero(i16 %x) {
; CHECK-LABEL: branch_lt_zero:
; CHECK:       XRA A
; CHECK-NEXT:  ADD H
; CHECK-NEXT:  J{{P|M}}
; CHECK-NOT:   MVI A, 0xff
entry:
  %cmp = icmp slt i16 %x, 0
  br i1 %cmp, label %neg, label %nonneg

neg:
  ret i8 1

nonneg:
  ret i8 0
}

define i8 @select_ge_zero(i16 %x, i8 %t, i8 %f) {
; CHECK-LABEL: select_ge_zero:
; CHECK:       XRA A
; CHECK-NEXT:  ADD H
; CHECK-NEXT:  J{{P|M}}
; CHECK-NOT:   MVI A, 0xff
entry:
  %cmp = icmp sge i16 %x, 0
  %sel = select i1 %cmp, i8 %t, i8 %f
  ret i8 %sel
}

define i8 @gt_zero_falls_back(i16 %x) {
; CHECK-LABEL: gt_zero_falls_back:
; CHECK-NOT:   ADD H
; CHECK:       SUB L
; CHECK:       SBB H
entry:
  %cmp = icmp sgt i16 %x, 0
  br i1 %cmp, label %pos, label %nonpos

pos:
  ret i8 1

nonpos:
  ret i8 0
}