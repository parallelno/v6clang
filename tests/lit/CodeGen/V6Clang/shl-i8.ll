; RUN: llc -march=v6clang < %s | FileCheck %s

; Test shift left by 1 → ADD A, A
; CHECK-LABEL: shl1:
; CHECK:       ADD A
; CHECK-NEXT:  RET
define i8 @shl1(i8 %a) {
  %r = shl i8 %a, 1
  ret i8 %r
}

; Test shift left by 3 → three ADD A, A
; CHECK-LABEL: shl3:
; CHECK:       ADD A
; CHECK-NEXT:  ADD A
; CHECK-NEXT:  ADD A
; CHECK-NEXT:  RET
define i8 @shl3(i8 %a) {
  %r = shl i8 %a, 3
  ret i8 %r
}
