; RUN: llc -march=v6clang < %s | FileCheck %s
; RUN: llc -march=v6clang --v6clang-disable-peephole < %s | FileCheck %s --check-prefix=DISABLED
;
; O88: MVI-through-MOV collapse.
; Pattern: MVI X, Imm ; [no intervening read/clobber of X] ; MOV Z, X
;          where X is dead after the MOV.
; Transform: emit MVI Z, Imm and erase both the original MVI and the MOV.
;
; Primary trigger: zext i8 -> i16 for pointer arithmetic, where the hi-half
; zero is materialised into an intermediate register before V6CLANG_BUILD_PAIR
; copies it to its final location.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@sin_lut = external global [256 x i8]

; O88 positive: zext i8 → i16 for table lookup.
; Before: MVI L,0 / MOV H,L / MOV L,A  (24cc, 4B)
; After:  MVI H,0 / MOV L,A            (16cc, 3B)
;
; CHECK-LABEL: lookup_zext:
; CHECK-NEXT: ; %bb.0:
; CHECK-NEXT:  MVI H, 0
; CHECK-NEXT:  MOV L, A
; CHECK-NOT:   MOV H, L
;
; DISABLED-LABEL: lookup_zext:
; DISABLED-NEXT: ; %bb.0:
; DISABLED-NEXT:  MVI L, 0
; DISABLED-NEXT:  MOV H, L
; DISABLED-NEXT:  MOV L, A
define i8 @lookup_zext(i8 %angle) {
  %ext = zext i8 %angle to i16
  %ptr = getelementptr inbounds i8, ptr @sin_lut, i16 %ext
  %val = load i8, ptr %ptr
  ret i8 %val
}

; O88 positive: zext i8 → i16 as addend in 16-bit addition.
; The zero half is materialised via an intermediate and then consumed
; by a DAD as the hi byte of one operand.
; After O88 the zero is written directly to the final hi register.
;
; CHECK-LABEL: zext_add:
; CHECK-NOT:   MOV D, E
; CHECK-NOT:   MOV H, L
; DISABLED-LABEL: zext_add:
; DISABLED:    MVI {{[BCDEHL]}}, 0
; DISABLED-NEXT: MOV
define i16 @zext_add(i8 %a, i16 %b) {
  %ext = zext i8 %a to i16
  %sum = add i16 %ext, %b
  ret i16 %sum
}
