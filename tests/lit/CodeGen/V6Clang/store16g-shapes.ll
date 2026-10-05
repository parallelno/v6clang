; RUN: llc -march=v6clang < %s | FileCheck %s
;
; O74 — V6CLANG_STORE16_G redesign. Per-shape, liveness-aware dispatch
; for the val=DE/BC arms. The val=HL arm is unchanged.

@g = external dso_local global i16
declare void @sink_i8(i8)
declare void @sink3_i16_i8(i16, i16, i16, i8)

; val=HL — single SHLD.
; CHECK-LABEL: case1_val_hl:
; CHECK:       SHLD g
; CHECK-NEXT:  RET
; CHECK-NOT:   PUSH
; CHECK-NOT:   XCHG
; CHECK-NOT:   STA g
define void @case1_val_hl(i16 %v) {
  store i16 %v, ptr @g, align 1
  ret void
}

; val=DE, HL dead — XCHG; SHLD (no trailing XCHG).
; The first arg lands in HL but is unused after the store; the
; second arg lands in DE and is the value.
; CHECK-LABEL: case2a_val_de_hl_dead:
; CHECK:       XCHG
; CHECK-NEXT:  SHLD g
; CHECK-NEXT:  RET
; CHECK-NOT:   PUSH
; CHECK-NOT:   STA g
define void @case2a_val_de_hl_dead(i16 %unused_hl, i16 %v) {
  store i16 %v, ptr @g, align 1
  ret void
}

; val=DE, HL live — XCHG; SHLD; XCHG.
; HL is returned, so it must survive across the store.
; CHECK-LABEL: case2b_val_de_hl_live:
; CHECK:       XCHG
; CHECK-NEXT:  SHLD g
; CHECK-NEXT:  XCHG
; CHECK-NOT:   PUSH
; CHECK-NOT:   STA g
define i16 @case2b_val_de_hl_live(i16 %hl_keep, i16 %v) {
  store i16 %v, ptr @g, align 1
  ret i16 %hl_keep
}

; val=BC, HL dead — MOV H,B; MOV L,C; SHLD.
; Three i16 args land in HL/DE/BC; the BC arg is the value;
; HL and DE are unused after.
; CHECK-LABEL: case3a_val_bc_hl_dead:
; CHECK:       MOV H, B
; CHECK-NEXT:  MOV L, C
; CHECK-NEXT:  SHLD g
; CHECK-NOT:   PUSH
; CHECK-NOT:   STA g
define void @case3a_val_bc_hl_dead(i16 %unused_hl, i16 %unused_de, i16 %v) {
  store i16 %v, ptr @g, align 1
  ret void
}

; val=BC, HL live, A dead — MOV A,C; STA; MOV A,B; STA+1.
; HL is returned (live across store); A is never set.
; CHECK-LABEL: case3b_val_bc_a_dead:
; CHECK:       MOV A, C
; CHECK-NEXT:  STA g
; CHECK-NEXT:  MOV A, B
; CHECK-NEXT:  STA g+1
; CHECK-NOT:   PUSH    H
define i16 @case3b_val_bc_a_dead(i16 %hl_keep, i16 %unused_de, i16 %v) {
  store i16 %v, ptr @g, align 1
  ret i16 %hl_keep
}

; val=BC, HL live, A live — PUSH H; MOV H,B; MOV L,C; SHLD; POP H.
; All four arg-class slots (HL, DE, BC, A) flow through a sink call after
; the store, forcing RA to keep HL live across the pseudo and A live too.
; CHECK-LABEL: case3c_val_bc_a_live:
; CHECK:       PUSH    H
; CHECK:       MOV H, B
; CHECK:       MOV L, C
; CHECK:       SHLD g
; CHECK:       POP     H
; CHECK-NOT:   STA g
define void @case3c_val_bc_a_live(i16 %hl_keep, i16 %de_keep, i16 %v, i8 %a_keep) {
  store i16 %v, ptr @g, align 1
  call void @sink3_i16_i8(i16 %hl_keep, i16 %de_keep, i16 %v, i8 %a_keep)
  ret void
}
