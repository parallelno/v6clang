; RUN: llc -march=v6clang -O2 < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; The V6CLANG backend has no jump-table (br_jt) or indirect-branch (brind)
; selection support. TargetLowering marks both non-legal so areJTsAllowed()
; returns false and switches lower to comparison-and-branch chains instead
; of a jump table. Regression test for "Cannot select: br_jt".

define i16 @sw(i16 %a) {
; CHECK-LABEL: sw:
; CHECK-NOT:   br_jt
; CHECK-NOT:   .LJTI
; CHECK-NOT:   PCHL
entry:
  switch i16 %a, label %def [
    i16 0, label %c0
    i16 1, label %c1
    i16 2, label %c2
    i16 3, label %c3
  ]

c0:
  ret i16 10
c1:
  ret i16 11
c2:
  ret i16 12
c3:
  ret i16 13
def:
  ret i16 99
}
