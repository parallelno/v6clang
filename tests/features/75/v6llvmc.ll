; ModuleID = 'tests\features\75\v6clang.c'
source_filename = "tests\\features\\75\\v6clang.c"
target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@g_sink16 = dso_local global i16 0, align 2
@g_sink8 = dso_local global i8 0, align 1
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

; Function Attrs: nofree norecurse nounwind memory(readwrite, argmem: none)
define dso_local noundef i8 @lxi_lo_used(i16 noundef %0) local_unnamed_addr #1 {
  %2 = xor i16 %0, -19201
  store volatile i16 %2, ptr @g_sink16, align 2, !tbaa !17
  ret i8 -1
}

; Function Attrs: nofree norecurse nounwind memory(readwrite, argmem: none)
define dso_local noundef i8 @lxi_hi_used(i16 noundef %0) local_unnamed_addr #1 {
  %2 = xor i16 %0, -19201
  store volatile i16 %2, ptr @g_sink16, align 2, !tbaa !17
  ret i8 -76
}

; Function Attrs: nofree norecurse nounwind memory(readwrite, argmem: none)
define dso_local noundef i16 @lxi_lo_to_b(i16 noundef %0) local_unnamed_addr #1 {
  %2 = xor i16 %0, -26057
  store volatile i16 %2, ptr @g_sink16, align 2, !tbaa !17
  ret i16 55
}

; Function Attrs: nofree norecurse nounwind memory(readwrite, argmem: none)
define dso_local noundef i8 @lxi_lo_zero(i16 noundef %0) local_unnamed_addr #1 {
  %2 = xor i16 %0, -19456
  store volatile i16 %2, ptr @g_sink16, align 2, !tbaa !17
  ret i8 0
}

; Function Attrs: nofree norecurse nounwind memory(readwrite, argmem: none)
define dso_local noundef i16 @main() local_unnamed_addr #1 {
  store volatile i16 -22837, ptr @g_sink16, align 2, !tbaa !17
  store volatile i8 -1, ptr @g_sink8, align 1, !tbaa !21
  store volatile i16 -7545, ptr @g_sink16, align 2, !tbaa !17
  store volatile i8 -76, ptr @g_sink8, align 1, !tbaa !21
  store volatile i16 139, ptr @g_sink16, align 2, !tbaa !17
  store volatile i16 55, ptr @g_sink16, align 2, !tbaa !17
  store volatile i16 27376, ptr @g_sink16, align 2, !tbaa !17
  store volatile i8 0, ptr @g_sink8, align 1, !tbaa !21
  ret i16 0
}

attributes #0 = { naked noinline nounwind "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "v6clang-rt-helper" }
attributes #1 = { nofree norecurse nounwind memory(readwrite, argmem: none) "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" }
attributes #2 = { nounwind }

!llvm.module.flags = !{!0}
!llvm.ident = !{!1}

!0 = !{i32 1, !"wchar_size", i32 2}
!1 = !{!"clang version 18.1.0rc (https://github.com/llvm/llvm-project.git 461274b81d8641eab64d494accddc81d7db8a09e)"}
!2 = !{i64 16697, i64 16720, i64 16789, i64 16859, i64 16954, i64 16976, i64 17012, i64 17069, i64 17132, i64 17208, i64 17230, i64 17266, i64 17302, i64 17338, i64 17403}
!3 = !{i64 17998, i64 18021, i64 18057, i64 18093, i64 18141, i64 18163, i64 18199, i64 18235, i64 18271, i64 18319, i64 18341, i64 18377, i64 18413, i64 18449}
!4 = !{i64 19013, i64 19036, i64 19112, i64 19177, i64 19249, i64 19321, i64 19343, i64 19405, i64 19441, i64 19477, i64 19525, i64 19547, i64 19583, i64 19619, i64 19655, i64 19731, i64 19753, i64 19814, i64 19850, i64 19886, i64 19934, i64 19956, i64 19992, i64 20028, i64 20064}
!5 = !{i64 20676, i64 20699, i64 20735, i64 20771, i64 20807, i64 20843, i64 20891, i64 20913, i64 20949, i64 21007, i64 21078, i64 21100, i64 21149, i64 21235, i64 21271, i64 21351, i64 21387, i64 21423, i64 21459, i64 21537, i64 21573, i64 21609, i64 21645, i64 21681, i64 21816, i64 21852, i64 21888, i64 21924, i64 21960, i64 21996, i64 22071, i64 22093, i64 22129, i64 22165, i64 22201, i64 22237, i64 22273, i64 22333}
!6 = !{i64 22702, i64 22731, i64 22773}
!7 = !{i64 23141, i64 23170, i64 23212, i64 23254, i64 23296}
!8 = !{i64 24018, i64 24047, i64 24115, i64 24176, i64 24240, i64 24307, i64 24349, i64 24417, i64 24481}
!9 = !{i64 25056, i64 25086, i64 25155, i64 25198, i64 25273, i64 25316, i64 25359, i64 25440, i64 25483, i64 25526, i64 25581, i64 25610, i64 25653, i64 25696, i64 25739, i64 25794, i64 25823, i64 25866, i64 25967, i64 26010, i64 26053, i64 26108, i64 26137, i64 26244, i64 26287, i64 26330, i64 26408, i64 26451, i64 26494, i64 26537, i64 26580, i64 26623, i64 26678, i64 26707, i64 26750, i64 26815, i64 26858, i64 26901, i64 26944, i64 27016}
!10 = !{i64 27347, i64 27370, i64 27406, i64 27442, i64 27478, i64 27514, i64 27550, i64 27586, i64 27622}
!11 = !{i64 27953, i64 27976, i64 28012, i64 28048, i64 28084, i64 28120, i64 28156, i64 28192, i64 28228}
!12 = !{i64 28602, i64 28632, i64 28675, i64 28758, i64 28801, i64 28844, i64 28887, i64 28942, i64 28971, i64 29014, i64 29057, i64 29100, i64 29155, i64 29184, i64 29227, i64 29270, i64 29313, i64 29356, i64 29411, i64 29440, i64 29483}
!13 = !{i64 29900, i64 29930, i64 29973, i64 30043, i64 30086, i64 30141, i64 30170, i64 30213, i64 30256, i64 30299, i64 30354, i64 30383, i64 30426, i64 30469, i64 30512, i64 30555, i64 30598, i64 30641, i64 30696, i64 30725, i64 30768}
!14 = !{i64 31173, i64 31196, i64 31232, i64 31268, i64 31304, i64 31340, i64 31388, i64 31410, i64 31446, i64 31482, i64 31530, i64 31552, i64 31600, i64 31622, i64 31658, i64 31694}
!15 = !{i64 32058, i64 32081, i64 32117, i64 32153, i64 32189, i64 32225, i64 32273, i64 32295, i64 32331, i64 32387, i64 32423, i64 32459, i64 32495, i64 32531, i64 32567, i64 32603, i64 32651, i64 32673, i64 32721, i64 32743, i64 32779, i64 32815}
!16 = !{i64 33183, i64 33206, i64 33242, i64 33278, i64 33314, i64 33350, i64 33398, i64 33420, i64 33456, i64 33492, i64 33551, i64 33587, i64 33666, i64 33702, i64 33738, i64 33774, i64 33810, i64 33858, i64 33880, i64 33928, i64 33950, i64 34017, i64 34053, i64 34089, i64 34158, i64 34194, i64 34230}
!17 = !{!18, !18, i64 0}
!18 = !{!"short", !19, i64 0}
!19 = !{!"omnipotent char", !20, i64 0}
!20 = !{!"Simple C/C++ TBAA"}
!21 = !{!19, !19, i64 0}
