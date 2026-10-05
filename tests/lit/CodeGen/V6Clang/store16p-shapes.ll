; RUN: llc -march=v6clang < %s | FileCheck %s
;
; O72 — V6CLANG_STORE16_P redesign. Pin the highest-value shapes:
;   row1: addr=HL, val=HL — dead-GR8 spare path (no A clobber)
;   row4: addr=DE, val=DE — XCHG-wrapped per-byte spare
;   row6a: addr=BC, val=BC, HL dead — 5B/40cc, no PUSH H

;===----------------------------------------------------------------------===
; row1: store of HL pointer through itself — uses dead-GR8 spare for the
; high byte (NOT A).
;===----------------------------------------------------------------------===
; CHECK-LABEL: row1_hl_hl:
; CHECK:       MOV [[T:[BCDE]]], H
; CHECK-NEXT:  MOV M, L
; CHECK-NEXT:  INX H
; CHECK-NEXT:  MOV M, [[T]]
; CHECK-NOT:   STAX
; CHECK-NOT:   PUSH PSW
define void @row1_hl_hl(ptr %p) {
  %v = ptrtoint ptr %p to i16
  store i16 %v, ptr %p
  ret void
}

;===----------------------------------------------------------------------===
; row4: store of DE pointer through itself, HL preserved across.
; Expansion: XCHG; MOV Spare, H; MOV M, L; INX H; MOV M, Spare; XCHG.
; Spare must be a dead GR8 (B in the typical case here); A must NOT be
; the staging register.
;===----------------------------------------------------------------------===
; CHECK-LABEL: row4_de_de:
; CHECK:       XCHG
; CHECK-NEXT:  MOV [[T:[BC]]], H
; CHECK-NEXT:  MOV M, L
; CHECK-NEXT:  INX H
; CHECK-NEXT:  MOV M, [[T]]
; CHECK-NEXT:  XCHG
; CHECK-NOT:   STAX
; CHECK-NOT:   PUSH PSW
define i16 @row4_de_de(i16 %hl_keep, ptr %p) {
  %v = ptrtoint ptr %p to i16
  store i16 %v, ptr %p
  ret i16 %hl_keep
}

;===----------------------------------------------------------------------===
; row6a: store of BC pointer through itself, HL dead. Use HL as scratch,
; no PUSH H / POP H.
;===----------------------------------------------------------------------===
; CHECK-LABEL: row6a_bc_bc_hl_dead:
; CHECK:       MOV H, B
; CHECK-NEXT:  MOV L, C
; CHECK-NEXT:  MOV M, C
; CHECK-NEXT:  INX H
; CHECK-NEXT:  MOV M, B
; CHECK-NOT:   PUSH H
; CHECK-NOT:   POP H
define void @row6a_bc_bc_hl_dead(i16 %a, i16 %b, ptr %p) {
  %v = ptrtoint ptr %p to i16
  store i16 %v, ptr %p
  ret void
}
