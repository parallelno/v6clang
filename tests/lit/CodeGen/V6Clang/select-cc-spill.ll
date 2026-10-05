; RUN: llc -march=v6clang < %s | FileCheck %s

; Regression test for SELECT_CC with spilled comparison operands.
; The old RELOAD8 expansion for H/L destinations used A as intermediary,
; silently clobbering a live CMP operand. This caused CMP to compare
; a value against itself instead of the correct operand.

; Simple select: should compile correctly with a real CMP (not CMP A).
; CHECK-LABEL: select_simple:
; CHECK:       CMP
; CHECK-NOT:   CMP	A
; CHECK:       RET
define i8 @select_simple(i8 %a, i8 %b) {
entry:
  %cmp = icmp ult i8 %a, %b
  %sel = select i1 %cmp, i8 %a, i8 %b
  ret i8 %sel
}

; Bubble-sort swap: compare-and-select two loaded values via pointer.
; This pattern originally triggered the bug due to register pressure
; from HL-based address computation clobbering reload intermediaries.
; CHECK-LABEL: bubble_swap:
; CHECK:       CMP
; CHECK-NOT:   CMP	A
; CHECK:       RET
define void @bubble_swap(ptr %arr) {
entry:
  %v0 = load i8, ptr %arr
  %p1 = getelementptr i8, ptr %arr, i16 1
  %v1 = load i8, ptr %p1
  %cmp = icmp ugt i8 %v0, %v1
  %lo = select i1 %cmp, i8 %v1, i8 %v0
  %hi = select i1 %cmp, i8 %v0, i8 %v1
  store i8 %lo, ptr %arr
  store i8 %hi, ptr %p1
  ret void
}
