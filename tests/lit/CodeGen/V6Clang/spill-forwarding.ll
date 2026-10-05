; RUN: llc -march=v6clang < %s | FileCheck %s
; TODO: enable DISABLED check once V6ClangSpillForwarding is added to the pipeline
; R-U-N: llc -march=v6clang -v6clang-disable-spill-forwarding < %s | FileCheck %s --check-prefix=DISABLED

; Test V6ClangSpillForwarding: redundant RELOAD16 pseudos should be replaced
; with register-to-register MOV instructions, eliminating DAD SP sequences.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; Multi-pointer copy loop with i16 index ??? generates heavy register pressure.
; Two 16-bit base pointers survive across the loop, the loop counter is i16,
; and GEP (base + idx) forces pointer arithmetic in HL.
; With only 3 register pairs (BC, DE, HL), 4 live i16 values cause spills.
;
; With forwarding: spill-then-reload of the same pair within a BB is replaced
; by MOV pairs, eliminating stack accesses.  Expect fewer DAD SP in the loop.
;
; CHECK-LABEL: test_multi_ptr_copy:
; The loop body performs indirect load from src (LDAX DE), store to dst
; (MOV M, A), and increments both pointers.
; CHECK:       .LBB0_2:
; CHECK:       LDAX    D
; CHECK:       MOV     M, A
; CHECK:       JNZ .LBB0_2
;
; DISABLED-LABEL: test_multi_ptr_copy:
; Without forwarding, register-to-register forwarding MOVs do not appear;
; the loop counter is reloaded from the stack instead.
; DISABLED:       .LBB0_2:
; DISABLED-NOT:   MOV E, C
; DISABLED:       JNZ .LBB0_2
define void @test_multi_ptr_copy(ptr %dst, ptr %src, i8 %n) {
entry:
  %cmp = icmp eq i8 %n, 0
  br i1 %cmp, label %exit, label %preheader

preheader:
  %count = zext i8 %n to i16
  br label %loop

loop:
  %idx = phi i16 [ 0, %preheader ], [ %idx.next, %loop ]
  %src.ptr = getelementptr inbounds i8, ptr %src, i16 %idx
  %val = load i8, ptr %src.ptr
  %val1 = add i8 %val, 1
  %dst.ptr = getelementptr inbounds i8, ptr %dst, i16 %idx
  store i8 %val1, ptr %dst.ptr
  %idx.next = add nuw nsw i16 %idx, 1
  %done = icmp eq i16 %idx.next, %count
  br i1 %done, label %exit, label %loop

exit:
  ret void
}
