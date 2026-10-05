; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

; O49 — Direct memory ALU/store ISel patterns. Verify that loaded-byte +
; ALU folds to the M-operand form rather than the split load + reg-ALU.

define i8 @add_m(i8 %a, ptr %p) {
; CHECK-LABEL: add_m:
; CHECK: ADD M
; CHECK-NOT: MOV {{.}}, M
  %b = load i8, ptr %p
  %r = add i8 %a, %b
  ret i8 %r
}

define i8 @sub_m(i8 %a, ptr %p) {
; CHECK-LABEL: sub_m:
; CHECK: SUB M
; CHECK-NOT: MOV {{.}}, M
  %b = load i8, ptr %p
  %r = sub i8 %a, %b
  ret i8 %r
}

define i8 @and_m(i8 %a, ptr %p) {
; CHECK-LABEL: and_m:
; CHECK: ANA M
; CHECK-NOT: MOV {{.}}, M
  %b = load i8, ptr %p
  %r = and i8 %a, %b
  ret i8 %r
}

define i8 @or_m(i8 %a, ptr %p) {
; CHECK-LABEL: or_m:
; CHECK: ORA M
; CHECK-NOT: MOV {{.}}, M
  %b = load i8, ptr %p
  %r = or i8 %a, %b
  ret i8 %r
}

define i8 @xor_m(i8 %a, ptr %p) {
; CHECK-LABEL: xor_m:
; CHECK: XRA M
; CHECK-NOT: MOV {{.}}, M
  %b = load i8, ptr %p
  %r = xor i8 %a, %b
  ret i8 %r
}

; CMP M fires only when the comparison result is consumed by a branch
; (i.e. the DAG uses V6ClangISD::CMP). Use a BR_CC idiom via select+br.
define void @cmp_m_br(i8 %a, ptr %p, ptr %sink) {
; CHECK-LABEL: cmp_m_br:
; CHECK: CMP M
; CHECK-NOT: MOV {{.}}, M
entry:
  %b = load i8, ptr %p
  %c = icmp eq i8 %a, %b
  br i1 %c, label %t, label %f
t:
  store i8 1, ptr %sink
  ret void
f:
  store i8 0, ptr %sink
  ret void
}

define void @store_imm(ptr %p) {
; CHECK-LABEL: store_imm:
; CHECK: MVI M, 0x42
; CHECK-NOT: MVI A, 0x42
  store i8 66, ptr %p
  ret void
}

define void @inc_m(ptr %p) {
; CHECK-LABEL: inc_m:
; CHECK: INR M
; CHECK-NOT: MOV {{.}}, M
  %v = load i8, ptr %p
  %n = add i8 %v, 1
  store i8 %n, ptr %p
  ret void
}

define void @dec_m(ptr %p) {
; CHECK-LABEL: dec_m:
; CHECK: DCR M
; CHECK-NOT: MOV {{.}}, M
  %v = load i8, ptr %p
  %n = add i8 %v, -1
  store i8 %n, ptr %p
  ret void
}
