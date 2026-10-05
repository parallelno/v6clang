; RUN: llc -march=v6clang < %s | FileCheck %s

; Test the cost model wiring for V6CLANG_DAD pseudo expansion.
; DAD path: pointer arithmetic where HL is the base and a register pair
; holds a small constant (loaded via LXI). The cost model should replace
; LXI+DAD with INX chains for constants ???3.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; ptr+1 via GEP ??? should use INX HL instead of LXI+DAD.
; CHECK-LABEL: load_offset1:
; CHECK:       INX H
; CHECK-NOT:   DAD
; CHECK:       MOV A, M
; CHECK:       RET
define i8 @load_offset1(ptr %p) {
  %q = getelementptr i8, ptr %p, i16 1
  %v = load i8, ptr %q
  ret i8 %v
}

; ptr+2 via GEP ??? should use 2??INX HL.
; CHECK-LABEL: load_offset2:
; CHECK:       INX H
; CHECK-NEXT:  INX H
; CHECK-NOT:   DAD
; CHECK:       MOV A, M
; CHECK:       RET
define i8 @load_offset2(ptr %p) {
  %q = getelementptr i8, ptr %p, i16 2
  %v = load i8, ptr %q
  ret i8 %v
}

; ptr+3 via GEP ??? should use 3??INX HL (tied on cycles, fewer bytes).
; CHECK-LABEL: load_offset3:
; CHECK:       INX H
; CHECK-NEXT:  INX H
; CHECK-NEXT:  INX H
; CHECK-NOT:   DAD
; CHECK:       MOV A, M
; CHECK:       RET
define i8 @load_offset3(ptr %p) {
  %q = getelementptr i8, ptr %p, i16 3
  %v = load i8, ptr %q
  ret i8 %v
}

; ptr+4 via GEP ??? should use LXI+DAD (4??INX is more expensive).
; CHECK-LABEL: load_offset4:
; CHECK:       LXI D, 4
; CHECK:       DAD D
; CHECK:       MOV A, M
; CHECK:       RET
define i8 @load_offset4(ptr %p) {
  %q = getelementptr i8, ptr %p, i16 4
  %v = load i8, ptr %q
  ret i8 %v
}

; ptr-1 via GEP ??? should use DCX HL.
; CHECK-LABEL: load_minus1:
; CHECK:       DCX H
; CHECK-NOT:   DAD
; CHECK:       MOV A, M
; CHECK:       RET
define i8 @load_minus1(ptr %p) {
  %q = getelementptr i8, ptr %p, i16 -1
  %v = load i8, ptr %q
  ret i8 %v
}

; ptr-3 via GEP ??? should use 3??DCX HL.
; CHECK-LABEL: load_minus3:
; CHECK:       DCX H
; CHECK-NEXT:  DCX H
; CHECK-NEXT:  DCX H
; CHECK-NOT:   DAD
; CHECK:       MOV A, M
; CHECK:       RET
define i8 @load_minus3(ptr %p) {
  %q = getelementptr i8, ptr %p, i16 -3
  %v = load i8, ptr %q
  ret i8 %v
}

; optsize: ptr+3 should still use INX (cheaper on both axes).
; CHECK-LABEL: load_offset3_os:
; CHECK:       INX H
; CHECK-NEXT:  INX H
; CHECK-NEXT:  INX H
; CHECK-NOT:   DAD
; CHECK:       MOV A, M
; CHECK:       RET
define i8 @load_offset3_os(ptr %p) optsize {
  %q = getelementptr i8, ptr %p, i16 3
  %v = load i8, ptr %q
  ret i8 %v
}

; optsize: ptr+4 should still use LXI+DAD (4??INX is worse on both axes).
; CHECK-LABEL: load_offset4_os:
; CHECK:       LXI D, 4
; CHECK:       DAD D
; CHECK:       MOV A, M
; CHECK:       RET
define i8 @load_offset4_os(ptr %p) optsize {
  %q = getelementptr i8, ptr %p, i16 4
  %v = load i8, ptr %q
  ret i8 %v
}
