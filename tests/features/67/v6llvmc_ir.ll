; ModuleID = 'tests\features\67\v6clang.c'
source_filename = "tests\\features\\67\\v6clang.c"
target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@llvm.compiler.used = appending global [15 x ptr] [ptr @__ashlhi3, ptr @__ashrhi3, ptr @__divhi3, ptr @__divmodhi4, ptr @__lshrhi3, ptr @__modhi3, ptr @__mulhi3, ptr @__mulqi3, ptr @__udivhi3, ptr @__udivmodhi4, ptr @__umodhi3, ptr @__v6clang_mulqihi3, ptr @__v6clang_neg_de_body, ptr @__v6clang_neg_hl_body, ptr @__v6clang_udivmod16_body], section "llvm.metadata"

; Function Attrs: naked noinline nounwind
define internal i8 @__mulqi3(i8 noundef %0, i8 noundef %1) #0 {
  tail call void asm sideeffect "MOV  E, B           \0A\09MVI  D, 0           \0A\09LXI  H, 0           \0A\09MVI  B, 8           \0A1:                  \0A\09DAD  H              \0A\09RLC                 \0A\09JNC  2f             \0A\09DAD  D              \0A2:                  \0A\09DCR  B              \0A\09JNZ  1b             \0A\09MOV  A, L           \0A\09RET                 \0A\09", ""() #4, !srcloc !2
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__v6clang_mulqihi3(i8 noundef %0, i8 noundef %1) #0 {
  tail call void asm sideeffect "MOV  E, B           \0A\09MVI  D, 0           \0A\09LXI  H, 0           \0A\09MVI  B, 8           \0A1:                  \0A\09DAD  H              \0A\09RLC                 \0A\09JNC  2f             \0A\09DAD  D              \0A2:                  \0A\09DCR  B              \0A\09JNZ  1b             \0A\09RET                 \0A\09", ""() #4, !srcloc !3
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__mulhi3(i16 noundef %0, i16 noundef %1) #0 {
  tail call void asm sideeffect "XCHG                \0A\09MOV  A, H           \0A\09MOV  C, L           \0A\09LXI  H, 0           \0A\09MVI  B, 8           \0A1:                  \0A\09DAD  H              \0A\09RLC                 \0A\09JNC  2f             \0A\09DAD  D              \0A2:                  \0A\09DCR  B              \0A\09JNZ  1b             \0A\09MOV  A, C           \0A\09MVI  B, 8           \0A3:                  \0A\09DAD  H              \0A\09RLC                 \0A\09JNC  4f             \0A\09DAD  D              \0A4:                  \0A\09DCR  B              \0A\09JNZ  3b             \0A\09RET                 \0A\09", ""() #4, !srcloc !4
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal void @__v6clang_udivmod16_body() #0 {
  tail call void asm sideeffect "MOV  A, D           \0A\09ORA  E              \0A\09JNZ  1f             \0A\09LXI  H, 0xFFFF      \0A\09LXI  B, 0           \0A\09RET                 \0A1:                  \0A\09LXI  B, 0           \0A\09MVI  A, 16          \0A\09PUSH PSW            \0A2:                  \0A\09DAD  H              \0A\09MOV  A, C           \0A\09RAL                 \0A\09MOV  C, A           \0A\09MOV  A, B           \0A\09RAL                 \0A\09MOV  B, A           \0A\09MOV  A, C           \0A\09SUB  E              \0A\09MOV  A, B           \0A\09SBB  D              \0A\09JC   3f             \0A\09MOV  A, C           \0A\09SUB  E              \0A\09MOV  C, A           \0A\09MOV  A, B           \0A\09SBB  D              \0A\09MOV  B, A           \0A\09INX  H              \0A3:                  \0A\09POP  PSW            \0A\09DCR  A              \0A\09PUSH PSW            \0A\09JNZ  2b             \0A\09POP  PSW            \0A\09RET                 \0A\09", ""() #4, !srcloc !5
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__udivhi3(i16 noundef %0, i16 noundef %1) #0 {
  tail call void asm sideeffect "CALL __v6clang_udivmod16_body \0A\09RET                       \0A\09", ""() #4, !srcloc !6
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__umodhi3(i16 noundef %0, i16 noundef %1) #0 {
  tail call void asm sideeffect "CALL __v6clang_udivmod16_body \0A\09MOV  H, B                 \0A\09MOV  L, C                 \0A\09RET                       \0A\09", ""() #4, !srcloc !7
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__udivmodhi4(i16 noundef %0, i16 noundef %1, ptr noundef %2) #0 {
  tail call void asm sideeffect "PUSH B                    \0A\09CALL __v6clang_udivmod16_body \0A\09XTHL                      \0A\09MOV  M, C                 \0A\09INX  H                    \0A\09MOV  M, B                 \0A\09POP  H                    \0A\09RET                       \0A\09", ""() #4, !srcloc !8
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__divmodhi4(i16 noundef %0, i16 noundef %1, ptr noundef %2) #0 {
  tail call void asm sideeffect "PUSH B                     \0A\09MOV  A, H                  \0A\09PUSH PSW                   \0A\09MOV  A, H                  \0A\09XRA  D                     \0A\09PUSH PSW                   \0A\09MOV  A, H                  \0A\09ORA  A                     \0A\09JP   1f                    \0A\09CALL __v6clang_neg_hl_body     \0A1:                         \0A\09MOV  A, D                  \0A\09ORA  A                     \0A\09JP   2f                    \0A\09CALL __v6clang_neg_de_body     \0A2:                         \0A\09CALL __v6clang_udivmod16_body  \0A\09POP  PSW                   \0A\09ORA  A                     \0A\09JP   3f                    \0A\09CALL __v6clang_neg_hl_body     \0A3:                         \0A\09POP  PSW                   \0A\09ORA  A                     \0A\09JP   4f                    \0A\09MOV  A, C                  \0A\09CMA                        \0A\09MOV  C, A                  \0A\09MOV  A, B                  \0A\09CMA                        \0A\09MOV  B, A                  \0A\09INX  B                     \0A4:                         \0A\09XTHL                       \0A\09MOV  M, C                  \0A\09INX  H                     \0A\09MOV  M, B                  \0A\09POP  H                     \0A\09RET                        \0A\09", ""() #4, !srcloc !9
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal void @__v6clang_neg_hl_body() #0 {
  tail call void asm sideeffect "MOV  A, L           \0A\09CMA                 \0A\09MOV  L, A           \0A\09MOV  A, H           \0A\09CMA                 \0A\09MOV  H, A           \0A\09INX  H              \0A\09RET                 \0A\09", ""() #4, !srcloc !10
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal void @__v6clang_neg_de_body() #0 {
  tail call void asm sideeffect "MOV  A, E           \0A\09CMA                 \0A\09MOV  E, A           \0A\09MOV  A, D           \0A\09CMA                 \0A\09MOV  D, A           \0A\09INX  D              \0A\09RET                 \0A\09", ""() #4, !srcloc !11
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__divhi3(i16 noundef %0, i16 noundef %1) #0 {
  tail call void asm sideeffect "MOV  A, H                  \0A\09XRA  D                     \0A\09PUSH PSW                   \0A\09MOV  A, H                  \0A\09ORA  A                     \0A\09JP   1f                    \0A\09CALL __v6clang_neg_hl_body     \0A1:                         \0A\09MOV  A, D                  \0A\09ORA  A                     \0A\09JP   2f                    \0A\09CALL __v6clang_neg_de_body     \0A2:                         \0A\09CALL __v6clang_udivmod16_body  \0A\09POP  PSW                   \0A\09ORA  A                     \0A\09JP   3f                    \0A\09CALL __v6clang_neg_hl_body     \0A3:                         \0A\09RET                        \0A\09", ""() #4, !srcloc !12
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__modhi3(i16 noundef %0, i16 noundef %1) #0 {
  tail call void asm sideeffect "MOV  A, H                  \0A\09PUSH PSW                   \0A\09ORA  A                     \0A\09JP   1f                    \0A\09CALL __v6clang_neg_hl_body     \0A1:                         \0A\09MOV  A, D                  \0A\09ORA  A                     \0A\09JP   2f                    \0A\09CALL __v6clang_neg_de_body     \0A2:                         \0A\09CALL __v6clang_udivmod16_body  \0A\09MOV  H, B                  \0A\09MOV  L, C                  \0A\09POP  PSW                   \0A\09ORA  A                     \0A\09JP   3f                    \0A\09CALL __v6clang_neg_hl_body     \0A3:                         \0A\09RET                        \0A\09", ""() #4, !srcloc !13
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__ashlhi3(i16 noundef %0, i8 noundef %1) #0 {
  tail call void asm sideeffect "MOV  A, E           \0A\09ANI  0x0F           \0A\09JZ   2f             \0A\09CPI  16             \0A\09JNC  3f             \0A\09MOV  E, A           \0A1:                  \0A\09DAD  H              \0A\09DCR  E              \0A\09JNZ  1b             \0A2:                  \0A\09RET                 \0A3:                  \0A\09LXI  H, 0           \0A\09RET                 \0A\09", ""() #4, !srcloc !14
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__lshrhi3(i16 noundef %0, i8 noundef %1) #0 {
  tail call void asm sideeffect "MOV  A, E           \0A\09ANI  0x0F           \0A\09JZ   2f             \0A\09CPI  16             \0A\09JNC  3f             \0A\09MOV  E, A           \0A1:                  \0A\09ORA  A              \0A\09MOV  A, H           \0A\09RAR                 \0A\09MOV  H, A           \0A\09MOV  A, L           \0A\09RAR                 \0A\09MOV  L, A           \0A\09DCR  E              \0A\09JNZ  1b             \0A2:                  \0A\09RET                 \0A3:                  \0A\09LXI  H, 0           \0A\09RET                 \0A\09", ""() #4, !srcloc !15
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__ashrhi3(i16 noundef %0, i8 noundef %1) #0 {
  tail call void asm sideeffect "MOV  A, E           \0A\09ANI  0x0F           \0A\09JZ   2f             \0A\09CPI  16             \0A\09JNC  3f             \0A\09MOV  E, A           \0A1:                  \0A\09MOV  A, H           \0A\09RAL                 \0A\09MOV  A, H           \0A\09RAR                 \0A\09MOV  H, A           \0A\09MOV  A, L           \0A\09RAR                 \0A\09MOV  L, A           \0A\09DCR  E              \0A\09JNZ  1b             \0A2:                  \0A\09RET                 \0A3:                  \0A\09MOV  A, H           \0A\09RAL                 \0A\09SBB  A              \0A\09MOV  H, A           \0A\09MOV  L, A           \0A\09RET                 \0A\09", ""() #4, !srcloc !16
  unreachable
}

; Function Attrs: nofree norecurse nosync nounwind memory(none)
define dso_local i16 @iter_xor_mix(i8 noundef %0) local_unnamed_addr #1 {
  %2 = zext i8 %0 to i16
  br label %3

3:                                                ; preds = %1, %3
  %4 = phi i16 [ 0, %1 ], [ %8, %3 ]
  %5 = phi i16 [ %2, %1 ], [ %7, %3 ]
  %6 = xor i16 %4, %5
  %7 = add i16 %6, %5
  %8 = add nuw nsw i16 %4, 1
  %9 = icmp eq i16 %8, 64
  br i1 %9, label %10, label %3, !llvm.loop !17

10:                                               ; preds = %3
  ret i16 %7
}

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #2

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #2

; Function Attrs: nofree norecurse nosync nounwind memory(none)
define dso_local i16 @iter_xor_next(i8 noundef %0) local_unnamed_addr #1 {
  %2 = zext i8 %0 to i16
  br label %3

3:                                                ; preds = %1, %3
  %4 = phi i16 [ 0, %1 ], [ %6, %3 ]
  %5 = phi i16 [ %2, %1 ], [ %8, %3 ]
  %6 = add nuw nsw i16 %4, 1
  %7 = xor i16 %6, %5
  %8 = add i16 %7, %5
  %9 = icmp eq i16 %6, 64
  br i1 %9, label %10, label %3, !llvm.loop !19

10:                                               ; preds = %3
  ret i16 %8
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: read)
define dso_local i16 @weighted_sum(ptr nocapture noundef readonly %0) local_unnamed_addr #3 {
  br label %2

2:                                                ; preds = %1, %2
  %3 = phi i16 [ 0, %1 ], [ %10, %2 ]
  %4 = phi i16 [ 0, %1 ], [ %9, %2 ]
  %5 = getelementptr inbounds i8, ptr %0, i16 %3
  %6 = load i8, ptr %5, align 1, !tbaa !20
  %7 = zext i8 %6 to i16
  %8 = add i16 %3, %4
  %9 = add i16 %8, %7
  %10 = add nuw nsw i16 %3, 1
  %11 = icmp eq i16 %10, 64
  br i1 %11, label %12, label %2, !llvm.loop !23

12:                                               ; preds = %2
  ret i16 %9
}

; Function Attrs: nofree norecurse nosync nounwind memory(none)
define dso_local i16 @main() local_unnamed_addr #1 {
  %1 = alloca [64 x i8], align 1
  call void @llvm.lifetime.start.p0(i64 64, ptr nonnull %1) #4
  br label %15

2:                                                ; preds = %15, %2
  %3 = phi i16 [ %10, %2 ], [ 0, %15 ]
  %4 = phi i16 [ %9, %2 ], [ 0, %15 ]
  %5 = getelementptr inbounds i8, ptr %1, i16 %3
  %6 = load i8, ptr %5, align 1, !tbaa !20
  %7 = zext i8 %6 to i16
  %8 = add i16 %4, %3
  %9 = add i16 %8, %7
  %10 = add nuw nsw i16 %3, 1
  %11 = icmp eq i16 %10, 64
  br i1 %11, label %12, label %2, !llvm.loop !23

12:                                               ; preds = %2
  %13 = add i16 %9, 125
  %14 = and i16 %13, 255
  call void @llvm.lifetime.end.p0(i64 64, ptr nonnull %1) #4
  ret i16 %14

15:                                               ; preds = %0, %15
  %16 = phi i8 [ 0, %0 ], [ %19, %15 ]
  %17 = zext nneg i8 %16 to i16
  %18 = getelementptr inbounds [64 x i8], ptr %1, i16 0, i16 %17
  store i8 %16, ptr %18, align 1, !tbaa !20
  %19 = add nuw nsw i8 %16, 1
  %20 = icmp eq i8 %19, 64
  br i1 %20, label %2, label %15, !llvm.loop !24
}

attributes #0 = { naked noinline nounwind "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "v6clang-rt-helper" }
attributes #1 = { nofree norecurse nosync nounwind memory(none) "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" }
attributes #2 = { mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #3 = { nofree norecurse nosync nounwind memory(argmem: read) "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" }
attributes #4 = { nounwind }

!llvm.module.flags = !{!0}
!llvm.ident = !{!1}

!0 = !{i32 1, !"wchar_size", i32 2}
!1 = !{!"clang version 18.1.0rc (https://github.com/llvm/llvm-project.git 461274b81d8641eab64d494accddc81d7db8a09e)"}
!2 = !{i64 17814, i64 17837, i64 17906, i64 17976, i64 18071, i64 18093, i64 18129, i64 18186, i64 18249, i64 18325, i64 18347, i64 18383, i64 18419, i64 18455, i64 18520}
!3 = !{i64 19115, i64 19138, i64 19174, i64 19210, i64 19258, i64 19280, i64 19316, i64 19352, i64 19388, i64 19436, i64 19458, i64 19494, i64 19530, i64 19566}
!4 = !{i64 20130, i64 20153, i64 20229, i64 20294, i64 20366, i64 20438, i64 20460, i64 20522, i64 20558, i64 20594, i64 20642, i64 20664, i64 20700, i64 20736, i64 20772, i64 20848, i64 20870, i64 20931, i64 20967, i64 21003, i64 21051, i64 21073, i64 21109, i64 21145, i64 21181}
!5 = !{i64 21793, i64 21816, i64 21852, i64 21888, i64 21924, i64 21960, i64 22008, i64 22030, i64 22066, i64 22124, i64 22195, i64 22217, i64 22266, i64 22352, i64 22388, i64 22468, i64 22504, i64 22540, i64 22576, i64 22654, i64 22690, i64 22726, i64 22762, i64 22798, i64 22933, i64 22969, i64 23005, i64 23041, i64 23077, i64 23113, i64 23188, i64 23210, i64 23246, i64 23282, i64 23318, i64 23354, i64 23390, i64 23450}
!6 = !{i64 23819, i64 23848, i64 23890}
!7 = !{i64 24258, i64 24287, i64 24329, i64 24371, i64 24413}
!8 = !{i64 25135, i64 25164, i64 25232, i64 25293, i64 25357, i64 25424, i64 25466, i64 25534, i64 25598}
!9 = !{i64 26173, i64 26203, i64 26272, i64 26315, i64 26390, i64 26433, i64 26476, i64 26557, i64 26600, i64 26643, i64 26698, i64 26727, i64 26770, i64 26813, i64 26856, i64 26911, i64 26940, i64 26983, i64 27084, i64 27127, i64 27170, i64 27225, i64 27254, i64 27361, i64 27404, i64 27447, i64 27525, i64 27568, i64 27611, i64 27654, i64 27697, i64 27740, i64 27795, i64 27824, i64 27867, i64 27932, i64 27975, i64 28018, i64 28061, i64 28133}
!10 = !{i64 28464, i64 28487, i64 28523, i64 28559, i64 28595, i64 28631, i64 28667, i64 28703, i64 28739}
!11 = !{i64 29070, i64 29093, i64 29129, i64 29165, i64 29201, i64 29237, i64 29273, i64 29309, i64 29345}
!12 = !{i64 29719, i64 29749, i64 29792, i64 29875, i64 29918, i64 29961, i64 30004, i64 30059, i64 30088, i64 30131, i64 30174, i64 30217, i64 30272, i64 30301, i64 30344, i64 30387, i64 30430, i64 30473, i64 30528, i64 30557, i64 30600}
!13 = !{i64 31017, i64 31047, i64 31090, i64 31160, i64 31203, i64 31258, i64 31287, i64 31330, i64 31373, i64 31416, i64 31471, i64 31500, i64 31543, i64 31586, i64 31629, i64 31672, i64 31715, i64 31758, i64 31813, i64 31842, i64 31885}
!14 = !{i64 32290, i64 32313, i64 32349, i64 32385, i64 32421, i64 32457, i64 32505, i64 32527, i64 32563, i64 32599, i64 32647, i64 32669, i64 32717, i64 32739, i64 32775, i64 32811}
!15 = !{i64 33175, i64 33198, i64 33234, i64 33270, i64 33306, i64 33342, i64 33390, i64 33412, i64 33448, i64 33504, i64 33540, i64 33576, i64 33612, i64 33648, i64 33684, i64 33720, i64 33768, i64 33790, i64 33838, i64 33860, i64 33896, i64 33932}
!16 = !{i64 34300, i64 34323, i64 34359, i64 34395, i64 34431, i64 34467, i64 34515, i64 34537, i64 34573, i64 34609, i64 34668, i64 34704, i64 34783, i64 34819, i64 34855, i64 34891, i64 34927, i64 34975, i64 34997, i64 35045, i64 35067, i64 35134, i64 35170, i64 35206, i64 35275, i64 35311, i64 35347}
!17 = distinct !{!17, !18}
!18 = !{!"llvm.loop.mustprogress"}
!19 = distinct !{!19, !18}
!20 = !{!21, !21, i64 0}
!21 = !{!"omnipotent char", !22, i64 0}
!22 = !{!"Simple C/C++ TBAA"}
!23 = distinct !{!23, !18}
!24 = distinct !{!24, !18}
