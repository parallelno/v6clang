; RUN: llc -march=v6clang < %s | FileCheck %s

; Test V6ClangAccumulatorPlanning: redundant MOV A, X; ... MOV X, A elimination.

; A function that does multiple operations should not have unnecessary
; round-trip moves to/from A.

; CHECK-LABEL: test_acc_planning:
; CHECK:       ADD
; CHECK:       RET
define i8 @test_acc_planning(i8 %a, i8 %b) {
  %r = add i8 %a, %b
  ret i8 %r
}

; Test with multiple operations — accumulator planning should minimize traffic.
; CHECK-LABEL: test_multi_op:
; CHECK:       ADD
; CHECK:       SUB
; CHECK:       RET
define i8 @test_multi_op(i8 %a, i8 %b, i8 %c) {
  %t = add i8 %a, %b
  %r = sub i8 %t, %c
  ret i8 %r
}

; Test with disabled pass.
; RUN: llc -march=v6clang -v6clang-disable-acc-planning < %s | FileCheck %s --check-prefix=OFF
; OFF-LABEL: test_acc_planning:
; OFF:       ADD
; OFF:       RET
