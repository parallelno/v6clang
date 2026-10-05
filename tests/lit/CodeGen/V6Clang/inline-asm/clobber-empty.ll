; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

; Phase 4: empty clobber list ("NOP" with no inputs/outputs/clobbers) must
; produce zero spills around the asm.

; CHECK-LABEL: empty_clobber:
; CHECK-NOT:   PUSH
; CHECK-NOT:   POP
; CHECK:       ;APP
; CHECK:       NOP
; CHECK:       ;NO_APP
; CHECK:       RET
define i8 @empty_clobber(i8 %x, i8 %y) {
  call void asm sideeffect "NOP", ""()
  %r = add i8 %y, 1
  ret i8 %r
}
