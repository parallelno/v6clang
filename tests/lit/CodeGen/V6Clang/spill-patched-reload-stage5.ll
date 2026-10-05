; RUN: llc -march=v6clang -O2 -mv6clang-spill-patched-reload -v6clang-disable-shld-lhld-fold < %s | FileCheck %s

; O61 Stage 5: widen the i16 spill-source filter from HL-only to
; {HL, DE, BC}. The chooser, MO_PATCH_IMM lowering, K-cap rules, and
; reload-side emission are unchanged from Stage 3. Stage 5 adds a
; per-source switch in the spill emitter:
;   * HL: SHLD <Sym+1>               (unchanged)
;   * DE: XCHG; SHLD <Sym+1>; [XCHG] (trailing XCHG when HL live or DE live)
;   * BC: [PUSH H;] MOV L,C; MOV H,B; SHLD <Sym+1>; [POP H]

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare i16 @op1(i16)
declare i16 @op2(i16)
declare void @use3(i16, i16, i16)

; Three i16 values held across two A/HL-clobbering calls. The RA
; spills each of arg0 (HL), arg1 (DE), and arg2 (BC). Stage 4 only
; patched the HL-sourced slot; Stage 5 must patch all three.
;
; CHECK-LABEL: three_args:
;
; BC-source spill of arg2 (HL live at function entry). Expect the
; PUSH H; MOV L,C; MOV H,B; SHLD <Sym+1>; POP H ladder with the
; SHLD carrying the .Lo61_<N>+1 operand.
; CHECK:         PUSH    H
; CHECK-NEXT:    MOV     L, C
; CHECK-NEXT:    MOV     H, B
; CHECK-NEXT:    SHLD    .LLo61_{{[0-9]+}}+1
; CHECK-NEXT:    POP     H
;
; DE-source spill of arg1. Trailing XCHG is required because arg0 (HL)
; is still live across this spill.
; CHECK-NEXT:    XCHG
; CHECK-NEXT:    SHLD    .LLo61_{{[0-9]+}}+1
; CHECK-NEXT:    XCHG
define i16 @three_args(i16 %x, i16 %y, i16 %z) norecurse {
entry:
  %a = call i16 @op1(i16 %x)
  %b = call i16 @op2(i16 %y)
  %c = call i16 @op1(i16 %z)
  call void @use3(i16 %a, i16 %b, i16 %c)
  %s1 = add i16 %a, %b
  %s2 = add i16 %s1, %c
  ret i16 %s2
}

; DE-source spill with a single HL-target reload. The value %y held
; in DE must survive an HL-clobbering call, forcing a DE-source
; V6CLANG_SPILL16. Stage 4 rejected this (source != HL). Stage 5 must
; emit `XCHG; SHLD <Sym+1>; XCHG` (trailing XCHG kept because DE is
; still consumed after the leading XCHG fix-up wraps back).
;
; CHECK-LABEL: de_src_spill:
; CHECK:         XCHG
; CHECK-NEXT:    SHLD    .L[[SYM:Lo61_[0-9]+]]+1
; CHECK-NEXT:    XCHG
; CHECK:         CALL    op1
; CHECK:       .L[[SYM]]:
; CHECK-NEXT:    LXI     {{H|D}}, 0
define i16 @de_src_spill(i16 %x, i16 %y) norecurse {
entry:
  %a = call i16 @op1(i16 %x)
  %b = call i16 @op2(i16 %y)
  %r = add i16 %a, %b
  ret i16 %r
}
