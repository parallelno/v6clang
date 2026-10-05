; RUN: llc -march=v6clang < %s | FileCheck %s
;
; O73 — V6CLANG_LOAD16_G redesign. Per-shape, liveness-aware dispatch
; for the dst=BC arm. The dst=HL and dst=DE arms are unchanged from
; O42 and are spot-checked alongside.

@g = external dso_local global i16
declare void @sink3_i16(i16, i16, i16)
declare void @sink3_i16_i8(i16, i16, i16, i8)

; dst=HL — single LHLD, no MOV/PUSH staging.
; CHECK-LABEL: case1_dst_hl:
; CHECK:       LHLD g
; CHECK-NEXT:  RET
; CHECK-NOT:   PUSH
define i16 @case1_dst_hl() {
  %v = load i16, ptr @g, align 1
  ret i16 %v
}

; dst=DE — XCHG; LHLD; (XCHG may fold via foldXchgDad). No PUSH H.
; CHECK-LABEL: case2_dst_de:
; CHECK:       XCHG
; CHECK-NEXT:  LHLD g
; CHECK-NOT:   PUSH
define i16 @case2_dst_de(i16 %hl_keep) {
  %v = load i16, ptr @g, align 1
  %s = add i16 %hl_keep, %v
  ret i16 %s
}

; dst=DE, HL dead — drop the leading XCHG: LHLD addr; XCHG. (4B / 24cc).
; The result lands in DE; HL is clobbered but dead.
; CHECK-LABEL: case2b_dst_de_hl_dead:
; CHECK:       LHLD g
; CHECK-NEXT:  XCHG
; CHECK-NOT:   PUSH
define void @case2b_dst_de_hl_dead() {
  %v = load i16, ptr @g, align 1
  call void @sink3_i16(i16 0, i16 %v, i16 0)
  ret void
}

; dst=BC, HL dead at the load (no live i16 carried into BC slot besides
; the loaded value itself). Expected shape: LHLD; MOV B,H; MOV C,L.
; CHECK-LABEL: case3a_dst_bc_hl_dead:
; CHECK:       LHLD g
; CHECK-NEXT:  MOV B, H
; CHECK-NEXT:  MOV C, L
; CHECK-NOT:   PUSH
; CHECK-NOT:   LDA
define void @case3a_dst_bc_hl_dead() {
  %v = load i16, ptr @g, align 1
  call void @sink3_i16(i16 0, i16 0, i16 %v)
  ret void
}

; dst=BC, HL live (carries hl_keep into call's HL slot), A dead.
; Expected shape: LDA g; MOV C, A; LDA g+1; MOV B, A. No PUSH H.
; CHECK-LABEL: case3b_dst_bc_a_dead:
; CHECK:       LDA g
; CHECK-NEXT:  MOV C, A
; CHECK-NEXT:  LDA g+1
; CHECK-NEXT:  MOV B, A
; CHECK-NOT:   PUSH    H
define void @case3b_dst_bc_a_dead(i16 %hl_keep) {
  %v = load i16, ptr @g, align 1
  call void @sink3_i16(i16 %hl_keep, i16 0, i16 %v)
  ret void
}

; dst=BC, HL live, A live (a_keep flows to the i8 A-slot).
; Expected fallback shape: PUSH H; LHLD; MOV B,H; MOV C,L; POP H.
; CHECK-LABEL: case3c_dst_bc_a_live:
; CHECK:       PUSH    H
; CHECK:       LHLD g
; CHECK:       MOV B, H
; CHECK:       MOV C, L
; CHECK:       POP     H
; CHECK-NOT:   LDA g
define void @case3c_dst_bc_a_live(i16 %hl_keep, i16 %de_keep, i8 %a_keep) {
  %v = load i16, ptr @g, align 1
  call void @sink3_i16_i8(i16 %hl_keep, i16 %de_keep, i16 %v, i8 %a_keep)
  ret void
}
