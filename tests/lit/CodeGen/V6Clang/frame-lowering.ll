; RUN: llc -march=v6clang -v6clang-disable-alloca-promote -v6clang-disable-static-stack-alloc < %s | FileCheck %s

; Test prologue/epilogue for function with 1 byte of locals.
; CHECK-LABEL: one_local:
; CHECK:       LXI H, 0xffff
; CHECK-NEXT:  DAD SP
; CHECK-NEXT:  SPHL
; CHECK:       LXI H, 1
; CHECK-NEXT:  DAD SP
; CHECK-NEXT:  SPHL
; CHECK-NEXT:  RET
define i8 @one_local(i8 %x) {
  %p = alloca i8
  store i8 %x, ptr %p
  %v = load i8, ptr %p
  ret i8 %v
}

; Test prologue/epilogue for function with 4-byte array local.
; O54: PUSH/POP of a dead pair beats LXI+DAD+SPHL on 4-byte even frames.
; CHECK-LABEL: array_local:
; CHECK:       PUSH B
; CHECK-NEXT:  PUSH B
; CHECK:       POP B
; CHECK-NEXT:  POP B
; CHECK-NEXT:  RET
define i8 @array_local(i8 %x) {
  %arr = alloca [4 x i8]
  %p = getelementptr [4 x i8], ptr %arr, i16 0, i16 0
  store i8 %x, ptr %p
  %v = load i8, ptr %p
  ret i8 %v
}
