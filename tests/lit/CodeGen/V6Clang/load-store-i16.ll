; RUN: llc -march=v6clang < %s | FileCheck %s

@g16 = global i16 0

; CHECK-LABEL: load_global:
; CHECK:       LHLD g16
; CHECK-NEXT:  RET
define i16 @load_global() {
  %v = load i16, ptr @g16
  ret i16 %v
}

; CHECK-LABEL: store_global:
; CHECK:       SHLD g16
; CHECK-NEXT:  RET
define void @store_global(i16 %val) {
  store i16 %val, ptr @g16
  ret void
}

; O71: case 1 (addr=HL, dst=HL) picks a dead GR8 spare (here: B) and
; routes the low byte through it. Falls back to A under PUSH PSW only
; if no dead GR8 exists.
; CHECK-LABEL: load_ptr:
; CHECK:       MOV [[T:[A-Z]+]], M
; CHECK-NEXT:  INX H
; CHECK-NEXT:  MOV H, M
; CHECK-NEXT:  MOV L, [[T]]
define i16 @load_ptr(ptr %p) {
  %v = load i16, ptr %p
  ret i16 %v
}

; CHECK-LABEL: store_ptr:
; O72: addr=DE, val=HL → XCHG-wrapped; preserves both A and HL.
; CHECK:       XCHG
; CHECK-NEXT:  MOV M, E
; CHECK-NEXT:  INX H
; CHECK-NEXT:  MOV M, D
; CHECK-NEXT:  XCHG
; CHECK-NEXT:  RET
define void @store_ptr(i16 %val, ptr %p) {
  store i16 %val, ptr %p
  ret void
}
