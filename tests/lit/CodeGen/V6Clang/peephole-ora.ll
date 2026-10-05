; RUN: llc -march=v6clang < %s | FileCheck %s

; Test V6ClangZeroTestOpt: CPI 0 should be replaced with ORA A.
; CPI 0 costs 8cc, ORA A costs 4cc, both set Z/S flags the same way.

; CHECK-LABEL: test_zero:
; CHECK-NOT:   CPI 0
; CHECK:       ORA A
define i8 @test_zero(i8 %a) {
entry:
  %c = icmp eq i8 %a, 0
  br i1 %c, label %then, label %else
then:
  ret i8 1
else:
  ret i8 0
}

; Non-zero immediate should still use CPI.
; CHECK-LABEL: test_nonzero:
; CHECK:       CPI
; CHECK-NOT:   ORA A
define i8 @test_nonzero(i8 %a) {
entry:
  %c = icmp eq i8 %a, 5
  br i1 %c, label %then, label %else
then:
  ret i8 1
else:
  ret i8 0
}

; Unsigned less-than zero comparison: ORA A for the zero test.
; CHECK-LABEL: test_zero_ne:
; CHECK-NOT:   CPI 0
; CHECK:       ORA A
define i8 @test_zero_ne(i8 %a) {
entry:
  %c = icmp ne i8 %a, 0
  br i1 %c, label %then, label %else
then:
  ret i8 1
else:
  ret i8 0
}
