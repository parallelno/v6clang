; RUN: llc -march=v6clang -O2 -v6clang-disable-alloca-promote -v6clang-disable-static-stack-alloc < %s | FileCheck %s

; Test O44: adjacent XCHG cancellation peephole.
; Verify no XCHG; XCHG adjacent pairs appear in the output.
; XchgOpt converts MOV pairs to XCHG; O44 cancels any resulting
; adjacent XCHG pairs (both in peephole and in XchgOpt cleanup).

@arr1 = dso_local global [100 x i16] zeroinitializer, align 1
@arr2 = dso_local global [100 x i16] zeroinitializer, align 1

; CHECK-LABEL: sumarray:
;   Epilogue: after frame teardown, single XCHG before RET (no XCHG; XCHG).
;   Without O44, XchgOpt creates XCHG; XCHG; ... ; XCHG; RET here.
; CHECK:       ; %bb.2:
; CHECK:       SPHL
; CHECK-NEXT:  XCHG
; CHECK-NEXT:  RET
define dso_local i16 @sumarray() local_unnamed_addr {
  br label %2

1:
  ret i16 %10

2:
  %3 = phi i16 [ 0, %0 ], [ %11, %2 ]
  %4 = phi i16 [ 0, %0 ], [ %10, %2 ]
  %5 = getelementptr inbounds [100 x i16], ptr @arr1, i16 0, i16 %3
  %6 = load volatile i16, ptr %5, align 1
  %7 = getelementptr inbounds [100 x i16], ptr @arr2, i16 0, i16 %3
  %8 = load volatile i16, ptr %7, align 1
  %9 = add i16 %6, %4
  %10 = add i16 %9, %8
  %11 = add nuw nsw i16 %3, 1
  %12 = icmp eq i16 %11, 100
  br i1 %12, label %1, label %2
}
