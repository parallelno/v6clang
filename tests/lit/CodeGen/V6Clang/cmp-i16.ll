; RUN: llc -march=v6clang < %s | FileCheck %s

; Comparison expansion uses fused compare+branch pseudo.
; EQ/NE use CMP-based non-destructive sequence with MBB splitting.

; CHECK-LABEL: cmp_ne_i16:
; CHECK:       CMP
; CHECK:       JNZ
; CHECK-NOT:   XRA
; CHECK:       CMP
; CHECK:       JNZ
define i8 @cmp_ne_i16(i16 %a, i16 %b) {
  %c = icmp ne i16 %a, %b
  br i1 %c, label %then, label %else
then:
  ret i8 1
else:
  ret i8 0
}

; Unsigned less-than uses SUB/SBB + JC/JNC (LLVM may invert branch)
; CHECK-LABEL: cmp_ult_i16:
; CHECK:       SUB
; CHECK:       SBB
; CHECK:       J{{N?}}C
define i8 @cmp_ult_i16(i16 %a, i16 %b) {
  %c = icmp ult i16 %a, %b
  br i1 %c, label %then, label %else
then:
  ret i8 1
else:
  ret i8 0
}

; Signed less-than uses SUB/SBB + JM/JP (LLVM may invert branch)
; CHECK-LABEL: cmp_slt_i16:
; CHECK:       SUB
; CHECK:       SBB
; CHECK:       J{{[MP]}}
define i8 @cmp_slt_i16(i16 %a, i16 %b) {
  %c = icmp slt i16 %a, %b
  br i1 %c, label %then, label %else
then:
  ret i8 1
else:
  ret i8 0
}
