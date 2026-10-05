; RUN: llc -march=v6clang -O2 < %s | FileCheck %s

; Test that 16-bit NE comparison uses CMP-based sequence, not XOR.
define void @ne_branch(i16 %a, i16 %b) {
; CHECK-LABEL: ne_branch:
; CHECK:       CMP
; CHECK:       {{J|R}}{{N?}}Z
; CHECK:       CMP
; CHECK:       {{J|R}}{{N?}}Z
; CHECK-NOT:   XRA
entry:
  %cmp = icmp ne i16 %a, %b
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

; Test that 16-bit EQ comparison uses CMP + JNZ/JZ pattern.
define void @eq_branch(i16 %a, i16 %b) {
; CHECK-LABEL: eq_branch:
; CHECK:       CMP
; Depending on block layout, either JNZ+JZ or JZ+JNZ may appear.
; What matters is: no XRA, and CMP is used.
; CHECK-NOT:   XRA
entry:
  %cmp = icmp eq i16 %a, %b
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

; Test that LT comparison still uses SUB/SBB (not CMP split).
define void @lt_branch(i16 %a, i16 %b) {
; CHECK-LABEL: lt_branch:
; CHECK:       SUB
; CHECK:       SBB
entry:
  %cmp = icmp ult i16 %a, %b
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

declare void @use()
