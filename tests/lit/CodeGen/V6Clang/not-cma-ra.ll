; RUN: llc -march=v6clang -O2 < %s | FileCheck %s

; Regression test for "ran out of registers during register allocation".
;
; `v &= ~m` where v is loaded once and live across both arms of a branch used
; to crash RA: the `not` (CMA) narrowed m's vreg to the Acc class (register A
; only) for its whole live range, and v (an LDA result feeding ANA/ORA) was
; also pinned to A.  Both then required A at the same ANA instruction and the
; allocator ran out of registers.  Selecting `not` through COPY_TO_REGCLASS
; keeps m in a general GR8 register with only a short-lived Acc temp for CMA.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; CHECK-LABEL: maskbit:
; CHECK:       CMA
; CHECK:       ANA
; CHECK:       RET
define void @maskbit(i8 %m, i8 %vis) {
entry:
  %v = load i8, ptr inttoptr (i16 27136 to ptr), align 1
  %isset = icmp eq i8 %vis, 0
  %or = or i8 %v, %m
  %not = xor i8 %m, -1
  %and = and i8 %v, %not
  %res = select i1 %isset, i8 %and, i8 %or
  store i8 %res, ptr inttoptr (i16 27136 to ptr), align 1
  ret void
}
