; RUN: llc -march=v6clang < %s | FileCheck %s

; CHECK-LABEL: const_i16:
; CHECK:       LXI H, 0x1234
; CHECK-NEXT:  RET
define i16 @const_i16() {
  ret i16 4660
}

; CHECK-LABEL: const_zero_i16:
; CHECK:       LXI H, 0
; CHECK-NEXT:  RET
define i16 @const_zero_i16() {
  ret i16 0
}
