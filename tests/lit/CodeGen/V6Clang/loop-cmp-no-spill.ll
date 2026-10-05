; RUN: llc -march=v6clang -O2 < %s | FileCheck %s

; Verify that a two-pointer loop uses CMP for exit condition and does
; not spill registers to stack.
@src = global [100 x i8] zeroinitializer
@dst = global [100 x i8] zeroinitializer

define void @array_copy() {
entry:
  br label %loop

loop:
  %ps = phi ptr [ @src, %entry ], [ %ps.next, %loop ]
  %pd = phi ptr [ @dst, %entry ], [ %pd.next, %loop ]
  %val = load i8, ptr %ps
  store i8 %val, ptr %pd
  %ps.next = getelementptr i8, ptr %ps, i16 1
  %pd.next = getelementptr i8, ptr %pd, i16 1
  %done = icmp ne ptr %ps.next, getelementptr (i8, ptr @src, i16 100)
  br i1 %done, label %loop, label %exit

exit:
  ret void
}

; CHECK-LABEL: array_copy:
; The loop uses CMP-based comparison (not XOR).
; CHECK:       CMP
; CHECK:       JNZ
; CHECK:       CMP
; CHECK:       JNZ
; CHECK-NOT:   XRA
