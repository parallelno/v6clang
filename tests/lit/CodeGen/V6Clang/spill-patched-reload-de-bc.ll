; RUN: llc -march=v6clang -O2 -mv6clang-spill-patched-reload -v6clang-disable-shld-lhld-fold < %s | FileCheck %s

; O61 Stage 2: cost-model-driven HL spill / {HL,DE,BC} patched reload.
;
; The chooser (BlockFrequency * Delta) picks the single reload with the
; highest savings per slot and rewrites it as `LXI <DstRP>, 0` with a
; pre-instr label .Lo61_N. Remaining reloads (if any) are emitted as the
; classical reload sequence for their destination register, reading from
; the patched site's imm bytes (<Sym, MO_PATCH_IMM>).

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare i16 @op1(i16)
declare i16 @op2(i16)

; Single HL spill, single DE-target reload. Stage 1 rejected this
; (reload dst != HL). Stage 2 must patch with `LXI DE, 0`.
;
; CHECK-LABEL: de_one_reload:
; CHECK:         CALL    op1
; CHECK:         SHLD    .L[[SYM:Lo61_[0-9]+]]+1
; CHECK:       .L[[SYM]]:
; CHECK-NEXT:    LXI     D, 0
define i16 @de_one_reload(i16 %x, i16 %y) norecurse {
entry:
  %a = call i16 @op1(i16 %x)
  %b = call i16 @op2(i16 %y)
  %r = add i16 %a, %b
  ret i16 %r
}
