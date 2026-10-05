; RUN: llc -march=v6clang < %s | FileCheck %s

; i32 constant: returns low in HL, high in DE
; CHECK-LABEL: const_i32:
; CHECK:       LXI H, 0x5678
; CHECK-NEXT:  LXI D, 0x1234
; CHECK-NEXT:  RET
define i32 @const_i32() {
  ret i32 305419896
}

; i32 add: high-half add can preserve HL via XCHG; DAD B; XCHG.
; CHECK-LABEL: add_i32:
; CHECK:       DAD B
; CHECK:       XCHG
; CHECK-NEXT:  DAD B
; CHECK-NEXT:  XCHG
; CHECK:       RET
define i32 @add_i32(i32 %a, i32 %b) {
  %r = add i32 %a, %b
  ret i32 %r
}
