; Verify O51: V6CLANG LSR formula tie-breaker can be forced to Insns-first
; ordering via -v6clang-lsr-strategy=insns-first. Auto remains Regs-first
; (see lsr-strategy-size.ll for the auto path); this lit test pins the
; opt-in path.
;
; The four-pointer axpy3 loop has more induction variables than V6CLANG's three
; GP register pairs. With Insns-first ordering, LSR picks formulas that
; keep pointer IVs separate at the cost of one extra stack spill slot
; (__v6clang_ss.axpy3+10), trading +1 register-pair pressure for fewer in-loop
; instructions per access (per LSR's own cost model — empirically the
; result regresses on V6CLANG, hence Insns-first is opt-in only).
;
; RUN: llc -march=v6clang -O2 -mv6clang-static-stack -mv6clang-no-spill-patched-reload -v6clang-lsr-strategy=insns-first < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

define dso_local void @axpy3(ptr nocapture writeonly %0, ptr nocapture readonly %1, ptr nocapture readonly %2, ptr nocapture readonly %3, i16 %4) norecurse {
  %6 = icmp eq i16 %4, 0
  br i1 %6, label %7, label %8

7:
  ret void

8:
  %9 = phi i16 [ %19, %8 ], [ 0, %5 ]
  %10 = getelementptr inbounds i16, ptr %1, i16 %9
  %11 = load i16, ptr %10, align 1
  %12 = getelementptr inbounds i16, ptr %2, i16 %9
  %13 = load i16, ptr %12, align 1
  %14 = add nsw i16 %13, %11
  %15 = getelementptr inbounds i16, ptr %3, i16 %9
  %16 = load i16, ptr %15, align 1
  %17 = add nsw i16 %14, %16
  %18 = getelementptr inbounds i16, ptr %0, i16 %9
  store i16 %17, ptr %18, align 1
  %19 = add nuw i16 %9, 1
  %20 = icmp eq i16 %19, %4
  br i1 %20, label %7, label %8
}

; Insns-first allocates an extra spill slot (+10) growing the static area
; from 10 to 12 bytes.

; CHECK-LABEL: axpy3:
; CHECK:       __v6clang_ss.axpy3+10
; CHECK:       .comm   __v6clang_ss.axpy3,12,1
