; RUN: llc -march=v6clang < %s | FileCheck %s

; GEP with i16 index on i16 element: base + idx * 2
; O71: case 1 (addr=HL, dst=HL) prefers a dead GR8 spare over A.
; CHECK-LABEL: gep_i16:
; CHECK:       XCHG
; CHECK:       DAD	H
; CHECK:       DAD	D
; CHECK:       MOV [[T:[A-Z]+]], M
; CHECK-NEXT:  INX H
; CHECK-NEXT:  MOV H, M
; CHECK-NEXT:  MOV L, [[T]]
define i16 @gep_i16(ptr %base, i16 %idx) {
  %ptr = getelementptr i16, ptr %base, i16 %idx
  %v = load i16, ptr %ptr
  ret i16 %v
}
