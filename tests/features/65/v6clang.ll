; ModuleID = 'tests\features\65\v6clang.c'
source_filename = "tests\\features\\65\\v6clang.c"
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
!2 = !{i64 16759, i64 16782, i64 16851, i64 16921, i64 17016, i64 17038, i64 17074, i64 17131, i64 17194, i64 17270, i64 17292, i64 17328, i64 17364, i64 17400, i64 17465}
!3 = !{i64 18060, i64 18083, i64 18119, i64 18155, i64 18203, i64 18225, i64 18261, i64 18297, i64 18333, i64 18381, i64 18403, i64 18439, i64 18475, i64 18511}
!4 = !{i64 19075, i64 19098, i64 19174, i64 19239, i64 19311, i64 19383, i64 19405, i64 19467, i64 19503, i64 19539, i64 19587, i64 19609, i64 19645, i64 19681, i64 19717, i64 19793, i64 19815, i64 19876, i64 19912, i64 19948, i64 19996, i64 20018, i64 20054, i64 20090, i64 20126}
!5 = !{i64 20738, i64 20761, i64 20797, i64 20833, i64 20869, i64 20905, i64 20953, i64 20975, i64 21011, i64 21069, i64 21140, i64 21162, i64 21211, i64 21297, i64 21333, i64 21413, i64 21449, i64 21485, i64 21521, i64 21599, i64 21635, i64 21671, i64 21707, i64 21743, i64 21878, i64 21914, i64 21950, i64 21986, i64 22022, i64 22058, i64 22133, i64 22155, i64 22191, i64 22227, i64 22263, i64 22299, i64 22335, i64 22395}
!6 = !{i64 22764, i64 22793, i64 22835}
!7 = !{i64 23203, i64 23232, i64 23274, i64 23316, i64 23358}
!8 = !{i64 24080, i64 24109, i64 24177, i64 24238, i64 24302, i64 24369, i64 24411, i64 24479, i64 24543}
!9 = !{i64 25118, i64 25148, i64 25217, i64 25260, i64 25335, i64 25378, i64 25421, i64 25502, i64 25545, i64 25588, i64 25643, i64 25672, i64 25715, i64 25758, i64 25801, i64 25856, i64 25885, i64 25928, i64 26029, i64 26072, i64 26115, i64 26170, i64 26199, i64 26306, i64 26349, i64 26392, i64 26470, i64 26513, i64 26556, i64 26599, i64 26642, i64 26685, i64 26740, i64 26769, i64 26812, i64 26877, i64 26920, i64 26963, i64 27006, i64 27078}
!10 = !{i64 27409, i64 27432, i64 27468, i64 27504, i64 27540, i64 27576, i64 27612, i64 27648, i64 27684}
!11 = !{i64 28015, i64 28038, i64 28074, i64 28110, i64 28146, i64 28182, i64 28218, i64 28254, i64 28290}
!12 = !{i64 28664, i64 28694, i64 28737, i64 28820, i64 28863, i64 28906, i64 28949, i64 29004, i64 29033, i64 29076, i64 29119, i64 29162, i64 29217, i64 29246, i64 29289, i64 29332, i64 29375, i64 29418, i64 29473, i64 29502, i64 29545}
!13 = !{i64 29962, i64 29992, i64 30035, i64 30105, i64 30148, i64 30203, i64 30232, i64 30275, i64 30318, i64 30361, i64 30416, i64 30445, i64 30488, i64 30531, i64 30574, i64 30617, i64 30660, i64 30703, i64 30758, i64 30787, i64 30830}
!14 = !{i64 31235, i64 31258, i64 31294, i64 31330, i64 31366, i64 31402, i64 31450, i64 31472, i64 31508, i64 31544, i64 31592, i64 31614, i64 31662, i64 31684, i64 31720, i64 31756}
!15 = !{i64 32120, i64 32143, i64 32179, i64 32215, i64 32251, i64 32287, i64 32335, i64 32357, i64 32393, i64 32449, i64 32485, i64 32521, i64 32557, i64 32593, i64 32629, i64 32665, i64 32713, i64 32735, i64 32783, i64 32805, i64 32841, i64 32877}
!16 = !{i64 33245, i64 33268, i64 33304, i64 33340, i64 33376, i64 33412, i64 33460, i64 33482, i64 33518, i64 33554, i64 33613, i64 33649, i64 33728, i64 33764, i64 33800, i64 33836, i64 33872, i64 33920, i64 33942, i64 33990, i64 34012, i64 34079, i64 34115, i64 34151, i64 34220, i64 34256, i64 34292}
!17 = !{!18, !18, i64 0}
!18 = !{!"omnipotent char", !19, i64 0}
!19 = !{!"Simple C/C++ TBAA"}
!20 = distinct !{!20, !21}
!21 = !{!"llvm.loop.mustprogress"}
!22 = distinct !{!22, !21}
!23 = distinct !{!23, !21}
