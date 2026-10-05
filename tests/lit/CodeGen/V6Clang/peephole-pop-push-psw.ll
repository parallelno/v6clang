; RUN: llc -march=v6clang -O2 < %s | FileCheck %s
; RUN: llc -march=v6clang -O2 -v6clang-disable-pop-push-elim < %s | FileCheck %s --check-prefix=DISABLED
;
; O83: PSW POP/PUSH pair elimination.  A byte-swap loop creates adjacent
; A/FLAGS save envelopes around a load and a store.  The middle
; POP PSW / PUSH PSW pair is removable when A and FLAGS are both dead before
; being read after the PUSH.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@perm = internal unnamed_addr global [7 x i8] zeroinitializer, align 1

; CHECK-LABEL: swap_loop:
; CHECK:       PUSH    PSW
; CHECK-NEXT:  LDAX    B
; CHECK-NEXT:  MOV     D, A
; CHECK-NEXT:  MOV     A, E
; CHECK-NEXT:  STAX    B
; CHECK-NEXT:  POP     PSW
;
; DISABLED-LABEL: swap_loop:
; DISABLED:       PUSH    PSW
; DISABLED-NEXT:  LDAX    B
; DISABLED-NEXT:  MOV     D, A
; DISABLED-NEXT:  POP     PSW
; DISABLED-NEXT:  PUSH    PSW
; DISABLED-NEXT:  MOV     A, E
; DISABLED-NEXT:  STAX    B
; DISABLED-NEXT:  POP     PSW
define void @swap_loop(i8 %k) local_unnamed_addr norecurse nounwind {
entry:
  br label %loop

loop:
  %hi = phi i8 [ %k, %entry ], [ %hi.next, %loop ]
  %lo = phi i8 [ 0, %entry ], [ %lo.next, %loop ]
  %lo16 = zext i8 %lo to i16
  %hi16 = zext i8 %hi to i16
  %lo.ptr = getelementptr inbounds [7 x i8], ptr @perm, i16 0, i16 %lo16
  %tmp = load i8, ptr %lo.ptr, align 1
  %hi.ptr = getelementptr inbounds [7 x i8], ptr @perm, i16 0, i16 %hi16
  %val = load i8, ptr %hi.ptr, align 1
  store i8 %val, ptr %lo.ptr, align 1
  store i8 %tmp, ptr %hi.ptr, align 1
  %lo.next = add nuw i8 %lo, 1
  %hi.next = add i8 %hi, -1
  %again = icmp ult i8 %lo.next, %hi.next
  br i1 %again, label %loop, label %exit

exit:
  ret void
}