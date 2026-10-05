; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s
;
; O78 — V6CLANG_STORE8_IMM_P per-shape redesign. Each function pins
; AddrReg via free-list CC (1st i16 arg → HL, 2nd → DE, 3rd → BC)
; and uses inline-asm sinks to control liveness of A/HL/DE.

; Row 1: addr=HL → MVI M, imm.
; CHECK-LABEL: row1_hl:
; CHECK:       MVI     M, 0x42
; CHECK-NOT:   STAX
; CHECK-NOT:   XCHG
; CHECK-NOT:   PUSH    H
define void @row1_hl(ptr %hl_ptr) {
  store i8 66, ptr %hl_ptr
  ret void
}

; Row 2: addr=BC, A dead → MVI A, imm; STAX B.
; CHECK-LABEL: row2_bc_a_dead:
; CHECK:       MVI     A, 0x42
; CHECK-NEXT:  STAX    B
; CHECK-NOT:   PUSH    H
; CHECK-NOT:   XCHG
define void @row2_bc_a_dead(i16 %hl_keep, i16 %de_keep, ptr %bc_ptr) {
  store i8 66, ptr %bc_ptr
  call void asm sideeffect "OUT 0xde", "r"(i16 %hl_keep)
  call void asm sideeffect "OUT 0xde", "r"(i16 %de_keep)
  ret void
}

; Row 3: addr=DE, A dead → MVI A, imm; STAX D.
; CHECK-LABEL: row3_de_a_dead:
; CHECK:       MVI     A, 0x42
; CHECK-NEXT:  STAX    D
; CHECK-NOT:   XCHG
define void @row3_de_a_dead(i16 %hl_keep, ptr %de_ptr) {
  store i8 66, ptr %de_ptr
  call void asm sideeffect "OUT 0xde", "r"(i16 %hl_keep)
  ret void
}

; Row 4: addr=DE, A live → XCHG; MVI M, imm; XCHG.
; CHECK-LABEL: row4_de_a_live:
; CHECK:       XCHG
; CHECK-NEXT:  MVI     M, 0x42
; CHECK-NEXT:  XCHG
define void @row4_de_a_live(i16 %hl_keep, ptr %de_ptr, i8 %a_keep) {
  store i8 66, ptr %de_ptr
  call void asm sideeffect "OUT 0xde", "{a},r"(i8 %a_keep, i16 %hl_keep)
  ret void
}

; Row 5: addr=BC, A live, HL dead → MOV L, C; MOV H, B; MVI M, imm.
; HL is sunk before the store, so it's dead at the pseudo.
; CHECK-LABEL: row5_bc_hl_dead:
; CHECK:       MOV     L, C
; CHECK-NEXT:  MOV     H, B
; CHECK-NEXT:  MVI     M, 0x42
; CHECK-NOT:   PUSH    H
; CHECK-NOT:   XCHG
define void @row5_bc_hl_dead(i16 %hl_keep, i16 %de_keep, ptr %bc_ptr, i8 %a_keep) {
  call void asm sideeffect "OUT 0xde", "r"(i16 %hl_keep)
  store i8 66, ptr %bc_ptr
  call void asm sideeffect "OUT 0xde", "{a},r"(i8 %a_keep, i16 %de_keep)
  ret void
}

; Row 6: addr=BC, A live, HL live, DE dead → MOV D,B; MOV E,C; XCHG; MVI M; XCHG.
; DE is sunk before the store, HL/A are kept live across.
; CHECK-LABEL: row6_bc_de_dead:
; CHECK:       MOV     D, B
; CHECK-NEXT:  MOV     E, C
; CHECK-NEXT:  XCHG
; CHECK-NEXT:  MVI     M, 0x42
; CHECK-NEXT:  XCHG
; CHECK-NOT:   PUSH    H
define void @row6_bc_de_dead(i16 %hl_keep, i16 %de_keep, ptr %bc_ptr, i8 %a_keep) {
  call void asm sideeffect "OUT 0xde", "r"(i16 %de_keep)
  store i8 66, ptr %bc_ptr
  call void asm sideeffect "OUT 0xde", "{a},r"(i8 %a_keep, i16 %hl_keep)
  ret void
}

; Row 7: addr=BC, all live → PUSH H; MOV L,C; MOV H,B; MVI M; POP H.
; CHECK-LABEL: row7_bc_all_live:
; CHECK:       PUSH    H
; CHECK-NEXT:  MOV     L, C
; CHECK-NEXT:  MOV     H, B
; CHECK-NEXT:  MVI     M, 0x42
; CHECK-NEXT:  POP     H
define void @row7_bc_all_live(i16 %hl_keep, i16 %de_keep, ptr %bc_ptr, i8 %a_keep) {
  store i8 66, ptr %bc_ptr
  call void asm sideeffect "OUT 0xde", "{a},r,r"(i8 %a_keep, i16 %hl_keep, i16 %de_keep)
  ret void
}
