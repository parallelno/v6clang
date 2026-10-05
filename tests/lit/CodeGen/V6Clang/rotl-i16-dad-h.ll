; RUN: llc -march=v6clang < %s | FileCheck %s

; O68 Phase 2: rotl i16 x, 1 → DAD H + MVI A,0 + ADC L carry-fold (5B / 26cc).

;-------------------------------------------------------------
; Case 1: scalar rotl i16, 1 — exact 4-instruction sequence.
;-------------------------------------------------------------
; CHECK-LABEL: rotl_u16_1:
; CHECK:       DAD     H
; CHECK-NEXT:  MVI     A, 0
; CHECK-NEXT:  ADC     L
; CHECK-NEXT:  MOV     L, A
; CHECK-NEXT:  RET
; Negative-assert: no fall-back to default Expand (RAR is part of SRL by 15).
; CHECK-NOT:   RAR
; CHECK-NOT:   __lshrhi3
define i16 @rotl_u16_1(i16 %x) {
  %shl = shl i16 %x, 1
  %shr = lshr i16 %x, 15
  %r   = or i16 %shl, %shr
  ret i16 %r
}

;-------------------------------------------------------------
; Case 2: rotl i16, 2 — falls back to default Expand path
; (constant != 1). Just confirm the new path doesn't fire and
; we don't regress to a libcall.
;-------------------------------------------------------------
; CHECK-LABEL: rotl_u16_2:
; CHECK-NOT:   ADC     L
; CHECK-NOT:   __ashlhi3
; CHECK-NOT:   __lshrhi3
; CHECK:       RET
define i16 @rotl_u16_2(i16 %x) {
  %shl = shl i16 %x, 2
  %shr = lshr i16 %x, 14
  %r   = or i16 %shl, %shr
  ret i16 %r
}

;-------------------------------------------------------------
; Case 3: llvm.fshl funnel-shift idiom (CRC-style) by 1.
; Instruction-Combine should canonicalise to rotl, which then
; lowers via the new path.
;-------------------------------------------------------------
; CHECK-LABEL: fshl_u16_1:
; CHECK:       DAD     H
; CHECK-NEXT:  MVI     A, 0
; CHECK-NEXT:  ADC     L
; CHECK-NEXT:  MOV     L, A
; CHECK-NEXT:  RET
declare i16 @llvm.fshl.i16(i16, i16, i16)
define i16 @fshl_u16_1(i16 %x) {
  %r = call i16 @llvm.fshl.i16(i16 %x, i16 %x, i16 1)
  ret i16 %r
}
