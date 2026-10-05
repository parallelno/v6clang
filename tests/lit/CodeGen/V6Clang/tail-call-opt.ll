; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; Test 1: Simple tail call — CALL+RET replaced with JMP.
define i16 @wrapper(i16 %x) {
; CHECK-LABEL: wrapper:
; CHECK-NOT:   CALL
; CHECK:       JMP	helper
; CHECK-NOT:   RET
entry:
  %r = call i16 @helper(i16 %x)
  ret i16 %r
}
declare i16 @helper(i16)

; Test 2: Void tail call.
define void @void_wrapper() {
; CHECK-LABEL: void_wrapper:
; CHECK-NOT:   CALL
; CHECK:       JMP	void_func
; CHECK-NOT:   RET
entry:
  call void @void_func()
  ret void
}
declare void @void_func()

; Test 3: NOT a tail call — work after call prevents optimization.
define i16 @not_tail(i16 %x) {
; CHECK-LABEL: not_tail:
; CHECK:       CALL	helper
; CHECK:       RET
entry:
  %r = call i16 @helper(i16 %x)
  %r2 = add i16 %r, 1
  ret i16 %r2
}

; Test 4: Dispatch — both branches get tail-call optimized.
; Branch inversion converts JZ+V6CLANG_TAILJMP into conditional JNZ.
define void @dispatch(i8 %cmd) {
; CHECK-LABEL: dispatch:
; CHECK:       JNZ	func_b
; CHECK:       JMP	func_a
; CHECK-NOT:   CALL
entry:
  %cmp = icmp eq i8 %cmd, 1
  br i1 %cmp, label %a, label %b

a:
  call void @func_a()
  ret void

b:
  call void @func_b()
  ret void
}
declare void @func_a()
declare void @func_b()

; Test 5: Tail call disabled via -v6clang-disable-peephole.
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 -v6clang-disable-peephole < %s \
; RUN:   | FileCheck %s --check-prefix=DISABLED

; DISABLED-LABEL: wrapper:
; DISABLED:       CALL	helper
; DISABLED:       RET
