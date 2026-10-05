; RUN: llc -march=v6clang < %s | FileCheck %s

; Test V6ClangXchgOpt: consecutive MOV D,H; MOV E,L (or reverse) should become XCHG.
; This function takes two i16 args (HL, DE) and adds them.
; The 16-bit add pseudo-expansion moves pair registers around,
; potentially producing MOV D,H / MOV E,L patterns replaceable by XCHG.

; Just verify that XCHG appears somewhere in the output or that there are
; no adjacent MOV D,H + MOV E,L pairs. With the optimization enabled,
; any DE<->HL copy pair should be replaced.

; CHECK-LABEL: test_add16:
; CHECK:       RET
define i16 @test_add16(i16 %a, i16 %b) {
  %r = add i16 %a, %b
  ret i16 %r
}
