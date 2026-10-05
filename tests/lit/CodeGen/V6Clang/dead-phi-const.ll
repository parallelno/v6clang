; RUN: llc -march=v6clang -O2 < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare i16 @bar(i16)

; Test 1: phi [0, entry] + br eq 0 (COND_Z, taken edge) → constant eliminated.
; The LXI 0 and register shuffle (MOV D,H; MOV E,L) should not appear.
define i16 @phi_zero_eq(i16 %x) {
; CHECK-LABEL: phi_zero_eq:
; CHECK-NOT:   LXI
; CHECK:       MOV A, H
; CHECK-NEXT:  ORA L
; CHECK-NEXT:  RZ
; CHECK:       JMP bar
entry:
  %cmp = icmp eq i16 %x, 0
  br i1 %cmp, label %merge, label %then

then:
  %y = call i16 @bar(i16 %x)
  br label %merge

merge:
  %result = phi i16 [ %y, %then ], [ 0, %entry ]
  ret i16 %result
}

; Test 2: phi [0, entry] + br ne 0 (COND_NZ, fallthrough edge) → constant eliminated.
define i16 @phi_zero_ne(i16 %x) {
; CHECK-LABEL: phi_zero_ne:
; CHECK-NOT:   LXI
; CHECK:       MOV A, H
; CHECK-NEXT:  ORA L
entry:
  %cmp = icmp ne i16 %x, 0
  br i1 %cmp, label %then, label %merge

then:
  %y = call i16 @bar(i16 %x)
  br label %merge

merge:
  %result = phi i16 [ %y, %then ], [ 0, %entry ]
  ret i16 %result
}

; Test 3: phi [42, entry] + br eq 42 → general constant case eliminated.
define i16 @phi_const42_eq(i16 %x) {
; CHECK-LABEL: phi_const42_eq:
; CHECK-NOT:   LXI{{.*}}42
; CHECK-NOT:   LXI{{.*}}0x2a
entry:
  %cmp = icmp eq i16 %x, 42
  br i1 %cmp, label %merge, label %then

then:
  %y = call i16 @bar(i16 %x)
  br label %merge

merge:
  %result = phi i16 [ %y, %then ], [ 42, %entry ]
  ret i16 %result
}

; Test 4 (negative): phi [0, entry] + br eq 1 → NO elimination (different constant).
define i16 @phi_different_const(i16 %x) {
; CHECK-LABEL: phi_different_const:
; CHECK:       LXI
entry:
  %cmp = icmp eq i16 %x, 1
  br i1 %cmp, label %merge, label %then

then:
  %y = call i16 @bar(i16 %x)
  br label %merge

merge:
  %result = phi i16 [ %y, %then ], [ 0, %entry ]
  ret i16 %result
}

; Test 5: verify disabled pass preserves old behavior.
; RUN: llc -march=v6clang -O2 -v6clang-disable-dead-phi-const < %s | FileCheck %s --check-prefix=DISABLED

; DISABLED-LABEL: phi_zero_eq:
; DISABLED:       LXI
