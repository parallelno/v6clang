; RUN: llc -mtriple=i8080-unknown-v6clang -O2 -mv6clang-annotate-pseudos -v6clang-disable-alloca-promote -v6clang-disable-static-stack-alloc < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare void @escape(ptr)

; CHECK-LABEL: load8_stack_arg:
; CHECK: ;--- V6CLANG_LOAD8_FI ---
; CHECK-NEXT: LXI H, {{[0-9]+}}
; CHECK-NEXT: DAD SP
; CHECK-NEXT: MOV A, M
; CHECK-NOT: ;--- V6CLANG_LEA_FI ---
; CHECK-NOT: ;--- V6CLANG_LOAD8_P ---
define i8 @load8_stack_arg(i8 %a0, i8 %a1, i8 %a2, i8 %a3,
                           i8 %a4, i8 %a5, i8 %a6, i8 %a7) {
entry:
  ret i8 %a7
}

; CHECK-LABEL: load16_stack_arg:
; CHECK: ;--- V6CLANG_LOAD16_FI ---
; CHECK-NEXT: LXI H, 2
; CHECK-NEXT: DAD SP
; CHECK-NEXT: MOV {{[A-Z]}}, M
; CHECK-NEXT: INX H
; CHECK-NEXT: MOV {{[A-Z]}}, M
; CHECK-NOT: ;--- V6CLANG_LEA_FI ---
; CHECK-NOT: ;--- V6CLANG_LOAD16_P ---
define i16 @load16_stack_arg(i16 %a0, i16 %a1, i16 %a2, i16 %a3) {
entry:
  %sum01 = add i16 %a0, %a1
  %sum012 = add i16 %sum01, %a2
  %sum0123 = add i16 %sum012, %a3
  ret i16 %sum0123
}

; CHECK-LABEL: store8_local:
; CHECK: ;--- V6CLANG_STORE8_FI ---
; CHECK-NEXT: LXI H, 0
; CHECK-NEXT: DAD SP
; CHECK-NEXT: MOV M, A
; CHECK: ;--- V6CLANG_LEA_FI ---
; CHECK: CALL escape
; CHECK: ;--- V6CLANG_LOAD8_FI ---
define i8 @store8_local(i8 %x) {
entry:
  %slot = alloca i8, align 1
  store volatile i8 %x, ptr %slot, align 1
  call void @escape(ptr %slot)
  %v = load volatile i8, ptr %slot, align 1
  ret i8 %v
}

; CHECK-LABEL: store16_local:
; CHECK: ;--- V6CLANG_STORE16_FI ---
; CHECK-NEXT: LXI H, 0
; CHECK-NEXT: DAD SP
; CHECK-NEXT: MOV M, C
; CHECK-NEXT: INX H
; CHECK-NEXT: MOV M, B
; CHECK: ;--- V6CLANG_LEA_FI ---
; CHECK: CALL escape
; CHECK: ;--- V6CLANG_LOAD16_FI ---
define i16 @store16_local(i16 %x) {
entry:
  %slot = alloca i16, align 1
  store volatile i16 %x, ptr %slot, align 1
  call void @escape(ptr %slot)
  %v = load volatile i16, ptr %slot, align 1
  ret i16 %v
}
