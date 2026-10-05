; RUN: llc -march=v6clang < %s | FileCheck %s

; Return i8 in A.
; CHECK-LABEL: ret_i8:
; CHECK:       MVI A, 0x2a
; CHECK-NEXT:  RET
define i8 @ret_i8() {
  ret i8 42
}

; Return i16 in HL.
; CHECK-LABEL: ret_i16:
; CHECK:       LXI H, 0x1234
; CHECK:       RET
define i16 @ret_i16() {
  ret i16 4660
}
