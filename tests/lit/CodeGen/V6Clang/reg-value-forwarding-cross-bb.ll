; RUN: llc -march=v6clang < %s | FileCheck %s
; RUN: llc -march=v6clang --v6clang-disable-reg-value-forwarding < %s | FileCheck %s --check-prefix=OFF

; O92: unified cross-BB physical-register value forwarding.
;
; In @repro, bb.0 establishes A == D via `MOV D, A; ORA A` (ORA A is
; value-preserving: it only updates FLAGS, so the A == D equality survives).
; That equality flows across basic-block boundaries and around the loop
; back-edge, so the `MOV A, D` reloads inside the loop body and at the second
; loop's preheader are redundant and must be removed.
;
; The `MOV A, D` at the tail (.LBB*_6 / final value test) is a *legitimate*
; reload -- at that point A no longer holds D's value (A was decremented by the
; inner loop), so it must be PRESERVED. This guards against over-eager folding.
;
; Note: this pass is register-agnostic (the lattice uses TRI-based alias
; queries, not hard-coded register numbers). Forcing a redundant cross-BB move
; on a non-A register deterministically from IR is register-allocator dependent
; and unreliable, so non-A safety is exercised by the feature test (walk16 in
; tests/features/76) and by the alias-aware clobber logic in the pass.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@perm1 = dso_local local_unnamed_addr global [8 x i8] zeroinitializer, align 1
@count = dso_local local_unnamed_addr global [8 x i8] zeroinitializer, align 1

define dso_local noundef i8 @repro() local_unnamed_addr {
  %1 = alloca i8, align 1
  store volatile i8 7, ptr %1, align 1
  %2 = load volatile i8, ptr %1, align 1
  %3 = icmp eq i8 %2, 0
  br i1 %3, label %4, label %6

4:
  %5 = icmp eq i8 %2, 1
  br label %12

6:
  %7 = phi i8 [ %10, %6 ], [ 0, %0 ]
  %8 = zext i8 %7 to i16
  %9 = getelementptr inbounds [8 x i8], ptr @perm1, i16 0, i16 %8
  store i8 %7, ptr %9, align 1
  %10 = add nuw i8 %7, 1
  %11 = icmp eq i8 %10, %2
  br i1 %11, label %4, label %6

12:
  %13 = phi i8 [ 2, %24 ], [ %2, %4 ]
  %14 = icmp eq i8 %13, 1
  br i1 %14, label %22, label %15

15:
  %16 = phi i8 [ %20, %15 ], [ %13, %12 ]
  %17 = zext i8 %16 to i16
  %18 = add nsw i16 %17, -1
  %19 = getelementptr inbounds [8 x i8], ptr @count, i16 0, i16 %18
  store i8 %16, ptr %19, align 1
  %20 = add i8 %16, -1
  %21 = icmp eq i8 %20, 1
  br i1 %21, label %22, label %15

22:
  br i1 %5, label %23, label %24

23:
  ret i8 1

24:
  %25 = load i8, ptr getelementptr inbounds ([8 x i8], ptr @count, i16 0, i16 1), align 1
  %26 = add i8 %25, -1
  store i8 %26, ptr getelementptr inbounds ([8 x i8], ptr @count, i16 0, i16 1), align 1
  br label %12
}

; The equality A == D is set up once, before the loops.
; CHECK-LABEL: repro:
; CHECK:       MOV     D, A
; CHECK-NEXT:  ORA     A

; Inner permutation loop must NOT reload A from D: the value is already live.
; CHECK-LABEL: .LBB{{[0-9]+}}_2:
; CHECK:       MOV     M, E
; CHECK-NOT:   MOV     A, D
; CHECK:       JNZ     .LBB{{[0-9]+}}_2

; The tail value test still needs a real reload of D into A -- preserved.
; CHECK:       MOV     A, D
; CHECK-NEXT:  CPI     1

; With the pass disabled, the redundant inner-loop reload is present.
; OFF-LABEL: .LBB{{[0-9]+}}_2:
; OFF:       MOV     M, E
; OFF:       MOV     A, D
; OFF:       JNZ     .LBB{{[0-9]+}}_2
