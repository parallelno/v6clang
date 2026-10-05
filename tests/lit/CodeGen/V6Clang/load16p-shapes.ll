; RUN: llc -march=v6clang < %s | FileCheck %s
;
; O71 — V6CLANG_LOAD16_P redesign. Spot-checks for the per-shape expander.
;
; Exhaustive shape coverage lives in tests/features/53/. This file
; pins down two specific regressions:
;   * case 1 (addr=HL, dst=HL) — must use a dead GR8 spare instead of A
;     when one is available (and never silently corrupt A).
;   * case 4 (addr=DE, dst=DE) — the bug-3 reproducer.

; Case 1 — addr=HL, dst=HL. Dead-GR8 spare preferred over A; no PUSH PSW.
; CHECK-LABEL: case1_hl_hl:
; CHECK:       MOV [[T:[A-Z]+]], M
; CHECK-NEXT:  INX H
; CHECK-NEXT:  MOV H, M
; CHECK-NEXT:  MOV L, [[T]]
; CHECK-NOT:   PUSH
define i16 @case1_hl_hl(ptr %p) {
  %v = load i16, ptr %p
  ret i16 %v
}

; Case 4 — addr=DE, dst=DE — bug-3 regression.
; With sum=HL (1st arg) and p=DE (2nd arg), the load must end with
; HL = orig HL (sum) and DE = loaded value (or with the trailing XCHG
; folded out by foldXchgDad, HL = loaded and DE = sum — DAD is
; commutative, same result). Either way the body must NOT use the
; old buggy `MOV E, M; INX H; MOV D, M; XCHG` shape (which corrupts
; both pairs); it must use a non-{D,E,H,L} spare.
; CHECK-LABEL: case4_de_de:
; CHECK:       XCHG
; CHECK-NEXT:  MOV [[T:[BC]]], M
; CHECK-NEXT:  INX H
; CHECK-NEXT:  MOV H, M
; CHECK-NEXT:  MOV L, [[T]]
; CHECK-NOT:   MOV E, M
; CHECK-NOT:   MOV D, M
define i16 @case4_de_de(i16 %sum, ptr %p) {
  %v = load i16, ptr %p
  %s = add i16 %sum, %v
  ret i16 %s
}

; Case 6 — addr=BC, dst=HL, A dead. Must use the new LDAX-based shape:
;   LDAX B; MOV L,A; INX B; LDAX B; MOV H,A
; (5B / 40cc, no PUSH, no MOV H,B; MOV L,C; staging.)
; CHECK-LABEL: case6_bc_hl_simple:
; CHECK:       LDAX B
; CHECK-NEXT:  MOV L, A
; CHECK-NEXT:  INX B
; CHECK-NEXT:  LDAX B
; CHECK-NEXT:  MOV H, A
; CHECK-NOT:   PUSH PSW
; CHECK-NOT:   MOV H, B
define i16 @case6_bc_hl_simple(i16 %x, i16 %y, ptr %p) {
  %v = load i16, ptr %p
  ret i16 %v
}

; Case 5a — addr=BC, dst=DE, HL live (holds x for the tail call), A dead.
; Must use the LDAX shape with dst halves D,E:
;   LDAX B; MOV E,A; INX B; LDAX B; MOV D,A
; HL is preserved automatically (LDAX doesn't touch HL); BC is dead
; after the load (no callee BC arg) so no DCX B.
declare void @sink2(i16, i16)
; CHECK-LABEL: case5a_bc_de:
; CHECK:       LDAX B
; CHECK-NEXT:  MOV E, A
; CHECK-NEXT:  INX B
; CHECK-NEXT:  LDAX B
; CHECK-NEXT:  MOV D, A
; CHECK-NOT:   PUSH H
; CHECK-NOT:   MOV H, B
define void @case5a_bc_de(i16 %x, i16 %y, ptr %p) {
  %v = load i16, ptr %p
  call void @sink2(i16 %x, i16 %v)
  ret void
}
