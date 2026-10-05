; RUN: llc -march=v6clang -O2 -mv6clang-spill-patched-reload -v6clang-disable-shld-lhld-fold < %s | FileCheck %s

; O61 Stage 3: multi-source HL spill (K <= 1) and single-source K <= 2
; patched reloads. The chooser (BlockFrequency * Delta) picks up to two
; reloads to patch and excludes HL-target candidates from the 2nd patch
; (2nd-patch Delta for HL is -12 cc per the O61 design doc).

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare i16 @op1(i16)
declare i16 @op2(i16)

; Multi-source HL spill: three HL spills of `a` across call sites in
; one function, each followed by a reload. Stage 2 rejected (filter
; required Spills.size() == 1). Stage 3 must accept as K=1 multi-source:
; every SHLD retargeted to the patched site, and the patched reload
; itself emits `LXI DE, 0` at .Lo61_N.
;
; CHECK-LABEL: multi_source:
; CHECK:         CALL    op2
; CHECK:         CALL    op1
; CHECK:         SHLD    .L[[SYM:Lo61_[0-9]+]]+1
; CHECK:       .L[[SYM]]:
; CHECK-NEXT:    LXI     D, 0
define i16 @multi_source(i16 %x, i16 %y, i16 %z) norecurse {
entry:
  %a1 = call i16 @op1(i16 %x)
  %b1 = call i16 @op2(i16 %y)
  %s1 = add i16 %a1, %b1
  %a2 = call i16 @op1(i16 %x)
  %b2 = call i16 @op2(i16 %z)
  %s2 = add i16 %a2, %b2
  %r = add i16 %s1, %s2
  ret i16 %r
}
