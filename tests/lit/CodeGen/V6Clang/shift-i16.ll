; RUN: llc -march=v6clang < %s | FileCheck %s

;===----------------------------------------------------------------------===
; SHL i16 tests
;===----------------------------------------------------------------------===

; CHECK-LABEL: shl1_i16:
; CHECK:       DAD H
; CHECK-NEXT:  RET
define i16 @shl1_i16(i16 %a) {
  %r = shl i16 %a, 1
  ret i16 %r
}

; shl by 3 = three repeated DAD HL sequences
; CHECK-LABEL: shl3_i16:
; CHECK:       DAD H
; CHECK-NEXT:  DAD H
; CHECK-NEXT:  DAD H
; CHECK-NEXT:  RET
define i16 @shl3_i16(i16 %a) {
  %r = shl i16 %a, 3
  ret i16 %r
}

; shl by 8 = move lo to hi, zero lo
; CHECK-LABEL: shl8_i16:
; CHECK-NOT:   ADD
; CHECK:       MOV H, {{[A-L]}}
; CHECK:       RET
define i16 @shl8_i16(i16 %a) {
  %r = shl i16 %a, 8
  ret i16 %r
}

; shl by 10 = move lo to hi, zero lo, shift hi left by 2
; CHECK-LABEL: shl10_i16:
; CHECK:       ADD A
; CHECK:       ADD A
; CHECK:       RET
define i16 @shl10_i16(i16 %a) {
  %r = shl i16 %a, 10
  ret i16 %r
}

; shl by 15 = rotate low byte once, then mask to keep only bit 7
; CHECK-LABEL: shl15_i16:
; CHECK:       MOV A, L
; CHECK-NEXT:  RRC
; CHECK-NEXT:  ANI 0x80
; CHECK-NEXT:  MVI L, 0
; CHECK-NEXT:  MOV H, A
; CHECK-NEXT:  RET
define i16 @shl15_i16(i16 %a) {
  %r = shl i16 %a, 15
  ret i16 %r
}

;===----------------------------------------------------------------------===
; SRL (logical right shift) i16 tests
;===----------------------------------------------------------------------===

; srl by 1 = ORA A (clear carry), RAR hi, RAR lo
; CHECK-LABEL: srl1_i16:
; CHECK:       MOV A, H
; CHECK-NEXT:  ORA A
; CHECK-NEXT:  RAR
; CHECK-NEXT:  MOV H, A
; CHECK-NEXT:  MOV A, L
; CHECK-NEXT:  RAR
; CHECK-NEXT:  MOV L, A
; CHECK-NEXT:  RET
define i16 @srl1_i16(i16 %a) {
  %r = lshr i16 %a, 1
  ret i16 %r
}

; srl by 3 = 24-bit left-shift trick in A:HL
; CHECK-LABEL: srl3_i16:
; CHECK:       XRA A
; CHECK:       DAD H
; CHECK:       ADC A
; CHECK:       DAD H
; CHECK:       ADC A
; CHECK:       DAD H
; CHECK:       ADC A
; CHECK:       DAD H
; CHECK:       ADC A
; CHECK:       DAD H
; CHECK:       ADC A
; CHECK:       MOV L, H
; CHECK:       MOV H, A
; CHECK:       RET
define i16 @srl3_i16(i16 %a) {
  %r = lshr i16 %a, 3
  ret i16 %r
}

; srl by 8 = move hi to lo, zero hi
; CHECK-LABEL: srl8_i16:
; CHECK:       MOV L, H
; CHECK-NEXT:  MVI H, 0
; CHECK-NEXT:  RET
define i16 @srl8_i16(i16 %a) {
  %r = lshr i16 %a, 8
  ret i16 %r
}

; srl by 10 = rotate the surviving source byte twice, then mask.
; CHECK-LABEL: srl10_i16:
; CHECK:       MOV A, H
; CHECK-NEXT:  RRC
; CHECK-NEXT:  RRC
; CHECK-NEXT:  ANI 0x3f
; CHECK-NEXT:  MOV L, A
; CHECK-NEXT:  MVI H, 0
; CHECK-NEXT:  RET
define i16 @srl10_i16(i16 %a) {
  %r = lshr i16 %a, 10
  ret i16 %r
}

; srl by 15 = rotate the source sign byte left once, then keep only bit 0
; CHECK-LABEL: srl15_i16:
; CHECK:       MOV A, H
; CHECK-NEXT:  RLC
; CHECK-NEXT:  ANI 1
; CHECK-NEXT:  MOV L, A
; CHECK-NEXT:  MVI H, 0
; CHECK-NEXT:  RET
define i16 @srl15_i16(i16 %a) {
  %r = lshr i16 %a, 15
  ret i16 %r
}

;===----------------------------------------------------------------------===
; SRA (arithmetic right shift) i16 tests
;===----------------------------------------------------------------------===

; sra by 1 = RLC (get sign bit), RAR hi (sign-extend), RAR lo
; CHECK-LABEL: sra1_i16:
; CHECK:       MOV A, H
; CHECK-NEXT:  RLC
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  RAR
; CHECK-NEXT:  MOV H, A
; CHECK-NEXT:  MOV A, L
; CHECK-NEXT:  RAR
; CHECK-NEXT:  MOV L, A
; CHECK-NEXT:  RET
define i16 @sra1_i16(i16 %a) {
  %r = ashr i16 %a, 1
  ret i16 %r
}

; sra by 7 = sign-propagating 24-bit left-shift trick in A:HL
; CHECK-LABEL: sra7_i16:
; CHECK:       MOV A, H
; CHECK-NEXT:  RLC
; CHECK-NEXT:  SBB A
; CHECK-NEXT:  DAD H
; CHECK-NEXT:  ADC A
; CHECK-NEXT:  MOV L, H
; CHECK-NEXT:  MOV H, A
; CHECK-NEXT:  RET
define i16 @sra7_i16(i16 %a) {
  %r = ashr i16 %a, 7
  ret i16 %r
}

; sra by 8 = move hi to lo, sign-extend hi (RLC+SBB)
; CHECK-LABEL: sra8_i16:
; CHECK:       MOV A, H
; CHECK-NEXT:  MOV L, H
; CHECK-NEXT:  RLC
; CHECK-NEXT:  SBB A
; CHECK-NEXT:  MOV H, A
; CHECK-NEXT:  RET
define i16 @sra8_i16(i16 %a) {
  %r = ashr i16 %a, 8
  ret i16 %r
}

; sra by 9 keeps the cheaper byte-lane + one arithmetic step form
; CHECK-LABEL: sra9_i16:
; CHECK:       MOV A, H
; CHECK-NEXT:  MOV L, H
; CHECK-NEXT:  RLC
; CHECK-NEXT:  SBB A
; CHECK-NEXT:  MOV H, A
; CHECK-NEXT:  MOV A, L
; CHECK-NEXT:  RLC
; CHECK-NEXT:  MOV A, L
; CHECK-NEXT:  RAR
; CHECK-NEXT:  MOV L, A
; CHECK-NEXT:  RET
define i16 @sra9_i16(i16 %a) {
  %r = ashr i16 %a, 9
  ret i16 %r
}

; sra by 15 = direct sign splat into both bytes
; CHECK-LABEL: sra15_i16:
; CHECK:       MOV A, H
; CHECK-NEXT:  RLC
; CHECK-NEXT:  SBB A
; CHECK-NEXT:  MOV H, A
; CHECK-NEXT:  MOV L, A
; CHECK-NEXT:  RET
define i16 @sra15_i16(i16 %a) {
  %r = ashr i16 %a, 15
  ret i16 %r
}
