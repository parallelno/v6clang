; ModuleID = 'tests\features\74\v6clang.c'
source_filename = "tests\\features\\74\\v6clang.c"
target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@g_sink16 = dso_local local_unnamed_addr global i16 0, align 2
@g_sink8 = dso_local local_unnamed_addr global i8 0, align 1
@llvm.compiler.used = appending global [15 x ptr] [ptr @__ashlhi3, ptr @__ashrhi3, ptr @__divhi3, ptr @__divmodhi4, ptr @__lshrhi3, ptr @__modhi3, ptr @__mulhi3, ptr @__mulqi3, ptr @__udivhi3, ptr @__udivmodhi4, ptr @__umodhi3, ptr @__v6clang_mulqihi3, ptr @__v6clang_neg_de_body, ptr @__v6clang_neg_hl_body, ptr @__v6clang_udivmod16_body], section "llvm.metadata"

; Function Attrs: naked noinline nounwind
define internal i8 @__mulqi3(i8 noundef %0, i8 noundef %1) #0 {
  tail call void asm sideeffect "MOV  E, B           \0A\09MVI  D, 0           \0A\09LXI  H, 0           \0A\09MVI  B, 8           \0A1:                  \0A\09DAD  H              \0A\09RLC                 \0A\09JNC  2f             \0A\09DAD  D              \0A2:                  \0A\09DCR  B              \0A\09JNZ  1b             \0A\09MOV  A, L           \0A\09RET                 \0A\09", ""() #5, !srcloc !2
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__v6clang_mulqihi3(i8 noundef %0, i8 noundef %1) #0 {
  tail call void asm sideeffect "MOV  E, B           \0A\09MVI  D, 0           \0A\09LXI  H, 0           \0A\09MVI  B, 8           \0A1:                  \0A\09DAD  H              \0A\09RLC                 \0A\09JNC  2f             \0A\09DAD  D              \0A2:                  \0A\09DCR  B              \0A\09JNZ  1b             \0A\09RET                 \0A\09", ""() #5, !srcloc !3
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__mulhi3(i16 noundef %0, i16 noundef %1) #0 {
  tail call void asm sideeffect "XCHG                \0A\09MOV  A, H           \0A\09MOV  C, L           \0A\09LXI  H, 0           \0A\09MVI  B, 8           \0A1:                  \0A\09DAD  H              \0A\09RLC                 \0A\09JNC  2f             \0A\09DAD  D              \0A2:                  \0A\09DCR  B              \0A\09JNZ  1b             \0A\09MOV  A, C           \0A\09MVI  B, 8           \0A3:                  \0A\09DAD  H              \0A\09RLC                 \0A\09JNC  4f             \0A\09DAD  D              \0A4:                  \0A\09DCR  B              \0A\09JNZ  3b             \0A\09RET                 \0A\09", ""() #5, !srcloc !4
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal void @__v6clang_udivmod16_body() #0 {
  tail call void asm sideeffect "MOV  A, D           \0A\09ORA  E              \0A\09JNZ  1f             \0A\09LXI  H, 0xFFFF      \0A\09LXI  B, 0           \0A\09RET                 \0A1:                  \0A\09LXI  B, 0           \0A\09MVI  A, 16          \0A\09PUSH PSW            \0A2:                  \0A\09DAD  H              \0A\09MOV  A, C           \0A\09RAL                 \0A\09MOV  C, A           \0A\09MOV  A, B           \0A\09RAL                 \0A\09MOV  B, A           \0A\09MOV  A, C           \0A\09SUB  E              \0A\09MOV  A, B           \0A\09SBB  D              \0A\09JC   3f             \0A\09MOV  A, C           \0A\09SUB  E              \0A\09MOV  C, A           \0A\09MOV  A, B           \0A\09SBB  D              \0A\09MOV  B, A           \0A\09INX  H              \0A3:                  \0A\09POP  PSW            \0A\09DCR  A              \0A\09PUSH PSW            \0A\09JNZ  2b             \0A\09POP  PSW            \0A\09RET                 \0A\09", ""() #5, !srcloc !5
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__udivhi3(i16 noundef %0, i16 noundef %1) #0 {
  tail call void asm sideeffect "CALL __v6clang_udivmod16_body \0A\09RET                       \0A\09", ""() #5, !srcloc !6
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__umodhi3(i16 noundef %0, i16 noundef %1) #0 {
  tail call void asm sideeffect "CALL __v6clang_udivmod16_body \0A\09MOV  H, B                 \0A\09MOV  L, C                 \0A\09RET                       \0A\09", ""() #5, !srcloc !7
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__udivmodhi4(i16 noundef %0, i16 noundef %1, ptr noundef %2) #0 {
  tail call void asm sideeffect "PUSH B                    \0A\09CALL __v6clang_udivmod16_body \0A\09XTHL                      \0A\09MOV  M, C                 \0A\09INX  H                    \0A\09MOV  M, B                 \0A\09POP  H                    \0A\09RET                       \0A\09", ""() #5, !srcloc !8
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__divmodhi4(i16 noundef %0, i16 noundef %1, ptr noundef %2) #0 {
  tail call void asm sideeffect "PUSH B                     \0A\09MOV  A, H                  \0A\09PUSH PSW                   \0A\09MOV  A, H                  \0A\09XRA  D                     \0A\09PUSH PSW                   \0A\09MOV  A, H                  \0A\09ORA  A                     \0A\09JP   1f                    \0A\09CALL __v6clang_neg_hl_body     \0A1:                         \0A\09MOV  A, D                  \0A\09ORA  A                     \0A\09JP   2f                    \0A\09CALL __v6clang_neg_de_body     \0A2:                         \0A\09CALL __v6clang_udivmod16_body  \0A\09POP  PSW                   \0A\09ORA  A                     \0A\09JP   3f                    \0A\09CALL __v6clang_neg_hl_body     \0A3:                         \0A\09POP  PSW                   \0A\09ORA  A                     \0A\09JP   4f                    \0A\09MOV  A, C                  \0A\09CMA                        \0A\09MOV  C, A                  \0A\09MOV  A, B                  \0A\09CMA                        \0A\09MOV  B, A                  \0A\09INX  B                     \0A4:                         \0A\09XTHL                       \0A\09MOV  M, C                  \0A\09INX  H                     \0A\09MOV  M, B                  \0A\09POP  H                     \0A\09RET                        \0A\09", ""() #5, !srcloc !9
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal void @__v6clang_neg_hl_body() #0 {
  tail call void asm sideeffect "MOV  A, L           \0A\09CMA                 \0A\09MOV  L, A           \0A\09MOV  A, H           \0A\09CMA                 \0A\09MOV  H, A           \0A\09INX  H              \0A\09RET                 \0A\09", ""() #5, !srcloc !10
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal void @__v6clang_neg_de_body() #0 {
  tail call void asm sideeffect "MOV  A, E           \0A\09CMA                 \0A\09MOV  E, A           \0A\09MOV  A, D           \0A\09CMA                 \0A\09MOV  D, A           \0A\09INX  D              \0A\09RET                 \0A\09", ""() #5, !srcloc !11
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__divhi3(i16 noundef %0, i16 noundef %1) #0 {
  tail call void asm sideeffect "MOV  A, H                  \0A\09XRA  D                     \0A\09PUSH PSW                   \0A\09MOV  A, H                  \0A\09ORA  A                     \0A\09JP   1f                    \0A\09CALL __v6clang_neg_hl_body     \0A1:                         \0A\09MOV  A, D                  \0A\09ORA  A                     \0A\09JP   2f                    \0A\09CALL __v6clang_neg_de_body     \0A2:                         \0A\09CALL __v6clang_udivmod16_body  \0A\09POP  PSW                   \0A\09ORA  A                     \0A\09JP   3f                    \0A\09CALL __v6clang_neg_hl_body     \0A3:                         \0A\09RET                        \0A\09", ""() #5, !srcloc !12
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__modhi3(i16 noundef %0, i16 noundef %1) #0 {
  tail call void asm sideeffect "MOV  A, H                  \0A\09PUSH PSW                   \0A\09ORA  A                     \0A\09JP   1f                    \0A\09CALL __v6clang_neg_hl_body     \0A1:                         \0A\09MOV  A, D                  \0A\09ORA  A                     \0A\09JP   2f                    \0A\09CALL __v6clang_neg_de_body     \0A2:                         \0A\09CALL __v6clang_udivmod16_body  \0A\09MOV  H, B                  \0A\09MOV  L, C                  \0A\09POP  PSW                   \0A\09ORA  A                     \0A\09JP   3f                    \0A\09CALL __v6clang_neg_hl_body     \0A3:                         \0A\09RET                        \0A\09", ""() #5, !srcloc !13
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__ashlhi3(i16 noundef %0, i8 noundef %1) #0 {
  tail call void asm sideeffect "MOV  A, E           \0A\09ANI  0x0F           \0A\09JZ   2f             \0A\09CPI  16             \0A\09JNC  3f             \0A\09MOV  E, A           \0A1:                  \0A\09DAD  H              \0A\09DCR  E              \0A\09JNZ  1b             \0A2:                  \0A\09RET                 \0A3:                  \0A\09LXI  H, 0           \0A\09RET                 \0A\09", ""() #5, !srcloc !14
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__lshrhi3(i16 noundef %0, i8 noundef %1) #0 {
  tail call void asm sideeffect "MOV  A, E           \0A\09ANI  0x0F           \0A\09JZ   2f             \0A\09CPI  16             \0A\09JNC  3f             \0A\09MOV  E, A           \0A1:                  \0A\09ORA  A              \0A\09MOV  A, H           \0A\09RAR                 \0A\09MOV  H, A           \0A\09MOV  A, L           \0A\09RAR                 \0A\09MOV  L, A           \0A\09DCR  E              \0A\09JNZ  1b             \0A2:                  \0A\09RET                 \0A3:                  \0A\09LXI  H, 0           \0A\09RET                 \0A\09", ""() #5, !srcloc !15
  unreachable
}

; Function Attrs: naked noinline nounwind
define internal i16 @__ashrhi3(i16 noundef %0, i8 noundef %1) #0 {
  tail call void asm sideeffect "MOV  A, E           \0A\09ANI  0x0F           \0A\09JZ   2f             \0A\09CPI  16             \0A\09JNC  3f             \0A\09MOV  E, A           \0A1:                  \0A\09MOV  A, H           \0A\09RAL                 \0A\09MOV  A, H           \0A\09RAR                 \0A\09MOV  H, A           \0A\09MOV  A, L           \0A\09RAR                 \0A\09MOV  L, A           \0A\09DCR  E              \0A\09JNZ  1b             \0A2:                  \0A\09RET                 \0A3:                  \0A\09MOV  A, H           \0A\09RAL                 \0A\09SBB  A              \0A\09MOV  H, A           \0A\09MOV  L, A           \0A\09RET                 \0A\09", ""() #5, !srcloc !16
  unreachable
}

; Function Attrs: mustprogress nofree noinline norecurse nosync nounwind willreturn memory(write, argmem: none, inaccessiblemem: none)
define dso_local noundef i8 @p1_lo_byte_after_xor16(i16 noundef %0) local_unnamed_addr #1 {
  %2 = xor i16 %0, -19201
  store i16 %2, ptr @g_sink16, align 2, !tbaa !17
  ret i8 -1
}

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #2

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #2

; Function Attrs: mustprogress nofree noinline norecurse nosync nounwind willreturn memory(write, argmem: none, inaccessiblemem: none)
define dso_local noundef i8 @p2_hi_byte_after_xor16(i16 noundef %0) local_unnamed_addr #1 {
  %2 = xor i16 %0, -19201
  store i16 %2, ptr @g_sink16, align 2, !tbaa !17
  ret i8 -76
}

; Function Attrs: mustprogress nofree noinline norecurse nosync nounwind willreturn memory(none)
define dso_local noundef i8 @p3_standalone_lo() local_unnamed_addr #3 {
  ret i8 52
}

; Function Attrs: mustprogress nofree noinline norecurse nosync nounwind willreturn memory(none)
define dso_local noundef i8 @p4_standalone_hi() local_unnamed_addr #3 {
  ret i8 18
}

; Function Attrs: mustprogress nofree noinline norecurse nosync nounwind willreturn memory(write, argmem: none, inaccessiblemem: none)
define dso_local noundef i16 @p5_both_bytes_used(i16 noundef %0) local_unnamed_addr #1 {
  %2 = xor i16 %0, -19201
  store i16 %2, ptr @g_sink16, align 2, !tbaa !17
  ret i16 -19201
}

; Function Attrs: nofree norecurse nounwind memory(write, inaccessiblemem: readwrite)
define dso_local i16 @main(i16 noundef %0, ptr nocapture noundef readnone %1) local_unnamed_addr #4 {
  %3 = alloca i8, align 1
  %4 = alloca i8, align 1
  %5 = alloca i8, align 1
  %6 = alloca i8, align 1
  %7 = alloca i16, align 2
  call void @llvm.lifetime.start.p0(i64 1, ptr nonnull %3)
  %8 = tail call i8 @p1_lo_byte_after_xor16(i16 noundef 4660) #6
  store volatile i8 -1, ptr %3, align 1, !tbaa !21
  call void @llvm.lifetime.start.p0(i64 1, ptr nonnull %4)
  %9 = tail call i8 @p2_hi_byte_after_xor16(i16 noundef 22136) #6
  store volatile i8 -76, ptr %4, align 1, !tbaa !21
  call void @llvm.lifetime.start.p0(i64 1, ptr nonnull %5)
  store volatile i8 52, ptr %5, align 1, !tbaa !21
  call void @llvm.lifetime.start.p0(i64 1, ptr nonnull %6)
  store volatile i8 18, ptr %6, align 1, !tbaa !21
  call void @llvm.lifetime.start.p0(i64 2, ptr nonnull %7)
  %10 = tail call i16 @p5_both_bytes_used(i16 noundef -21555) #6
  store volatile i16 -19201, ptr %7, align 2, !tbaa !17
  %11 = load volatile i8, ptr %3, align 1, !tbaa !21
  %12 = zext i8 %11 to i16
  %13 = load volatile i8, ptr %4, align 1, !tbaa !21
  %14 = zext i8 %13 to i16
  %15 = add nuw nsw i16 %14, %12
  %16 = load volatile i8, ptr %5, align 1, !tbaa !21
  %17 = zext i8 %16 to i16
  %18 = add nuw nsw i16 %15, %17
  %19 = load volatile i8, ptr %6, align 1, !tbaa !21
  %20 = zext i8 %19 to i16
  %21 = add nuw nsw i16 %18, %20
  %22 = load volatile i16, ptr %7, align 2, !tbaa !17
  %23 = and i16 %22, 255
  %24 = add nuw nsw i16 %21, %23
  call void @llvm.lifetime.end.p0(i64 2, ptr nonnull %7)
  call void @llvm.lifetime.end.p0(i64 1, ptr nonnull %6)
  call void @llvm.lifetime.end.p0(i64 1, ptr nonnull %5)
  call void @llvm.lifetime.end.p0(i64 1, ptr nonnull %4)
  call void @llvm.lifetime.end.p0(i64 1, ptr nonnull %3)
  ret i16 %24
}

attributes #0 = { naked noinline nounwind "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "v6clang-rt-helper" }
attributes #1 = { mustprogress nofree noinline norecurse nosync nounwind willreturn memory(write, argmem: none, inaccessiblemem: none) "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" }
attributes #2 = { mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #3 = { mustprogress nofree noinline norecurse nosync nounwind willreturn memory(none) "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" }
attributes #4 = { nofree norecurse nounwind memory(write, inaccessiblemem: readwrite) "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" }
attributes #5 = { nounwind }
attributes #6 = { nobuiltin "no-builtins" }

!llvm.module.flags = !{!0}
!llvm.ident = !{!1}

!0 = !{i32 1, !"wchar_size", i32 2}
!1 = !{!"clang version 18.1.0rc (https://github.com/llvm/llvm-project.git 461274b81d8641eab64d494accddc81d7db8a09e)"}
!2 = !{i64 17882, i64 17905, i64 17974, i64 18044, i64 18139, i64 18161, i64 18197, i64 18254, i64 18317, i64 18393, i64 18415, i64 18451, i64 18487, i64 18523, i64 18588}
!3 = !{i64 19183, i64 19206, i64 19242, i64 19278, i64 19326, i64 19348, i64 19384, i64 19420, i64 19456, i64 19504, i64 19526, i64 19562, i64 19598, i64 19634}
!4 = !{i64 20198, i64 20221, i64 20297, i64 20362, i64 20434, i64 20506, i64 20528, i64 20590, i64 20626, i64 20662, i64 20710, i64 20732, i64 20768, i64 20804, i64 20840, i64 20916, i64 20938, i64 20999, i64 21035, i64 21071, i64 21119, i64 21141, i64 21177, i64 21213, i64 21249}
!5 = !{i64 21861, i64 21884, i64 21920, i64 21956, i64 21992, i64 22028, i64 22076, i64 22098, i64 22134, i64 22192, i64 22263, i64 22285, i64 22334, i64 22420, i64 22456, i64 22536, i64 22572, i64 22608, i64 22644, i64 22722, i64 22758, i64 22794, i64 22830, i64 22866, i64 23001, i64 23037, i64 23073, i64 23109, i64 23145, i64 23181, i64 23256, i64 23278, i64 23314, i64 23350, i64 23386, i64 23422, i64 23458, i64 23518}
!6 = !{i64 23887, i64 23916, i64 23958}
!7 = !{i64 24326, i64 24355, i64 24397, i64 24439, i64 24481}
!8 = !{i64 25203, i64 25232, i64 25300, i64 25361, i64 25425, i64 25492, i64 25534, i64 25602, i64 25666}
!9 = !{i64 26241, i64 26271, i64 26340, i64 26383, i64 26458, i64 26501, i64 26544, i64 26625, i64 26668, i64 26711, i64 26766, i64 26795, i64 26838, i64 26881, i64 26924, i64 26979, i64 27008, i64 27051, i64 27152, i64 27195, i64 27238, i64 27293, i64 27322, i64 27429, i64 27472, i64 27515, i64 27593, i64 27636, i64 27679, i64 27722, i64 27765, i64 27808, i64 27863, i64 27892, i64 27935, i64 28000, i64 28043, i64 28086, i64 28129, i64 28201}
!10 = !{i64 28532, i64 28555, i64 28591, i64 28627, i64 28663, i64 28699, i64 28735, i64 28771, i64 28807}
!11 = !{i64 29138, i64 29161, i64 29197, i64 29233, i64 29269, i64 29305, i64 29341, i64 29377, i64 29413}
!12 = !{i64 29787, i64 29817, i64 29860, i64 29943, i64 29986, i64 30029, i64 30072, i64 30127, i64 30156, i64 30199, i64 30242, i64 30285, i64 30340, i64 30369, i64 30412, i64 30455, i64 30498, i64 30541, i64 30596, i64 30625, i64 30668}
!13 = !{i64 31085, i64 31115, i64 31158, i64 31228, i64 31271, i64 31326, i64 31355, i64 31398, i64 31441, i64 31484, i64 31539, i64 31568, i64 31611, i64 31654, i64 31697, i64 31740, i64 31783, i64 31826, i64 31881, i64 31910, i64 31953}
!14 = !{i64 32358, i64 32381, i64 32417, i64 32453, i64 32489, i64 32525, i64 32573, i64 32595, i64 32631, i64 32667, i64 32715, i64 32737, i64 32785, i64 32807, i64 32843, i64 32879}
!15 = !{i64 33243, i64 33266, i64 33302, i64 33338, i64 33374, i64 33410, i64 33458, i64 33480, i64 33516, i64 33572, i64 33608, i64 33644, i64 33680, i64 33716, i64 33752, i64 33788, i64 33836, i64 33858, i64 33906, i64 33928, i64 33964, i64 34000}
!16 = !{i64 34368, i64 34391, i64 34427, i64 34463, i64 34499, i64 34535, i64 34583, i64 34605, i64 34641, i64 34677, i64 34736, i64 34772, i64 34851, i64 34887, i64 34923, i64 34959, i64 34995, i64 35043, i64 35065, i64 35113, i64 35135, i64 35202, i64 35238, i64 35274, i64 35343, i64 35379, i64 35415}
!17 = !{!18, !18, i64 0}
!18 = !{!"short", !19, i64 0}
!19 = !{!"omnipotent char", !20, i64 0}
!20 = !{!"Simple C/C++ TBAA"}
!21 = !{!19, !19, i64 0}
