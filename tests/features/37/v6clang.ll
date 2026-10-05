; ModuleID = 'tests\features\37\v6clang.c'
source_filename = "tests\\features\\37\\v6clang.c"
target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@g_u16 = dso_local local_unnamed_addr global i16 0, align 1
@g_u8 = dso_local local_unnamed_addr global i8 0, align 1

; Function Attrs: norecurse nounwind
define dso_local i8 @a_spill_r8_reload(i8 noundef %0, i8 noundef %1) local_unnamed_addr #0 {
  %3 = tail call i8 @op1(i8 noundef %0) #2
  %4 = tail call i8 @op2(i8 noundef %1) #2
  %5 = add i8 %4, %3
  ret i8 %5
}

; Function Attrs: nocallback
declare dso_local i8 @op1(i8 noundef) local_unnamed_addr #1

; Function Attrs: nocallback
declare dso_local i8 @op2(i8 noundef) local_unnamed_addr #1

; Function Attrs: norecurse nounwind
define dso_local i8 @k2_i8(i8 noundef %0, i8 noundef %1, i8 noundef %2) local_unnamed_addr #0 {
  %4 = tail call i8 @op1(i8 noundef %0) #2
  %5 = tail call i8 @op2(i8 noundef %1) #2
  %6 = tail call i8 @op2(i8 noundef %2) #2
  %7 = shl i8 %4, 1
  %8 = add i8 %5, %7
  %9 = add i8 %8, %6
  ret i8 %9
}

; Function Attrs: norecurse nounwind
define dso_local i8 @multi_src_i8(i8 noundef %0, i8 noundef %1, i8 noundef %2) local_unnamed_addr #0 {
  %4 = icmp eq i8 %2, 0
  br i1 %4, label %7, label %5

5:                                                ; preds = %3
  %6 = tail call i8 @op1(i8 noundef %0) #2
  br label %9

7:                                                ; preds = %3
  %8 = tail call i8 @op2(i8 noundef %0) #2
  br label %9

9:                                                ; preds = %7, %5
  %10 = phi i8 [ %6, %5 ], [ %8, %7 ]
  %11 = tail call i8 @op2(i8 noundef %1) #2
  %12 = add i8 %11, %10
  ret i8 %12
}

; Function Attrs: norecurse nounwind
define dso_local void @mixed_widths(i16 noundef %0, i8 noundef %1) local_unnamed_addr #0 {
  %3 = trunc i16 %0 to i8
  %4 = tail call i8 @op1(i8 noundef %3) #2
  %5 = zext i8 %4 to i16
  %6 = add i16 %5, %0
  %7 = tail call i8 @op2(i8 noundef %1) #2
  %8 = tail call i8 @op2(i8 noundef %3) #2
  %9 = zext i8 %8 to i16
  %10 = tail call i8 @op1(i8 noundef %1) #2
  %11 = add i16 %6, %9
  store i16 %11, ptr @g_u16, align 1, !tbaa !2
  %12 = add i8 %10, %7
  store i8 %12, ptr @g_u8, align 1, !tbaa !6
  ret void
}

; Function Attrs: norecurse nounwind
define dso_local noundef i16 @main() local_unnamed_addr #0 {
  %1 = tail call i8 @op1(i8 noundef 17) #2
  %2 = tail call i8 @op2(i8 noundef 34) #2
  %3 = add i8 %2, %1
  %4 = tail call i8 @op1(i8 noundef 51) #2
  %5 = tail call i8 @op2(i8 noundef 68) #2
  %6 = tail call i8 @op2(i8 noundef 85) #2
  %7 = shl i8 %4, 1
  %8 = add i8 %5, %7
  %9 = add i8 %8, %6
  tail call void @use2(i8 noundef %3, i8 noundef %9) #2
  %10 = tail call i8 @op1(i8 noundef 102) #2
  %11 = tail call i8 @op2(i8 noundef 119) #2
  %12 = add i8 %11, %10
  tail call void @use2(i8 noundef %12, i8 noundef 0) #2
  %13 = tail call i8 @op1(i8 noundef -51) #2
  %14 = zext i8 %13 to i16
  %15 = add nuw nsw i16 %14, -21555
  %16 = tail call i8 @op2(i8 noundef -17) #2
  %17 = tail call i8 @op2(i8 noundef -51) #2
  %18 = zext i8 %17 to i16
  %19 = tail call i8 @op1(i8 noundef -17) #2
  %20 = add nuw nsw i16 %15, %18
  store i16 %20, ptr @g_u16, align 1, !tbaa !2
  %21 = add i8 %19, %16
  store i8 %21, ptr @g_u8, align 1, !tbaa !6
  ret i16 0
}

; Function Attrs: nocallback
declare dso_local void @use2(i8 noundef, i8 noundef) local_unnamed_addr #1

attributes #0 = { norecurse nounwind "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" }
attributes #1 = { nocallback "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" }
attributes #2 = { nobuiltin nocallback nounwind "no-builtins" }

!llvm.module.flags = !{!0}
!llvm.ident = !{!1}

!0 = !{i32 1, !"wchar_size", i32 2}
!1 = !{!"clang version 18.1.0rc (https://github.com/llvm/llvm-project.git 461274b81d8641eab64d494accddc81d7db8a09e)"}
!2 = !{!3, !3, i64 0}
!3 = !{!"int", !4, i64 0}
!4 = !{!"omnipotent char", !5, i64 0}
!5 = !{!"Simple C/C++ TBAA"}
!6 = !{!4, !4, i64 0}
