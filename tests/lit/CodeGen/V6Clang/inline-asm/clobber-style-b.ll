; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

; Phase 4 Style B: inline-asm performs an extern CALL with only A + memory
; clobbered. BC and DE must NOT be saved/restored across the asm — the
; clobber list is authoritative.

; CHECK-LABEL: style_b_i8:
; CHECK-NOT:   PUSH    B
; CHECK-NOT:   PUSH    D
; CHECK:       ;APP
; CHECK:       CALL    helper
; CHECK:       ;NO_APP
; CHECK-NOT:   POP     B
; CHECK-NOT:   POP     D
; CHECK:       MOV     A, B
; CHECK:       RET
define i8 @style_b_i8(i8 %x, i8 %y) {
  call void asm sideeffect "CALL helper", "~{a},~{memory}"()
  %r = add i8 %y, 1
  ret i8 %r
}

; Style B with i16 arg in DE — must survive the extern CALL.
; CHECK-LABEL: style_b_i16:
; CHECK-NOT:   PUSH    D
; CHECK:       ;APP
; CHECK:       CALL    helper
; CHECK:       ;NO_APP
; CHECK-NOT:   POP     D
; CHECK:       RET
define i16 @style_b_i16(i16 %x, i16 %p) {
  call void asm sideeffect "CALL helper", "~{a},~{memory}"()
  ret i16 %p
}
