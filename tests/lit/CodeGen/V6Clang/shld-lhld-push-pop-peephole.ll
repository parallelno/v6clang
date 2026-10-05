; RUN: llc -march=v6clang -O2 -mv6clang-no-spill-patched-reload --enable-deferred-spilling < %s | FileCheck %s

; Test O43: SHLD/LHLD to PUSH/POP peephole (static stack spill shortening).
;
; Positive test: verify that close SHLD/LHLD pairs with no SP-affecting
; instructions between them are replaced with PUSH HL / POP HL.
; The +2 slot (arr1_ptr) has XCHG between SHLD/LHLD so it stays as-is.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@arr1 = dso_local global [200 x i16] zeroinitializer, align 1
@arr2 = dso_local global [200 x i16] zeroinitializer, align 1

; CHECK-LABEL: sumarray:
; The loop body: first spill/reload pair at __v6clang_ss.sumarray+0 converted to PUSH/POP.
; CHECK:       .LBB0_1:
; CHECK:       PUSH	H
; The +2 slot: SHLD stays (long range with PUSH/POP between SHLD and LHLD).
; CHECK:       SHLD	__v6clang_ss.sumarray+2
; CHECK:       POP	H
; Second converted pair:
; CHECK:       PUSH	H
; CHECK:       POP	H
; The +2 slot reload stays:
; CHECK:       LHLD	__v6clang_ss.sumarray+2
define dso_local i16 @sumarray() local_unnamed_addr #0 {
  br label %2

1:
  ret i16 %10

2:
  %3 = phi i16 [ 0, %0 ], [ %11, %2 ]
  %4 = phi i16 [ 0, %0 ], [ %10, %2 ]
  %5 = getelementptr inbounds [200 x i16], ptr @arr1, i16 0, i16 %3
  %6 = load volatile i16, ptr %5, align 1
  %7 = getelementptr inbounds [200 x i16], ptr @arr2, i16 0, i16 %3
  %8 = load volatile i16, ptr %7, align 1
  %9 = add i16 %6, %4
  %10 = add i16 %9, %8
  %11 = add nuw nsw i16 %3, 1
  %12 = icmp eq i16 %11, 200
  br i1 %12, label %1, label %2
}

attributes #0 = { nofree norecurse nounwind memory(readwrite, argmem: none) "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" }
