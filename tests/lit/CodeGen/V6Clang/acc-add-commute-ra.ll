; RUN: llc -march=v6clang -O3 < %s | FileCheck %s

; The third masked load is naturally live in A when the final add is selected.
; ADDr must be commutable so RA can keep that fresh A value as the tied lhs/result
; and move the running sum to a non-A GR8 register.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; CHECK-LABEL: neighbours3:
; CHECK:       ANI 1
; CHECK-NEXT:  MOV C, A
; CHECK:       ADD C
; CHECK-NEXT:  MOV C, A
; CHECK:       ANI 1
; CHECK-NEXT:  ADD C
; CHECK-NOT:   ADD A
; CHECK:       RET
define i16 @neighbours3(ptr %p) {
entry:
  %p0 = getelementptr inbounds i8, ptr %p, i16 -79
  %v0 = load i8, ptr %p0, align 1
  %b0 = and i8 %v0, 1
  %p1 = getelementptr inbounds i8, ptr %p, i16 -78
  %v1 = load i8, ptr %p1, align 1
  %b1 = and i8 %v1, 1
  %s1 = add nuw nsw i8 %b1, %b0
  %p2 = getelementptr inbounds i8, ptr %p, i16 -77
  %v2 = load i8, ptr %p2, align 1
  %b2 = and i8 %v2, 1
  %s2 = add nuw nsw i8 %s1, %b2
  %ret = zext nneg i8 %s2 to i16
  ret i16 %ret
}