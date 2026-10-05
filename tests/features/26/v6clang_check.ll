; ModuleID = 'tests\features\26\v6clang.c'
source_filename = "tests\\features\\26\\v6clang.c"
target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@arr1 = dso_local global [100 x i16] zeroinitializer, align 1
@arr2 = dso_local global [100 x i16] zeroinitializer, align 1

; Function Attrs: nofree norecurse nounwind memory(readwrite, argmem: none)
define dso_local i16 @sumarray() local_unnamed_addr #0 {
  br label %2

1:                                                ; preds = %2
  ret i16 %10

2:                                                ; preds = %0, %2
  %3 = phi i16 [ 0, %0 ], [ %11, %2 ]
  %4 = phi i16 [ 0, %0 ], [ %10, %2 ]
  %5 = getelementptr inbounds [100 x i16], ptr @arr1, i16 0, i16 %3
  %6 = load volatile i16, ptr %5, align 1, !tbaa !2
  %7 = getelementptr inbounds [100 x i16], ptr @arr2, i16 0, i16 %3
  %8 = load volatile i16, ptr %7, align 1, !tbaa !2
  %9 = add i16 %6, %4
  %10 = add i16 %9, %8
  %11 = add nuw nsw i16 %3, 1
  %12 = icmp eq i16 %11, 100
  br i1 %12, label %1, label %2, !llvm.loop !6
}

; Function Attrs: nofree norecurse nounwind memory(readwrite, argmem: none)
define dso_local i16 @main() local_unnamed_addr #0 {
  br label %1

1:                                                ; preds = %1, %0
  %2 = phi i16 [ 0, %0 ], [ %10, %1 ]
  %3 = phi i16 [ 0, %0 ], [ %9, %1 ]
  %4 = getelementptr inbounds [100 x i16], ptr @arr1, i16 0, i16 %2
  %5 = load volatile i16, ptr %4, align 1, !tbaa !2
  %6 = getelementptr inbounds [100 x i16], ptr @arr2, i16 0, i16 %2
  %7 = load volatile i16, ptr %6, align 1, !tbaa !2
  %8 = add i16 %5, %3
  %9 = add i16 %8, %7
  %10 = add nuw nsw i16 %2, 1
  %11 = icmp eq i16 %10, 100
  br i1 %11, label %12, label %1, !llvm.loop !6

12:                                               ; preds = %1
  ret i16 %9
}

attributes #0 = { nofree norecurse nounwind memory(readwrite, argmem: none) "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" }

!llvm.module.flags = !{!0}
!llvm.ident = !{!1}

!0 = !{i32 1, !"wchar_size", i32 2}
!1 = !{!"clang version 18.1.0rc (https://github.com/llvm/llvm-project.git 461274b81d8641eab64d494accddc81d7db8a09e)"}
!2 = !{!3, !3, i64 0}
!3 = !{!"int", !4, i64 0}
!4 = !{!"omnipotent char", !5, i64 0}
!5 = !{!"Simple C/C++ TBAA"}
!6 = distinct !{!6, !7}
!7 = !{!"llvm.loop.mustprogress"}
