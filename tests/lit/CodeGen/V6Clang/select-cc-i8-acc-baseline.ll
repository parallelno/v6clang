; O81 golden — SELECT_CC i8 with constant arms: post-O81 register allocation.
;
; RUN: llc -march=v6clang < %s | FileCheck %s
;
; Documents the POST-O81 select materialization behavior for two scenarios:
;
;   Scenario A (select_simple_loop): no outer-loop register pressure.
;     O81 fires: both arms are MVIr constants, A is physically dead at the MI.
;     4-block through-A diamond emitted; MBP places true arm (0x4F) as
;     fallthrough → MVI A, 0x4F before XRA A in linear layout.
;
;   Scenario B (fillscreen_double): outer loop counter live across inner loop.
;     O81 fires: both arms constant, A physically dead (vreg pressure handled
;     by allocator). Result routed through A; XRA A via O55 on zero arm.
;     Saves 1B / 4cc per false-path inner iteration (≈3200cc over 25×64 loop).
;
; neg_a_live:       val_in_A must be saved (to L) before the select fires;
;                   O81 still fires (allocator spills val_in_A to L correctly).
; neg_computed_arms: arms are pointer loads, not immediates → fall back.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; ---------------------------------------------------------------------------
; Scenario A — simple loop; O81 fires (constant arms, A physically dead).
; MBP places true arm (0x4F) as fallthrough → MVI A, 0x4f before XRA A.
; CHECK-LABEL: select_simple_loop:
; CHECK:       ANI{{.*}}4
; CHECK-NOT:   MVI{{.*}}C
; CHECK:       MVI{{.*}}A{{.*}}0x4f
; CHECK:       XRA{{.*}}A
; CHECK:       STAX
; ---------------------------------------------------------------------------
define void @select_simple_loop(ptr %src, ptr %dst, i16 %n) {
entry:
  %zero = icmp eq i16 %n, 0
  br i1 %zero, label %exit, label %loop
loop:
  %sp = phi ptr [ %src, %entry ], [ %sn, %loop ]
  %dp = phi ptr [ %dst, %entry ], [ %dn, %loop ]
  %i  = phi i16 [ 0, %entry ], [ %in, %loop ]
  %b  = load i8, ptr %sp
  %m  = and i8 %b, 4
  %c  = icmp eq i8 %m, 0
  %v  = select i1 %c, i8 0, i8 79
  store i8 %v, ptr %dp
  %sn = getelementptr inbounds i8, ptr %sp, i16 1
  %dn = getelementptr inbounds i8, ptr %dp, i16 1
  %in = add i16 %i, 1
  %done = icmp eq i16 %in, %n
  br i1 %done, label %exit, label %loop
exit:
  ret void
}

; ---------------------------------------------------------------------------
; Scenario B — fillScreen double-loop; O81 fires (constant arms, A dead).
; Inner loop after O81:
;   LDAX  D
;   ANI   4
;   J<cc> .true
;   MVI   A, 0x4F    ← true arm (MBP fallthrough)
;   JMP   .sink
; .true:
;   XRA   A          ← O55 fires: MVI A, 0 → XRA A (1B / 4cc)
; .sink:
;   MOV   M, A       ← result in A; C is now free
;
; CHECK-LABEL: fillscreen_double:
; CHECK:       ANI{{.*}}4
; CHECK-NOT:   MVI{{.*}}C
; CHECK:       MVI{{.*}}A{{.*}}0x4f
; CHECK:       XRA{{.*}}A
; CHECK:       MOV{{.*}}M{{.*}}A
; ---------------------------------------------------------------------------
define void @fillscreen_double() {
entry:
  br label %outer
outer:
  %src = phi ptr [ inttoptr (i16 -2048 to ptr), %entry ], [ %spn, %row_end ]
  %dst = phi ptr [ inttoptr (i16 30722 to ptr), %entry ], [ %dst_next, %row_end ]
  %y   = phi i8  [ 0, %entry ], [ %y_next, %row_end ]
  %row_end_ptr = getelementptr i8, ptr %src, i16 64
  br label %inner
inner:
  %sp  = phi ptr [ %src, %outer ], [ %spn, %inner ]
  %dp  = phi ptr [ %dst, %outer ], [ %dpn, %inner ]
  %b   = load i8, ptr %sp
  %m   = and i8 %b, 4
  %c   = icmp eq i8 %m, 0
  %v   = select i1 %c, i8 0, i8 79
  store i8 %v, ptr %dp
  %spn    = getelementptr inbounds i8, ptr %sp, i16 1
  %dpn    = getelementptr inbounds i8, ptr %dp, i16 1
  %idone  = icmp eq ptr %spn, %row_end_ptr
  br i1 %idone, label %row_end, label %inner
row_end:
  %dst_next = getelementptr inbounds i8, ptr %dpn, i16 15
  %y_next   = add nuw nsw i8 %y, 1
  %odone    = icmp eq i8 %y_next, 25
  br i1 %odone, label %exit, label %outer
exit:
  ret void
}

; ---------------------------------------------------------------------------
; NEGATIVE: A holds val_in_A (first arg) which is needed post-select via ADD.
; O81 still fires (A physically dead at SELECT MI); allocator spills val_in_A
; to L. MOV L, A appears at function entry; subsequent ADD L is correct.
; CHECK-LABEL: neg_a_live:
; CHECK:       MOV{{.*}}L{{.*}}A
; CHECK:       XRA{{.*}}A
; CHECK:       RET
; ---------------------------------------------------------------------------
define i8 @neg_a_live(i8 %a, i8 %cond) {
  %cmp = icmp ne i8 %cond, 0
  %sel = select i1 %cmp, i8 79, i8 0
  %r   = add i8 %sel, %a
  ret i8 %r
}

; ---------------------------------------------------------------------------
; NEGATIVE: computed arms (loads), not constants.
; No constant-materialization path; efficient pointer-swap used instead.
; CHECK-LABEL: neg_computed_arms:
; CHECK:       RET
; ---------------------------------------------------------------------------
define i8 @neg_computed_arms(ptr %p, ptr %q, i8 %cond) {
  %x = load i8, ptr %p
  %y = load i8, ptr %q
  %cmp = icmp ne i8 %cond, 0
  %r = select i1 %cmp, i8 %x, i8 %y
  ret i8 %r
}
