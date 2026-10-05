; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

; Phase 4: verify inline-asm clobber lists are honored — no over-spill.

; Style A: inline body, only A clobbered. y (i8 in B) and p (i16 in DE) must
; survive the asm without PUSH/POP of B, BC, D, or DE.
; CHECK-LABEL: style_a_i8:
; CHECK-NOT:   PUSH    B
; CHECK-NOT:   PUSH    D
; CHECK:       ;APP
; CHECK:       MVI     A, 0xed
; CHECK:       OUT     0x10
; CHECK:       ;NO_APP
; CHECK-NOT:   POP     B
; CHECK-NOT:   POP     D
; CHECK:       MOV     A, B
; CHECK:       RET
define i8 @style_a_i8(i8 %x, i8 %y) {
  call void asm sideeffect "MVI A,0xED\0AOUT 0x10", "~{a}"()
  %r = add i8 %y, 1
  ret i8 %r
}

; Style A with i16 arg in DE — must stay in DE across the asm.
; CHECK-LABEL: style_a_i16:
; CHECK-NOT:   PUSH    D
; CHECK:       ;APP
; CHECK:       OUT     0x20
; CHECK:       ;NO_APP
; CHECK-NOT:   POP     D
; CHECK:       RET
define i16 @style_a_i16(i16 %x, i16 %p) {
  call void asm sideeffect "OUT 0x20", "~{a}"()
  ret i16 %p
}
