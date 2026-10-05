; RUN: llc -march=v6clang -mv6clang-annotate-pseudos < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@g8 = dso_local global i8 0, align 1

; CHECK-LABEL: neg16:
; CHECK:       ;--- V6CLANG_NEG16 ---
; CHECK-NEXT:  XRA A
; CHECK-NEXT:  SUB L
; CHECK-NEXT:  MOV L, A
; CHECK-NEXT:  SBB A
; CHECK-NEXT:  SUB H
; CHECK-NEXT:  MOV H, A
define dso_local i16 @neg16(i16 noundef %x) local_unnamed_addr {
  %n = sub i16 0, %x
  ret i16 %n
}

; CHECK-LABEL: neg8_a:
; CHECK:       ;--- V6CLANG_NEG8 ---
; CHECK-NEXT:  CMA
; CHECK-NEXT:  INR A
; CHECK-NEXT:  RET
define dso_local i8 @neg8_a(i8 noundef %x) local_unnamed_addr {
  %n = sub i8 0, %x
  ret i8 %n
}

; The second i8 argument is passed outside A, so the accumulator-only
; specialization must not fire.
;
; CHECK-LABEL: neg8_non_a:
; CHECK-NOT:   ;--- V6CLANG_NEG8 ---
; CHECK:       XRA A
; CHECK-NEXT:  SUB B
; CHECK-NEXT:  RET
; CHECK-NOT:   CMA
define dso_local i8 @neg8_non_a(i8 noundef %lead, i8 noundef %x) local_unnamed_addr {
  %n = sub i8 0, %x
  ret i8 %n
}

; Memory-source byte negate should keep the direct memory subtract path rather
; than forcing a load-to-A followed by CMA/INR.
;
; CHECK-LABEL: neg8_mem:
; CHECK-NOT:   ;--- V6CLANG_NEG8 ---
; CHECK:       LXI H, g8
; CHECK-NEXT:  XRA A
; CHECK-NEXT:  ;--- V6CLANG_SUB_M_P ---
; CHECK-NEXT:  SUB M
; CHECK-NEXT:  RET
; CHECK-NOT:   CMA
define dso_local i8 @neg8_mem() local_unnamed_addr {
  %v = load i8, ptr @g8, align 1
  %n = sub i8 0, %v
  ret i8 %n
}