; RUN: llc -march=v6clang < %s | FileCheck %s
; RUN: llc -march=v6clang --v6clang-disable-peephole --v6clang-disable-reg-value-forwarding < %s | FileCheck %s --check-prefix=NOPH
;
; O62 — Efficient i16 shift expansion for constant amount >= 8.
; Verifies that V6CLANG_SRL16 / V6CLANG_SRA16 / V6CLANG_SHL16 expansions for byte-
; aligned (and slightly larger) shift amounts:
;   1. skip the dead "copy Src to Dst" prologue,
;   2. zero/sign-extend the unused half via i8-domain ops,
;   3. use a half-width per-bit loop (DstLo only) for the residual
;      shift amount (ShAmt - 8), since DstHi is provably 0 / sign byte.
;
; The i8080 ABI passes the i16 argument in HL and the ptr in DE, so
; Src == Dst == HL at expansion time. This still exercises the changed
; code paths; the dst != src case is covered by the C-level feature
; test in tests/features/32.

target triple = "i8080-unknown-v6clang"

;===----------------------------------------------------------------------===
; SRL i16 by 8
;===----------------------------------------------------------------------===
; New expansion: byte-lane move H -> L + zero H. No per-bit RAR loop.
; CHECK-LABEL: srl8_i16:
; CHECK-NEXT: ; %bb.0:
; CHECK-NEXT:  MOV L, H
; CHECK-NEXT:  MVI H, 0
; O72: store via DE pointer is now XCHG-wrapped (no STAX D / MOV A, L).
; CHECK-NEXT:  XCHG
; CHECK-NEXT:  MOV M, E
; CHECK-NOT:   RAR
define void @srl8_i16(i16 %x, ptr %p) {
  %r = lshr i16 %x, 8
  store i16 %r, ptr %p
  ret void
}

;===----------------------------------------------------------------------===
; SRL i16 by 10
;===----------------------------------------------------------------------===
; O86: rotate the surviving source byte twice, then clear the wrapped bits.
; CHECK-LABEL: srl10_i16:
; CHECK-NEXT: ; %bb.0:
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  RRC
; CHECK-NEXT:  RRC
; CHECK-NEXT:  ANI 0x3f
; CHECK-NEXT:  MOV L, A
; CHECK-NEXT:  MVI H, 0
define void @srl10_i16(i16 %x, ptr %p) {
  %r = lshr i16 %x, 10
  store i16 %r, ptr %p
  ret void
}

;===----------------------------------------------------------------------===
; ASHR i16 by 8
;===----------------------------------------------------------------------===
; New expansion:
;   MOV A, H   ; capture sign byte (SrcHi)
;   MOV L, H   ; byte-lane move SrcHi -> DstLo
;   RLC
;   SBB A
;   MOV H, A   ; sign byte into DstHi
; No per-bit ASHR loop is needed for exactly 8.
; CHECK-LABEL: ashr8_i16:
; CHECK-NEXT: ; %bb.0:
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  MOV L, H
; CHECK-NEXT:  RLC
; CHECK-NEXT:  SBB A
; CHECK-NEXT:  MOV H, A
define void @ashr8_i16(i16 %x, ptr %p) {
  %r = ashr i16 %x, 8
  store i16 %r, ptr %p
  ret void
}

;===----------------------------------------------------------------------===
; ASHR i16 by 10
;===----------------------------------------------------------------------===
; O86: rotate/mask the kept low-byte bits from H, then OR in the sign-fill.
; CHECK-LABEL: ashr10_i16:
; CHECK-NEXT: ; %bb.0:
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  RRC
; CHECK-NEXT:  RRC
; CHECK-NEXT:  ANI 0x3f
; CHECK-NEXT:  MOV L, A
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  RLC
; CHECK-NEXT:  SBB A
; CHECK-NEXT:  MOV H, A
; CHECK-NEXT:  ANI 0xc0
; CHECK-NEXT:  ORA L
; CHECK-NEXT:  MOV L, A
define void @ashr10_i16(i16 %x, ptr %p) {
  %r = ashr i16 %x, 10
  store i16 %r, ptr %p
  ret void
}

;===----------------------------------------------------------------------===
; ASHR i16 by 9/10/15 feeding an i8 return
;===----------------------------------------------------------------------===
; These cases are lowered in V6CLANG_SRA16_RAM_LO, not created by the peephole.
; The no-peephole checks lock down that the expander itself skips the dead
; DstHi materialization when only the low byte escapes.

; CHECK-LABEL: ashr9_trunc_i16:
; CHECK-NEXT: ; %bb.0:
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  RLC
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  RAR
; CHECK-NEXT:  RET
; NOPH-LABEL: ashr9_trunc_i16:
; NOPH-NEXT: ; %bb.0:
; NOPH-NEXT:  MOV A, H
; NOPH-NEXT:  RLC
; NOPH-NEXT:  MOV A, H
; NOPH-NEXT:  RAR
; NOPH-NEXT:  MOV L, A
; NOPH-NEXT:  MOV A, L
; NOPH-NEXT:  RET
define i8 @ashr9_trunc_i16(i16 %x) {
  %r = ashr i16 %x, 9
  %t = trunc i16 %r to i8
  ret i8 %t
}

; CHECK-LABEL: ashr10_trunc_i16:
; CHECK-NEXT: ; %bb.0:
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  RRC
; CHECK-NEXT:  RRC
; CHECK-NEXT:  ANI 0x3f
; CHECK-NEXT:  MOV L, A
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  RLC
; CHECK-NEXT:  SBB A
; CHECK-NEXT:  ANI 0xc0
; CHECK-NEXT:  ORA L
; CHECK-NEXT:  RET
; NOPH-LABEL: ashr10_trunc_i16:
; NOPH-NEXT: ; %bb.0:
; NOPH-NEXT:  MOV A, H
; NOPH-NEXT:  RRC
; NOPH-NEXT:  RRC
; NOPH-NEXT:  ANI 0x3f
; NOPH-NEXT:  MOV L, A
; NOPH-NEXT:  MOV A, H
; NOPH-NEXT:  RLC
; NOPH-NEXT:  SBB A
; NOPH-NEXT:  ANI 0xc0
; NOPH-NEXT:  ORA L
; NOPH-NEXT:  MOV L, A
; NOPH-NEXT:  MOV A, L
; NOPH-NEXT:  RET
define i8 @ashr10_trunc_i16(i16 %x) {
  %r = ashr i16 %x, 10
  %t = trunc i16 %r to i8
  ret i8 %t
}

; CHECK-LABEL: ashr15_trunc_i16:
; CHECK-NEXT: ; %bb.0:
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  RLC
; CHECK-NEXT:  SBB A
; CHECK-NEXT:  RET
; NOPH-LABEL: ashr15_trunc_i16:
; NOPH-NEXT: ; %bb.0:
; NOPH-NEXT:  MOV A, H
; NOPH-NEXT:  RLC
; NOPH-NEXT:  SBB A
; NOPH-NEXT:  MOV L, A
; NOPH-NEXT:  MOV A, L
; NOPH-NEXT:  RET
define i8 @ashr15_trunc_i16(i16 %x) {
  %r = ashr i16 %x, 15
  %t = trunc i16 %r to i8
  ret i8 %t
}

;===----------------------------------------------------------------------===
; SHL i16 by 8 — sanity check (custom-lowered via BUILD_PAIR in ISel)
;===----------------------------------------------------------------------===
; This case never reaches the V6CLANG_SHL16 pseudo (LowerSHL_i16 emits
; BUILD_PAIR(0, lo) directly), so the diff vs. before O62 is zero.
; Locked down here only to detect future regressions.
; CHECK-LABEL: shl8_i16:
; CHECK:       MOV H, L
; CHECK-NOT:   ADD A
define void @shl8_i16(i16 %x, ptr %p) {
  %r = shl i16 %x, 8
  store i16 %r, ptr %p
  ret void
}

;===----------------------------------------------------------------------===
; SHL i16 by 10 — sanity check for the high-byte RAM specialization
;===----------------------------------------------------------------------===
; CHECK-LABEL: shl10_i16:
; CHECK-NEXT: ; %bb.0:
; CHECK-NEXT:  MOV A, L
; CHECK-NEXT:  ADD A
; CHECK-NEXT:  ADD A
; CHECK-NEXT:  MVI L, 0
; CHECK-NEXT:  MOV H, A
define void @shl10_i16(i16 %x, ptr %p) {
  %r = shl i16 %x, 10
  store i16 %r, ptr %p
  ret void
}
