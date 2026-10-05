; RUN: llc -march=v6clang < %s | FileCheck %s

; Test V6ClangTypeNarrowing: narrow zext i8->i16 when only i8 result is used.

; A zext from i8 to i16 followed by trunc back to i8 should be simplified.
; The type narrowing pass removes unnecessary widening.

; CHECK-LABEL: test_narrow_identity:
; CHECK:       RET
define i8 @test_narrow_identity(i8 %a) {
  %wide = zext i8 %a to i16
  %narrow = trunc i16 %wide to i8
  ret i8 %narrow
}

; Test with disabled pass.
; RUN: llc -march=v6clang -v6clang-disable-type-narrowing < %s | FileCheck %s --check-prefix=OFF
; OFF-LABEL: test_narrow_identity:
; OFF:       RET

; Narrowing should apply to zext + compare with small constant.
; The compare gets narrowed to an 8-bit operation (CMP reg or CPI imm).
; CHECK-LABEL: test_narrow_cmp:
; CHECK-NOT:   LHLD
; CHECK:       RET
define i8 @test_narrow_cmp(i8 %a) {
  %wide = zext i8 %a to i16
  %cmp = icmp ult i16 %wide, 10
  br i1 %cmp, label %then, label %else
then:
  ret i8 1
else:
  ret i8 0
}
