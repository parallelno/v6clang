; RUN: llc -march=v6clang < %s | FileCheck %s

; Verify that a loop with pointer increment uses INX, not the 8-bit chain.
@buf = global [64 x i8] zeroinitializer

; CHECK-LABEL: clear_buf:
; CHECK:       INX D
define void @clear_buf() {
entry:
  br label %loop

loop:
  %p = phi ptr [ @buf, %entry ], [ %p.next, %loop ]
  store i8 0, ptr %p
  %p.next = getelementptr i8, ptr %p, i16 1
  %done = icmp eq ptr %p.next, getelementptr (i8, ptr @buf, i16 64)
  br i1 %done, label %exit, label %loop

exit:
  ret void
}
