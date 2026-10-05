; RUN: llc -march=v6clang -O3 < %s | FileCheck %s

; Repeated pointer offsets from the same live-in base must not let the first
; V6CLANG_DAD clobber HL when the pseudo result is allocated in DE. The physical
; expansion should compute DE = HL + imm while restoring the original HL base.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; CHECK-LABEL: neighbours3:
; CHECK:       LXI D, 0xffb1
; CHECK-NEXT:  XCHG
; CHECK-NEXT:  DAD D
; CHECK-NEXT:  XCHG
; CHECK-NEXT:  LDAX D
; CHECK:       LXI D, 0xffb2
; CHECK-NEXT:  XCHG
; CHECK-NEXT:  DAD D
; CHECK-NEXT:  XCHG
; CHECK-NEXT:  LDAX D
; CHECK:       LXI D, 0xffb3
; CHECK-NEXT:  DAD D
; CHECK-NEXT:  MOV A, M
; CHECK:       RET
define i16 @neighbours3(ptr %p) {
entry:
  %p0 = getelementptr inbounds i8, ptr %p, i16 -79
  %v0 = load i8, ptr %p0, align 1
  %b0 = and i8 %v0, 1
  %p1 = getelementptr inbounds i8, ptr %p, i16 -78
  %v1 = load i8, ptr %p1, align 1
  %b1 = and i8 %v1, 1
  %s1 = add nuw nsw i8 %b1, %b0
  %p2 = getelementptr inbounds i8, ptr %p, i16 -77
  %v2 = load i8, ptr %p2, align 1
  %b2 = and i8 %v2, 1
  %s2 = add nuw nsw i8 %s1, %b2
  %ret = zext nneg i8 %s2 to i16
  ret i16 %ret
}
