; RUN: llc -march=v6clang -O2 < %s | FileCheck %s --check-prefix=O2
; RUN: llc -march=v6clang -O2 -v6clang-disable-loadstore-opt < %s | FileCheck %s --check-prefix=OFF

; Verify the V6ClangLoadStoreOpt HL-state tracker for chained LXI -> INX/DCX
; folding across HL-preserving gap instructions and GlobalAddress operands.

@g_s = dso_local global [4 x i8] zeroinitializer, align 1
@g_a = dso_local global i8 0, align 1
@g_b = dso_local global i8 0, align 1
@g_c = dso_local global i8 0, align 1
@g_d = dso_local global i8 0, align 1

; --- Case 1: GlobalAddress chain with LDA / ADD M gaps. -----------------
; Three sequential field reads on @g_s. After the first LXI H, g_s+N
; the tracker should fold both subsequent LXIs into INX H (Delta=1 each).
;
; O2-LABEL: ga_chain:
; O2:       LXI     H, g_s
; O2-NOT:   LXI     H, g_s+
; O2:       INX     H
; O2-NOT:   LXI     H, g_s+
; O2:       INX     H
; O2:       RET
;
; OFF-LABEL: ga_chain:
; OFF:      LXI     H, g_s
; OFF:      LXI     H, g_s+
; OFF:      LXI     H, g_s+
; OFF:      RET
define i8 @ga_chain() {
  %p0 = getelementptr [4 x i8], ptr @g_s, i16 0, i16 0
  %p1 = getelementptr [4 x i8], ptr @g_s, i16 0, i16 1
  %p2 = getelementptr [4 x i8], ptr @g_s, i16 0, i16 2
  %p3 = getelementptr [4 x i8], ptr @g_s, i16 0, i16 3
  %a = load i8, ptr %p0
  %b = load i8, ptr %p1
  %c = load i8, ptr %p2
  %d = load i8, ptr %p3
  %ab = add i8 %a, %b
  %abc = add i8 %ab, %c
  %abcd = add i8 %abc, %d
  ret i8 %abcd
}

; --- Case 2: Distinct globals (negative). -------------------------------
; @g_a / @g_b / @g_c / @g_d have distinct GlobalValue identities. The
; pass must NOT fold across them even if they happen to be adjacent.
;
; O2-LABEL: distinct_globals:
; O2:       LXI     H, g_b
; O2:       LXI     H, g_c
; O2:       LXI     H, g_d
define i8 @distinct_globals() {
  %a = load volatile i8, ptr @g_a
  %b = load volatile i8, ptr @g_b
  %c = load volatile i8, ptr @g_c
  %d = load volatile i8, ptr @g_d
  %ab = add i8 %a, %b
  %abc = add i8 %ab, %c
  %abcd = add i8 %abc, %d
  ret i8 %abcd
}

; --- Case 3: optsize attribute exercises the cost-mode hook. ------------
; With optsize the threshold is 3 (vs 1 at -O2). The chain still folds
; because adjacent Delta values are already 1.
;
; O2-LABEL: ga_chain_optsize:
; O2:       LXI     H, g_s
; O2-NOT:   LXI     H, g_s+
; O2:       INX     H
; O2-NOT:   LXI     H, g_s+
; O2:       INX     H
; O2:       RET
define i8 @ga_chain_optsize() optsize {
  %p0 = getelementptr [4 x i8], ptr @g_s, i16 0, i16 0
  %p1 = getelementptr [4 x i8], ptr @g_s, i16 0, i16 1
  %p2 = getelementptr [4 x i8], ptr @g_s, i16 0, i16 2
  %p3 = getelementptr [4 x i8], ptr @g_s, i16 0, i16 3
  %a = load i8, ptr %p0
  %b = load i8, ptr %p1
  %c = load i8, ptr %p2
  %d = load i8, ptr %p3
  %ab = add i8 %a, %b
  %abc = add i8 %ab, %c
  %abcd = add i8 %abc, %d
  ret i8 %abcd
}
