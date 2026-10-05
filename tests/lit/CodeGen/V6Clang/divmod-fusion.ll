; Verify O70 Step 3.5: udiv+urem on same operands fuses into ONE __udivmodhi4 call.
; RUN: llc -mtriple=i8080-unknown-v6clang < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

define void @divmod_pair(i16 %a, i16 %b, ptr %qp, ptr %rp) {
; CHECK-LABEL: divmod_pair:
; CHECK:     CALL __udivmodhi4
; CHECK-NOT: CALL __udivhi3
; CHECK-NOT: CALL __umodhi3
  %q = udiv i16 %a, %b
  %r = urem i16 %a, %b
  store i16 %q, ptr %qp
  store i16 %r, ptr %rp
  ret void
}

define void @sdivmod_pair(i16 %a, i16 %b, ptr %qp, ptr %rp) {
; CHECK-LABEL: sdivmod_pair:
; CHECK:     CALL __divmodhi4
; CHECK-NOT: CALL __divhi3
; CHECK-NOT: CALL __modhi3
  %q = sdiv i16 %a, %b
  %r = srem i16 %a, %b
  store i16 %q, ptr %qp
  store i16 %r, ptr %rp
  ret void
}
