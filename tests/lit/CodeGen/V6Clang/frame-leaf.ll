; RUN: llc -march=v6clang < %s | FileCheck %s

; Leaf function with no locals should have no prologue/epilogue.
; CHECK-LABEL: leaf_noop:
; CHECK-NOT:   LXI
; CHECK-NOT:   DAD
; CHECK-NOT:   SPHL
; CHECK:       RET
define void @leaf_noop() {
  ret void
}

; Leaf function returning its argument — no prologue needed.
; CHECK-LABEL: leaf_identity:
; CHECK-NOT:   SPHL
; CHECK:       RET
define i8 @leaf_identity(i8 %x) {
  ret i8 %x
}

; Leaf function with trivial computation — no locals, no stack frame.
; CHECK-LABEL: leaf_add:
; CHECK-NOT:   SPHL
; CHECK:       ADD B
; CHECK-NEXT:  RET
define i8 @leaf_add(i8 %a, i8 %b) {
  %r = add i8 %a, %b
  ret i8 %r
}
