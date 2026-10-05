; Verify O51: V6CLANG LSR formula tie-breaker defaults to Regs-first
; (auto-dispatch) and can be forced via -v6clang-lsr-strategy=regs-first.
;
; Regs-first is the default strategy for the four-pointer axpy3 loop. With
; the current static-stack and frame-index lowering pipeline, both auto and
; explicit regs-first use the same 12-byte static spill area.
;
; RUN: llc -march=v6clang -O2 -mv6clang-static-stack -mv6clang-no-spill-patched-reload < %s | FileCheck %s --check-prefix=AUTO
; RUN: llc -march=v6clang -O2 -mv6clang-static-stack -mv6clang-no-spill-patched-reload -v6clang-lsr-strategy=regs-first < %s | FileCheck %s --check-prefix=EXPLICIT

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

define dso_local void @axpy3(ptr nocapture writeonly %0, ptr nocapture readonly %1, ptr nocapture readonly %2, ptr nocapture readonly %3, i16 %4) norecurse optsize {
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

; Auto and explicit regs-first must agree on the current spill footprint.

; AUTO-LABEL: axpy3:
; AUTO:        __v6clang_ss.axpy3+10
; AUTO:        .comm   __v6clang_ss.axpy3,12,1

; EXPLICIT-LABEL: axpy3:
; EXPLICIT:     __v6clang_ss.axpy3+10
; EXPLICIT:     .comm   __v6clang_ss.axpy3,12,1
