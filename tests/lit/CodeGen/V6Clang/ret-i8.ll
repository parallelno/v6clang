; RUN: llc -march=v6clang < %s | FileCheck %s

; CHECK-LABEL: ret42:
; CHECK:       MVI A, 0x2a
; CHECK-NEXT:  RET
define i8 @ret42() {
  ret i8 42
}

; CHECK-LABEL: identity:
; CHECK:       RET
define i8 @identity(i8 %x) {
  ret i8 %x
}
