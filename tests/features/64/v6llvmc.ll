; ModuleID = 'tests\features\64\v6clang.c'
source_filename = "tests\\features\\64\\v6clang.c"
target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@flags = internal unnamed_addr global [200 x i8] zeroinitializer, align 1
@llvm.compiler.used = appending global [15 x ptr] [ptr @__ashlhi3, ptr @__ashrhi3, ptr @__divhi3, ptr @__divmodhi4, ptr @__lshrhi3, ptr @__modhi3, ptr @__mulhi3, ptr @__mulqi3, ptr @__udivhi3, ptr @__udivmodhi4, ptr @__umodhi3, ptr @__v6clang_mulqihi3, ptr @__v6clang_neg_de_body, ptr @__v6clang_neg_hl_body, ptr @__v6clang_udivmod16_body], section "llvm.metadata"

; Function Attrs: naked noinline nounwind
define internal i8 @__mulqi3(i8 noundef %0, i8 noundef %1) #0 {
  tail call void asm sideeffect "MOV  E, B           \0A\09MVI  D, 0           \0A\09LXI  H, 0           \0A\09MVI  B, 8           \0A1:                  \0A\09DAD  H              \0A\09RLC                 \0A\09JNC  2f             \0A\09DAD  D              \0A2:                  \0A\09DCR  B              \0A\09JNZ  1b             \0A\09MOV  A, L           \0A\09RET                 \0A\09", ""() #2, !srcloc !2
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__v6clang_mulqihi3(i8 noundef %0, i8 noundef %1) #0 {
  tail call void asm sideeffect "MOV  E, B           \0A\09MVI  D, 0           \0A\09LXI  H, 0           \0A\09MVI  B, 8           \0A1:                  \0A\09DAD  H              \0A\09RLC                 \0A\09JNC  2f             \0A\09DAD  D              \0A2:                  \0A\09DCR  B              \0A\09JNZ  1b             \0A\09RET                 \0A\09", ""() #2, !srcloc !3
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__mulhi3(i16 noundef %0, i16 noundef %1) #0 {
  tail call void asm sideeffect "XCHG                \0A\09MOV  A, H           \0A\09MOV  C, L           \0A\09LXI  H, 0           \0A\09MVI  B, 8           \0A1:                  \0A\09DAD  H              \0A\09RLC                 \0A\09JNC  2f             \0A\09DAD  D              \0A2:                  \0A\09DCR  B              \0A\09JNZ  1b             \0A\09MOV  A, C           \0A\09MVI  B, 8           \0A3:                  \0A\09DAD  H              \0A\09RLC                 \0A\09JNC  4f             \0A\09DAD  D              \0A4:                  \0A\09DCR  B              \0A\09JNZ  3b             \0A\09RET                 \0A\09", ""() #2, !srcloc !4
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal void @__v6clang_udivmod16_body() #0 {
  tail call void asm sideeffect "MOV  A, D           \0A\09ORA  E              \0A\09JNZ  1f             \0A\09LXI  H, 0xFFFF      \0A\09LXI  B, 0           \0A\09RET                 \0A1:                  \0A\09LXI  B, 0           \0A\09MVI  A, 16          \0A\09PUSH PSW            \0A2:                  \0A\09DAD  H              \0A\09MOV  A, C           \0A\09RAL                 \0A\09MOV  C, A           \0A\09MOV  A, B           \0A\09RAL                 \0A\09MOV  B, A           \0A\09MOV  A, C           \0A\09SUB  E              \0A\09MOV  A, B           \0A\09SBB  D              \0A\09JC   3f             \0A\09MOV  A, C           \0A\09SUB  E              \0A\09MOV  C, A           \0A\09MOV  A, B           \0A\09SBB  D              \0A\09MOV  B, A           \0A\09INX  H              \0A3:                  \0A\09POP  PSW            \0A\09DCR  A              \0A\09PUSH PSW            \0A\09JNZ  2b             \0A\09POP  PSW            \0A\09RET                 \0A\09", ""() #2, !srcloc !5
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__udivhi3(i16 noundef %0, i16 noundef %1) #0 {
  tail call void asm sideeffect "CALL __v6clang_udivmod16_body \0A\09RET                       \0A\09", ""() #2, !srcloc !6
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__umodhi3(i16 noundef %0, i16 noundef %1) #0 {
  tail call void asm sideeffect "CALL __v6clang_udivmod16_body \0A\09MOV  H, B                 \0A\09MOV  L, C                 \0A\09RET                       \0A\09", ""() #2, !srcloc !7
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__udivmodhi4(i16 noundef %0, i16 noundef %1, ptr noundef %2) #0 {
  tail call void asm sideeffect "PUSH B                    \0A\09CALL __v6clang_udivmod16_body \0A\09XTHL                      \0A\09MOV  M, C                 \0A\09INX  H                    \0A\09MOV  M, B                 \0A\09POP  H                    \0A\09RET                       \0A\09", ""() #2, !srcloc !8
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__divmodhi4(i16 noundef %0, i16 noundef %1, ptr noundef %2) #0 {
  tail call void asm sideeffect "PUSH B                     \0A\09MOV  A, H                  \0A\09PUSH PSW                   \0A\09MOV  A, H                  \0A\09XRA  D                     \0A\09PUSH PSW                   \0A\09MOV  A, H                  \0A\09ORA  A                     \0A\09JP   1f                    \0A\09CALL __v6clang_neg_hl_body     \0A1:                         \0A\09MOV  A, D                  \0A\09ORA  A                     \0A\09JP   2f                    \0A\09CALL __v6clang_neg_de_body     \0A2:                         \0A\09CALL __v6clang_udivmod16_body  \0A\09POP  PSW                   \0A\09ORA  A                     \0A\09JP   3f                    \0A\09CALL __v6clang_neg_hl_body     \0A3:                         \0A\09POP  PSW                   \0A\09ORA  A                     \0A\09JP   4f                    \0A\09MOV  A, C                  \0A\09CMA                        \0A\09MOV  C, A                  \0A\09MOV  A, B                  \0A\09CMA                        \0A\09MOV  B, A                  \0A\09INX  B                     \0A4:                         \0A\09XTHL                       \0A\09MOV  M, C                  \0A\09INX  H                     \0A\09MOV  M, B                  \0A\09POP  H                     \0A\09RET                        \0A\09", ""() #2, !srcloc !9
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal void @__v6clang_neg_hl_body() #0 {
  tail call void asm sideeffect "MOV  A, L           \0A\09CMA                 \0A\09MOV  L, A           \0A\09MOV  A, H           \0A\09CMA                 \0A\09MOV  H, A           \0A\09INX  H              \0A\09RET                 \0A\09", ""() #2, !srcloc !10
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal void @__v6clang_neg_de_body() #0 {
  tail call void asm sideeffect "MOV  A, E           \0A\09CMA                 \0A\09MOV  E, A           \0A\09MOV  A, D           \0A\09CMA                 \0A\09MOV  D, A           \0A\09INX  D              \0A\09RET                 \0A\09", ""() #2, !srcloc !11
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__divhi3(i16 noundef %0, i16 noundef %1) #0 {
  tail call void asm sideeffect "MOV  A, H                  \0A\09XRA  D                     \0A\09PUSH PSW                   \0A\09MOV  A, H                  \0A\09ORA  A                     \0A\09JP   1f                    \0A\09CALL __v6clang_neg_hl_body     \0A1:                         \0A\09MOV  A, D                  \0A\09ORA  A                     \0A\09JP   2f                    \0A\09CALL __v6clang_neg_de_body     \0A2:                         \0A\09CALL __v6clang_udivmod16_body  \0A\09POP  PSW                   \0A\09ORA  A                     \0A\09JP   3f                    \0A\09CALL __v6clang_neg_hl_body     \0A3:                         \0A\09RET                        \0A\09", ""() #2, !srcloc !12
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__modhi3(i16 noundef %0, i16 noundef %1) #0 {
  tail call void asm sideeffect "MOV  A, H                  \0A\09PUSH PSW                   \0A\09ORA  A                     \0A\09JP   1f                    \0A\09CALL __v6clang_neg_hl_body     \0A1:                         \0A\09MOV  A, D                  \0A\09ORA  A                     \0A\09JP   2f                    \0A\09CALL __v6clang_neg_de_body     \0A2:                         \0A\09CALL __v6clang_udivmod16_body  \0A\09MOV  H, B                  \0A\09MOV  L, C                  \0A\09POP  PSW                   \0A\09ORA  A                     \0A\09JP   3f                    \0A\09CALL __v6clang_neg_hl_body     \0A3:                         \0A\09RET                        \0A\09", ""() #2, !srcloc !13
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__ashlhi3(i16 noundef %0, i8 noundef %1) #0 {
  tail call void asm sideeffect "MOV  A, E           \0A\09ANI  0x0F           \0A\09JZ   2f             \0A\09CPI  16             \0A\09JNC  3f             \0A\09MOV  E, A           \0A1:                  \0A\09DAD  H              \0A\09DCR  E              \0A\09JNZ  1b             \0A2:                  \0A\09RET                 \0A3:                  \0A\09LXI  H, 0           \0A\09RET                 \0A\09", ""() #2, !srcloc !14
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__lshrhi3(i16 noundef %0, i8 noundef %1) #0 {
  tail call void asm sideeffect "MOV  A, E           \0A\09ANI  0x0F           \0A\09JZ   2f             \0A\09CPI  16             \0A\09JNC  3f             \0A\09MOV  E, A           \0A1:                  \0A\09ORA  A              \0A\09MOV  A, H           \0A\09RAR                 \0A\09MOV  H, A           \0A\09MOV  A, L           \0A\09RAR                 \0A\09MOV  L, A           \0A\09DCR  E              \0A\09JNZ  1b             \0A2:                  \0A\09RET                 \0A3:                  \0A\09LXI  H, 0           \0A\09RET                 \0A\09", ""() #2, !srcloc !15
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__ashrhi3(i16 noundef %0, i8 noundef %1) #0 {
  tail call void asm sideeffect "MOV  A, E           \0A\09ANI  0x0F           \0A\09JZ   2f             \0A\09CPI  16             \0A\09JNC  3f             \0A\09MOV  E, A           \0A1:                  \0A\09MOV  A, H           \0A\09RAL                 \0A\09MOV  A, H           \0A\09RAR                 \0A\09MOV  H, A           \0A\09MOV  A, L           \0A\09RAR                 \0A\09MOV  L, A           \0A\09DCR  E              \0A\09JNZ  1b             \0A2:                  \0A\09RET                 \0A3:                  \0A\09MOV  A, H           \0A\09RAL                 \0A\09SBB  A              \0A\09MOV  H, A           \0A\09MOV  L, A           \0A\09RET                 \0A\09", ""() #2, !srcloc !16
  unreachable
}

; Function Attrs: nofree norecurse nosync nounwind memory(readwrite, argmem: none, inaccessiblemem: none)
define dso_local i16 @sieve_count(i16 noundef %0) local_unnamed_addr #1 {
  %2 = icmp eq i16 %0, 0
  br i1 %2, label %35, label %3

3:                                                ; preds = %1, %3
  %4 = phi i16 [ %6, %3 ], [ 0, %1 ]
  %5 = getelementptr inbounds [200 x i8], ptr @flags, i16 0, i16 %4
  store i8 0, ptr %5, align 1, !tbaa !17
  %6 = add nuw i16 %4, 1
  %7 = icmp ult i16 %6, %0
  br i1 %7, label %3, label %8, !llvm.loop !20

8:                                                ; preds = %3
  %9 = add i16 %0, -2
  %10 = icmp ugt i16 %0, 4
  br i1 %10, label %11, label %35

11:                                               ; preds = %8, %28
  %12 = phi i16 [ %32, %28 ], [ 4, %8 ]
  %13 = phi i16 [ %29, %28 ], [ %9, %8 ]
  %14 = phi i16 [ %33, %28 ], [ 2, %8 ]
  %15 = getelementptr inbounds [200 x i8], ptr @flags, i16 0, i16 %14
  %16 = load i8, ptr %15, align 1, !tbaa !17
  %17 = icmp eq i8 %16, 0
  br i1 %17, label %18, label %28

18:                                               ; preds = %11, %18
  %19 = phi i16 [ %25, %18 ], [ %13, %11 ]
  %20 = phi i16 [ %26, %18 ], [ %12, %11 ]
  %21 = getelementptr inbounds [200 x i8], ptr @flags, i16 0, i16 %20
  %22 = load i8, ptr %21, align 1, !tbaa !17
  %23 = icmp eq i8 %22, 0
  %24 = sext i1 %23 to i16
  %25 = add i16 %19, %24
  store i8 1, ptr %21, align 1, !tbaa !17
  %26 = add i16 %20, %14
  %27 = icmp ult i16 %26, %0
  br i1 %27, label %18, label %28, !llvm.loop !22

28:                                               ; preds = %18, %11
  %29 = phi i16 [ %13, %11 ], [ %25, %18 ]
  %30 = shl i16 %14, 1
  %31 = or disjoint i16 %30, 1
  %32 = add i16 %31, %12
  %33 = add i16 %14, 1
  %34 = icmp ult i16 %32, %0
  br i1 %34, label %11, label %35, !llvm.loop !23

35:                                               ; preds = %28, %1, %8
  %36 = phi i16 [ %9, %8 ], [ -2, %1 ], [ %29, %28 ]
  ret i16 %36
}

; Function Attrs: nofree norecurse nosync nounwind memory(readwrite, argmem: none, inaccessiblemem: none)
define dso_local i16 @main() local_unnamed_addr #1 {
  br label %1

1:                                                ; preds = %1, %0
  %2 = phi i16 [ %4, %1 ], [ 0, %0 ]
  %3 = getelementptr inbounds [200 x i8], ptr @flags, i16 0, i16 %2
  store i8 0, ptr %3, align 1, !tbaa !17
  %4 = add nuw nsw i16 %2, 1
  %5 = icmp eq i16 %4, 200
  br i1 %5, label %6, label %1, !llvm.loop !20

6:                                                ; preds = %1, %23
  %7 = phi i16 [ %27, %23 ], [ 4, %1 ]
  %8 = phi i16 [ %24, %23 ], [ 198, %1 ]
  %9 = phi i16 [ %28, %23 ], [ 2, %1 ]
  %10 = getelementptr inbounds [200 x i8], ptr @flags, i16 0, i16 %9
  %11 = load i8, ptr %10, align 1, !tbaa !17
  %12 = icmp eq i8 %11, 0
  br i1 %12, label %13, label %23

13:                                               ; preds = %6, %13
  %14 = phi i16 [ %20, %13 ], [ %8, %6 ]
  %15 = phi i16 [ %21, %13 ], [ %7, %6 ]
  %16 = getelementptr inbounds [200 x i8], ptr @flags, i16 0, i16 %15
  %17 = load i8, ptr %16, align 1, !tbaa !17
  %18 = icmp eq i8 %17, 0
  %19 = sext i1 %18 to i16
  %20 = add i16 %14, %19
  store i8 1, ptr %16, align 1, !tbaa !17
  %21 = add i16 %15, %9
  %22 = icmp ult i16 %21, 200
  br i1 %22, label %13, label %23, !llvm.loop !22

23:                                               ; preds = %13, %6
  %24 = phi i16 [ %8, %6 ], [ %20, %13 ]
  %25 = shl nuw i16 %9, 1
  %26 = add nuw nsw i16 %7, 1
  %27 = add i16 %26, %25
  %28 = add nuw nsw i16 %9, 1
  %29 = icmp eq i16 %28, 15
  br i1 %29, label %30, label %6, !llvm.loop !23

30:                                               ; preds = %23
  %31 = and i16 %24, 255
  %32 = lshr i16 %24, 8
  %33 = xor i16 %31, %32
  ret i16 %33
}

attributes #0 = { naked noinline nounwind "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "v6clang-rt-helper" }
attributes #1 = { nofree norecurse nosync nounwind memory(readwrite, argmem: none, inaccessiblemem: none) "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" }
attributes #2 = { nounwind }

!llvm.module.flags = !{!0}
!llvm.ident = !{!1}

!0 = !{i32 1, !"wchar_size", i32 2}
!1 = !{!"clang version 18.1.0rc (https://github.com/llvm/llvm-project.git 461274b81d8641eab64d494accddc81d7db8a09e)"}
!2 = !{i64 16904, i64 16927, i64 16996, i64 17066, i64 17161, i64 17183, i64 17219, i64 17276, i64 17339, i64 17415, i64 17437, i64 17473, i64 17509, i64 17545, i64 17610}
!3 = !{i64 18205, i64 18228, i64 18264, i64 18300, i64 18348, i64 18370, i64 18406, i64 18442, i64 18478, i64 18526, i64 18548, i64 18584, i64 18620, i64 18656}
!4 = !{i64 19220, i64 19243, i64 19319, i64 19384, i64 19456, i64 19528, i64 19550, i64 19612, i64 19648, i64 19684, i64 19732, i64 19754, i64 19790, i64 19826, i64 19862, i64 19938, i64 19960, i64 20021, i64 20057, i64 20093, i64 20141, i64 20163, i64 20199, i64 20235, i64 20271}
!5 = !{i64 20883, i64 20906, i64 20942, i64 20978, i64 21014, i64 21050, i64 21098, i64 21120, i64 21156, i64 21214, i64 21285, i64 21307, i64 21356, i64 21442, i64 21478, i64 21558, i64 21594, i64 21630, i64 21666, i64 21744, i64 21780, i64 21816, i64 21852, i64 21888, i64 22023, i64 22059, i64 22095, i64 22131, i64 22167, i64 22203, i64 22278, i64 22300, i64 22336, i64 22372, i64 22408, i64 22444, i64 22480, i64 22540}
!6 = !{i64 22909, i64 22938, i64 22980}
!7 = !{i64 23348, i64 23377, i64 23419, i64 23461, i64 23503}
!8 = !{i64 24225, i64 24254, i64 24322, i64 24383, i64 24447, i64 24514, i64 24556, i64 24624, i64 24688}
!9 = !{i64 25263, i64 25293, i64 25362, i64 25405, i64 25480, i64 25523, i64 25566, i64 25647, i64 25690, i64 25733, i64 25788, i64 25817, i64 25860, i64 25903, i64 25946, i64 26001, i64 26030, i64 26073, i64 26174, i64 26217, i64 26260, i64 26315, i64 26344, i64 26451, i64 26494, i64 26537, i64 26615, i64 26658, i64 26701, i64 26744, i64 26787, i64 26830, i64 26885, i64 26914, i64 26957, i64 27022, i64 27065, i64 27108, i64 27151, i64 27223}
!10 = !{i64 27554, i64 27577, i64 27613, i64 27649, i64 27685, i64 27721, i64 27757, i64 27793, i64 27829}
!11 = !{i64 28160, i64 28183, i64 28219, i64 28255, i64 28291, i64 28327, i64 28363, i64 28399, i64 28435}
!12 = !{i64 28809, i64 28839, i64 28882, i64 28965, i64 29008, i64 29051, i64 29094, i64 29149, i64 29178, i64 29221, i64 29264, i64 29307, i64 29362, i64 29391, i64 29434, i64 29477, i64 29520, i64 29563, i64 29618, i64 29647, i64 29690}
!13 = !{i64 30107, i64 30137, i64 30180, i64 30250, i64 30293, i64 30348, i64 30377, i64 30420, i64 30463, i64 30506, i64 30561, i64 30590, i64 30633, i64 30676, i64 30719, i64 30762, i64 30805, i64 30848, i64 30903, i64 30932, i64 30975}
!14 = !{i64 31380, i64 31403, i64 31439, i64 31475, i64 31511, i64 31547, i64 31595, i64 31617, i64 31653, i64 31689, i64 31737, i64 31759, i64 31807, i64 31829, i64 31865, i64 31901}
!15 = !{i64 32265, i64 32288, i64 32324, i64 32360, i64 32396, i64 32432, i64 32480, i64 32502, i64 32538, i64 32594, i64 32630, i64 32666, i64 32702, i64 32738, i64 32774, i64 32810, i64 32858, i64 32880, i64 32928, i64 32950, i64 32986, i64 33022}
!16 = !{i64 33390, i64 33413, i64 33449, i64 33485, i64 33521, i64 33557, i64 33605, i64 33627, i64 33663, i64 33699, i64 33758, i64 33794, i64 33873, i64 33909, i64 33945, i64 33981, i64 34017, i64 34065, i64 34087, i64 34135, i64 34157, i64 34224, i64 34260, i64 34296, i64 34365, i64 34401, i64 34437}
!17 = !{!18, !18, i64 0}
!18 = !{!"omnipotent char", !19, i64 0}
!19 = !{!"Simple C/C++ TBAA"}
!20 = distinct !{!20, !21}
!21 = !{!"llvm.loop.mustprogress"}
!22 = distinct !{!22, !21}
!23 = distinct !{!23, !21}
