; RUN: llc -march=v6clang -O2 -mv6clang-spill-patched-reload -v6clang-disable-shld-lhld-fold < %s | FileCheck %s
; RUN: llc -march=v6clang -O2 -mv6clang-no-spill-patched-reload -v6clang-disable-shld-lhld-fold < %s | FileCheck %s --check-prefix=DISABLED

; O61 Stage 1: rewrite HL-only V6CLANG_SPILL16 / V6CLANG_RELOAD16 pairs into a
; patched LXI HL reload whose imm bytes are written by the SHLD spill.
;
; With the flag on, expect at least one SHLD to `.L...+1` followed by a
; label immediately before an `LXI HL, 0` (the patched reload). Other spill
; slots that route through DE/XCHG are out of Stage 1 scope and still use
; classical SHLD/LHLD. With the flag off, no patched-symbol label appears
; and `one_reload`'s HL slot uses classical SHLD/LHLD.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare i16 @op(i16)

; Single HL spill, single HL reload of the spilled value.
;
; CHECK-LABEL: one_reload:
; CHECK:       SHLD    .L[[SYM:[^ ]+]]+1
; CHECK:     .L[[SYM]]:
; CHECK-NEXT:  LXI     H, 0
;
; DISABLED-LABEL: one_reload:
; DISABLED-NOT: .LLo61_
; DISABLED:    SHLD    __v6clang_ss.one_reload
; DISABLED:    LHLD    __v6clang_ss.one_reload
define i16 @one_reload(i16 %x) norecurse {
entry:
  %a = call i16 @op(i16 %x)
  %b1 = call i16 @op(i16 %a)
  %b2 = call i16 @op(i16 %a)
  %r = add i16 %b1, %b2
  ret i16 %r
}
