; RUN: llc -march=v6clang < %s | FileCheck %s

; Pointer-use i16 add lowers to V6CLANG_DAD. The ADD operands may arrive as
; DE+HL after generic combines, but the post-RA expansion must keep the
; existing HL live-in as the DAD base instead of forcing DE into HL first.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; CHECK-LABEL: store_at_sum:
; CHECK:       DAD D
; CHECK-NEXT:  MVI M, 1
; CHECK-NEXT:  RET
define void @store_at_sum(i16 %off, i16 %i) {
entry:
  %sum = add i16 %i, %off
  %ptr = inttoptr i16 %sum to ptr
  store i8 1, ptr %ptr, align 1
  ret void
}
