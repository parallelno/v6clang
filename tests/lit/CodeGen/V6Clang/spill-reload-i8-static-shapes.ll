; RUN: llc -march=v6clang -O2 -mv6clang-static-stack -mv6clang-no-spill-patched-reload < %s | FileCheck %s

; O64 — Liveness-Aware i8 Spill/Reload Lowering (shared decision ladder
; in V6ClangSpillExpand). For static-stack-eligible functions the ladder
; must never emit the classical `PUSH HL ; LXI HL, __v6clang_ss+N ;
; MOV r, M ; POP HL` fallback when a cheaper row applies.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare i8 @op(i8)
declare void @use5(i8, i8, i8, i8, i8)

; Main-like scenario: five A-clobbering calls followed by a 5-arg
; consumer. Drives multiple i8 spill/reload sites on the static slot.
; The post-call reload of the 4th spilled value (x4) into a GR8 fires
; O64 Shape B Row 3 — HL is live (it was just loaded with DAD SP as
; the outparam-buffer pointer), A is live (holds x5 returned by op),
; and B is dead. Result: MOV B, A ; LDA slot ; MOV <Dst>, A ; MOV A, B.
;
; The anti-pattern is the old fallback `PUSH HL ; LXI HL, __v6clang_ss.* ;
; MOV r, M ; POP HL`; O64 must not emit it under static stack when a
; cheaper row applies.
;
; CHECK-LABEL: main_like:
; CHECK-NOT:   PUSH{{[ \t]+}}HL
; CHECK:       STA     __v6clang_ss.main_like
; CHECK-NOT:   POP{{[ \t]+}}HL
define void @main_like() norecurse {
entry:
  %x1 = call i8 @op(i8 17)
  %x2 = call i8 @op(i8 34)
  %x3 = call i8 @op(i8 51)
  %x4 = call i8 @op(i8 68)
  %x5 = call i8 @op(i8 85)
  call void @use5(i8 %x1, i8 %x2, i8 %x3, i8 %x4, i8 %x5)
  ret void
}

; Simple two-call function: both i8 reload sites either hit Shape A
; (LDA) or Shape B Row 1 (HL dead) — neither needs PUSH/POP HL.
; CHECK-LABEL: row_b1:
; CHECK-NOT:   PUSH{{[ \t]+}}HL
; CHECK-NOT:   POP{{[ \t]+}}HL
define i8 @row_b1(i8 %a, i8 %b) norecurse {
entry:
  %x = call i8 @op(i8 %a)
  %y = call i8 @op(i8 %b)
  %s = add i8 %x, %y
  ret i8 %s
}
