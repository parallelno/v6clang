; RUN: llc -march=v6clang < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare dso_local void @sink(i8 noundef) local_unnamed_addr
declare dso_local i8   @op1(i8 noundef) local_unnamed_addr

; O80 shape 1: src already in A → single ORA A.
;
; CHECK-LABEL: shape_a:
; CHECK:       ORA A
; CHECK-NEXT:  JZ
; CHECK-NOT:   MOV A
; CHECK-NOT:   CPI
; CHECK-NOT:   INR
; CHECK-NOT:   DCR
define dso_local i8 @shape_a(i8 noundef %x) local_unnamed_addr {
  %t = icmp eq i8 %x, 0
  br i1 %t, label %z, label %nz
z:
  ret i8 0
nz:
  ret i8 1
}

; O80 shape 2: A dead at the test → XRA A; CMP src (preserves O38 path).
; %x == 0 is the only test, %y is consumed only on the non-zero arm but
; arrives in B; A is free at the test point.
;
; CHECK-LABEL: shape_a_dead:
; CHECK:       XRA A
; CHECK-NEXT:  CMP B
; CHECK-NOT:   INR
; CHECK-NOT:   DCR
; CHECK-NOT:   CPI
define dso_local i8 @shape_a_dead(i8 noundef %x, i8 noundef %y) local_unnamed_addr {
  %t = icmp eq i8 %y, 0
  br i1 %t, label %z, label %nz
z:
  ret i8 0
nz:
  %r = tail call i8 @op1(i8 noundef %y)
  ret i8 %r
}

; O80 shape 3: A holds a value that must survive the zero-test.
; @op1 returns into A; the cond byte (in B) must be tested without
; disturbing A. Expansion: INR B; DCR B (no MOV scratch,A; ...; MOV A,scratch).
;
; CHECK-LABEL: shape_a_live:
; CHECK:       CALL op1
; CHECK:       INR [[R:[BCDEHL]]]
; CHECK-NEXT:  DCR [[R]]
; CHECK-NOT:   MOV {{[BCDEHL]}}, A
; CHECK-NOT:   MOV A, {{[BCDEHL]}}
; CHECK-NOT:   CPI
define dso_local i8 @shape_a_live(i8 noundef %v, i8 noundef %cond) local_unnamed_addr {
  %a = tail call i8 @op1(i8 noundef %v)
  %t = icmp eq i8 %cond, 0
  br i1 %t, label %z, label %nz
z:
  ret i8 %a
nz:
  %a2 = add i8 %a, 1
  ret i8 %a2
}
