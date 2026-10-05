; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s
;
; O76 — V6CLANG_LOAD8_P per-shape redesign. Spot-checks for the priority-4
; sub-shapes:
;   case7_de_*  : addr=DE, A live → XCHG bypass (3B/16cc).
;   case6a_bc_* : addr=BC, A live, SpareR available → SpareR-A (4B/32cc).
;   case6b_bc_* : addr=BC, A live, no spare → PSW-wrap fallback.
;
; Exhaustive shape coverage and cycle-count anchoring lives in
; tests/features/58/. This file pins down the canonical emissions.

; case7_de_b — addr=DE, dst=B, A live (kept in A across the load by
; means of the trailing inline-asm 'a' constraint).
;
; CHECK-LABEL: case7_de_b:
; CHECK:       XCHG
; CHECK-NEXT:  MOV     B, M
; CHECK-NEXT:  XCHG
; CHECK-NOT:   PUSH    PSW
; CHECK-NOT:   LDAX
define void @case7_de_b(i16 %hl_keep, ptr %de_ptr, i8 %a_keep) {
  %v = load i8, ptr %de_ptr
  call void asm sideeffect "OUT 0xde", "{a},{b},r"(i8 %a_keep, i8 %v, i16 %hl_keep)
  ret void
}

; case7_de_c — addr=DE, dst=C, A live.
; CHECK-LABEL: case7_de_c:
; CHECK:       XCHG
; CHECK-NEXT:  MOV     C, M
; CHECK-NEXT:  XCHG
; CHECK-NOT:   PUSH    PSW
define void @case7_de_c(i16 %hl_keep, ptr %de_ptr, i8 %a_keep) {
  %v = load i8, ptr %de_ptr
  call void asm sideeffect "OUT 0xde", "{a},{c},r"(i8 %a_keep, i8 %v, i16 %hl_keep)
  ret void
}

; case7_de_h — addr=DE, dst=H, A live. Partner-MOV trick: emits
; `MOV D, M` (not `MOV H, M`), so post-XCHG the loaded byte lands in H.
; CHECK-LABEL: case7_de_h:
; CHECK:       XCHG
; CHECK-NEXT:  MOV     D, M
; CHECK-NEXT:  XCHG
; CHECK-NOT:   PUSH    PSW
define void @case7_de_h(i16 %hl_keep, ptr %de_ptr, i8 %a_keep) {
  %v = load i8, ptr %de_ptr
  call void asm sideeffect "OUT 0xde", "{a},{h},r"(i8 %a_keep, i8 %v, i16 %hl_keep)
  ret void
}

; case7_de_l — addr=DE, dst=L, A live. Partner-MOV: `MOV E, M`.
; CHECK-LABEL: case7_de_l:
; CHECK:       XCHG
; CHECK-NEXT:  MOV     E, M
; CHECK-NEXT:  XCHG
; CHECK-NOT:   PUSH    PSW
define void @case7_de_l(i16 %hl_keep, ptr %de_ptr, i8 %a_keep) {
  %v = load i8, ptr %de_ptr
  call void asm sideeffect "OUT 0xde", "{a},{l},r"(i8 %a_keep, i8 %v, i16 %hl_keep)
  ret void
}

; case6a_bc_b — addr=BC, dst=B, A live, SpareR avail (D/E or another
; non-{A,B} GR8 is dead at the load). Expect:
;   MOV  spareR, A
;   LDAX B
;   MOV  B, A
;   MOV  A, spareR
; (4B / 32cc). No PSW envelope.
;
; CHECK-LABEL: case6a_bc_b:
; CHECK:       MOV     [[T:[CDEHL]]], A
; CHECK-NEXT:  LDAX    B
; CHECK-NEXT:  MOV     B, A
; CHECK-NEXT:  MOV     A, [[T]]
; CHECK-NOT:   PUSH    PSW
define void @case6a_bc_b(i16 %hl_keep, i16 %de_keep, ptr %bc_ptr, i8 %a_keep) {
  %v = load i8, ptr %bc_ptr
  call void asm sideeffect "OUT 0xde", "{a},{b},r,r"(i8 %a_keep, i8 %v, i16 %hl_keep, i16 %de_keep)
  ret void
}

; case4_bc_a_dead — addr=BC, dst=B, A dead. Existing (unchanged) shape:
;   LDAX B; MOV B, A
; CHECK-LABEL: case4_bc_a_dead:
; CHECK:       LDAX    B
; CHECK-NEXT:  MOV     B, A
; CHECK-NOT:   PUSH    PSW
; CHECK-NOT:   XCHG
define void @case4_bc_a_dead(i16 %hl_keep, i16 %de_keep, ptr %bc_ptr) {
  %v = load i8, ptr %bc_ptr
  call void asm sideeffect "OUT 0xde", "{b},r,r"(i8 %v, i16 %hl_keep, i16 %de_keep)
  ret void
}
