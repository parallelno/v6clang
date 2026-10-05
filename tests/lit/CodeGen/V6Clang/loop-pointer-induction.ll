; RUN: llc -march=v6clang -O2 < %s | FileCheck %s

; V6ClangLoopPointerInduction converts base+counter GEPs to running pointers.
; The loop should use LDAX/STAX with pointer increments instead of
; recomputing addresses from base + counter each iteration.

@src = dso_local global [100 x i8] zeroinitializer, align 1
@dst = dso_local global [100 x i8] zeroinitializer, align 1

; CHECK-LABEL: copy_loop:
; The src pointer should be loaded into DE and kept in a register.
; CHECK:       LXI D, src
; The loop body should use indirect loads/stores, not base+counter DAD.
; CHECK:       .LBB0_1:
; CHECK:       LDAX D
; CHECK:       MOV M, A
; The exit comparison should be against src+100 (pointer end address).
; CHECK:       src+100
; CHECK:       JNZ .LBB0_1
define void @copy_loop() {
entry:
  br label %loop

loop:
  %i = phi i16 [ 0, %entry ], [ %i.next, %loop ]
  %src.ptr = getelementptr inbounds [100 x i8], ptr @src, i16 0, i16 %i
  %val = load i8, ptr %src.ptr, align 1
  %dst.ptr = getelementptr inbounds [100 x i8], ptr @dst, i16 0, i16 %i
  store i8 %val, ptr %dst.ptr, align 1
  %i.next = add nuw nsw i16 %i, 1
  %done = icmp eq i16 %i.next, 100
  br i1 %done, label %exit, label %loop

exit:
  ret void
}

; Test that a step-2 IV (produced by a second LSR pass strength-reducing i*2
; into a stride-2 counter) uses ExitLimit as the byte end-offset, not
; ExitLimit*Step.  The loop visits 8 elements at stride 2, so the exit pointer
; must be src+16, not src+32.
;
; IR equivalent of:
;   for (int i = 0; i < 8; i++) dst[i] = src[i*2];
; after LSR rewrites the shl-by-1 into a step-2 IV (lsr.iv = 0,2,4,...,14,16).

; CHECK-LABEL: stride2_loop:
; CHECK:       LXI H, dst
; CHECK:       LXI D, src
; The loop body advances both pointers by 2 each iteration.
; CHECK:       INX H
; CHECK:       INX H
; The exit pointer must be src+16, not src+32.
; CHECK:       src+16
; CHECK:       JNZ
define void @stride2_loop() {
entry:
  br label %loop

loop:
  ; step-2 IV — exactly what codegen LSR produces from shl i16 %i, 1
  %lsr.iv = phi i16 [ 0, %entry ], [ %lsr.next, %loop ]
  %src.ptr = getelementptr inbounds [32 x i8], ptr @src, i16 0, i16 %lsr.iv
  %val = load i8, ptr %src.ptr, align 1
  %dst.ptr = getelementptr inbounds [100 x i8], ptr @dst, i16 0, i16 %lsr.iv
  store i8 %val, ptr %dst.ptr, align 1
  %lsr.next = add nuw nsw i16 %lsr.iv, 2
  %done = icmp eq i16 %lsr.next, 16
  br i1 %done, label %exit, label %loop

exit:
  ret void
}
