; RUN: llc -march=v6clang -O2 < %s | FileCheck %s

@src = global [100 x i8] zeroinitializer
@dst = global [100 x i8] zeroinitializer

; Verify the array-copy loop uses MVI+CMP instead of LXI+MOV+CMP.
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
  %done = icmp eq ptr %ps.next, getelementptr (i8, ptr @src, i16 100)
  br i1 %done, label %exit, label %loop

exit:
  ret void
}

; CHECK-LABEL: array_copy:
; The comparison constant should use MVI+CMP, not LXI+MOV+CMP.
; The optimizer may use either pointer comparison (MVI A, <(src+100))
; or integer counter comparison (MVI A, 0x64). Either way, MVI+CMP is used.
; The high-byte half of an i16 counter compare loads a zero into A —
; O55 narrows that to `XRA A` since FLAGS are dead until the next CMP.
; CHECK:      {{\.LBB.*:}}
; CHECK:      MVI A,
; CHECK:      CMP
; CHECK:      {{(MVI A,|XRA A)}}
; CHECK:      CMP
