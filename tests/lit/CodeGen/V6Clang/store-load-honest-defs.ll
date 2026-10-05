; RUN: llc -march=v6clang < %s | FileCheck %s
;
; O20: Honest Store/Load Pseudo Defs ??? verify HL-preserving expansion.

@arr = global [100 x i8] zeroinitializer

; Simple store through pointer — val in A (first arg), addr in HL
; (first i16 arg under free-list CC). Should use MOV M,A directly.
; CHECK-LABEL: store_byte:
; CHECK:       MOV     M, A
; CHECK-NOT:   PUSH
; CHECK:       RET
define void @store_byte(i8 %val, ptr %p) {
  store i8 %val, ptr %p
  ret void
}

; Simple load through pointer ??? addr arrives in HL (first arg).
; Should use MOV A, M directly, no copy.
; CHECK-LABEL: load_byte:
; CHECK:       MOV     A, M
; CHECK-NOT:   PUSH
; CHECK:       RET
define i8 @load_byte(ptr %p) {
  %v = load i8, ptr %p
  ret i8 %v
}

; Single-pointer store loop ??? the key O20 pattern.
; With argument in A occupying L, RA places pointer in DE and uses STAX.
; No DE???HL copy per iteration.
; CHECK-LABEL: fill_array:
; CHECK-NOT:   MOV     H, D
; CHECK-NOT:   MOV     L, E
; CHECK:       STAX    D
; CHECK:       INX     D
define void @fill_array(i8 %start) {
entry:
  br label %loop

loop:
  %i = phi i16 [0, %entry], [%i.next, %loop]
  %v = phi i8 [%start, %entry], [%v.next, %loop]
  %ptr = getelementptr inbounds [100 x i8], ptr @arr, i16 0, i16 %i
  store i8 %v, ptr %ptr
  %i.next = add nuw i16 %i, 1
  %v.next = add i8 %v, 1
  %cmp = icmp ne i16 %i.next, 100
  br i1 %cmp, label %loop, label %exit

exit:
  ret void
}
