; RUN: llc -march=v6clang < %s | FileCheck %s
; RUN: llc -march=v6clang --v6clang-disable-peephole --v6clang-disable-reg-value-forwarding < %s | FileCheck %s --check-prefix=DISABLED

target triple = "i8080-unknown-v6clang"

; Test V6ClangPeephole: redundant MOV elimination.
; Self-MOV (MOV X, X) should be removed.

; Simple function that returns its argument — should not have MOV A, A.
; CHECK-LABEL: test_self_mov:
; CHECK-NOT:   MOV A, A
; CHECK:       RET
define i8 @test_self_mov(i8 %a) {
  ret i8 %a
}

; Function with add that shouldn't produce redundant MOVs.
; CHECK-LABEL: test_no_redundant:
; CHECK:       ADD
; CHECK:       RET
define i8 @test_no_redundant(i8 %a, i8 %b) {
  %r = add i8 %a, %b
  ret i8 %r
}

; O82 follow-up: round-trip MOV X,Y ; MOV Y,X should be eliminated.
; This used to end with MOV L, A / MOV A, L.
; CHECK-LABEL: lshr9_trunc_roundtrip:
; CHECK-NEXT: ; %bb.0:
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  RRC
; CHECK-NEXT:  ANI 0x7f
; CHECK-NEXT:  RET
; DISABLED-LABEL: lshr9_trunc_roundtrip:
; DISABLED:      MOV L, A
; DISABLED:      MOV A, L
define i8 @lshr9_trunc_roundtrip(i16 %x) {
  %shift = lshr i16 %x, 9
  %trunc = trunc i16 %shift to i8
  ret i8 %trunc
}

; O82/O87 follow-up: ashr i16 by 9 feeding an i8 return should not build the
; dead sign-byte path at all. With the peephole enabled, the terminal
; MOV L,A / MOV A,L round-trip also disappears.
; CHECK-LABEL: ashr9_trunc_roundtrip:
; CHECK-NEXT: ; %bb.0:
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  RLC
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  RAR
; CHECK-NEXT:  RET
; DISABLED-LABEL: ashr9_trunc_roundtrip:
; DISABLED-NEXT: ; %bb.0:
; DISABLED-NEXT:  MOV A, H
; DISABLED-NEXT:  RLC
; DISABLED-NEXT:  MOV A, H
; DISABLED-NEXT:  RAR
; DISABLED-NEXT:  MOV L, A
; DISABLED-NEXT:  MOV A, L
; DISABLED-NEXT:  RET
define i8 @ashr9_trunc_roundtrip(i16 %x) {
  %shift = ashr i16 %x, 9
  %trunc = trunc i16 %shift to i8
  ret i8 %trunc
}

; CHECK-LABEL: ashr15_trunc_roundtrip:
; CHECK-NEXT: ; %bb.0:
; CHECK-NEXT:  MOV A, H
; CHECK-NEXT:  RLC
; CHECK-NEXT:  SBB A
; CHECK-NEXT:  RET
; DISABLED-LABEL: ashr15_trunc_roundtrip:
; DISABLED:      MOV L, A
; DISABLED:      MOV A, L
define i8 @ashr15_trunc_roundtrip(i16 %x) {
  %shift = ashr i16 %x, 15
  %trunc = trunc i16 %shift to i8
  ret i8 %trunc
}
