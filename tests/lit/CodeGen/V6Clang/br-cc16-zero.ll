; RUN: llc -march=v6clang -O2 < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; Test that NE comparison against zero uses MOV+ORA (O27 fast path).
define void @ne_zero(i16 %x) {
; CHECK-LABEL: ne_zero:
; CHECK:       MOV A,
; CHECK-NEXT:  ORA
; CHECK-NEXT:  {{J|R}}
; CHECK-NOT:   MVI A, 0
entry:
  %cmp = icmp ne i16 %x, 0
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

; Test that EQ comparison against zero uses MOV+ORA (O27 fast path).
define void @eq_zero(i16 %x) {
; CHECK-LABEL: eq_zero:
; CHECK:       MOV A,
; CHECK-NEXT:  ORA
; CHECK-NEXT:  {{J|R}}
; CHECK-NOT:   MVI A, 0
entry:
  %cmp = icmp eq i16 %x, 0
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

; Test that NE comparison against non-zero integer still uses MVI+CMP.
define void @ne_nonzero(i16 %x) {
; CHECK-LABEL: ne_nonzero:
; CHECK:       MVI A,
; CHECK:       CMP
entry:
  %cmp = icmp ne i16 %x, 42
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

; Test that null pointer check uses MOV+ORA (O27 fast path).
define void @ne_null_ptr(ptr %p) {
; CHECK-LABEL: ne_null_ptr:
; CHECK:       MOV A,
; CHECK-NEXT:  ORA
; CHECK-NEXT:  {{J|R}}
; CHECK-NOT:   MVI A, 0
entry:
  %cmp = icmp ne ptr %p, null
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

; Test that NE comparison against a global address does NOT use O27 zero path.
@arr = global [100 x i8] zeroinitializer
define void @ne_global(ptr %p) {
; CHECK-LABEL: ne_global:
; CHECK:       CMP
; CHECK-NOT:   ORA
entry:
  %end = getelementptr i8, ptr @arr, i16 100
  %cmp = icmp ne ptr %p, %end
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

declare void @use()
