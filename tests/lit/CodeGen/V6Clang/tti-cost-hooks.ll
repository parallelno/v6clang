; Cost-model lit test for O22: V6CLANG-tuned TTI cost hooks.
; Verifies that getArithmeticInstrCost / getMemoryOpCost / getCmpSelInstrCost
; return V6CLANG-tuned numbers when enabled (default), and BasicTTI defaults
; when disabled via -v6clang-tti-cost-hooks=0.

; RUN: opt -mtriple=i8080-unknown-v6clang \
; RUN:   -passes='print<cost-model>' -cost-kind=throughput \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=ON

; RUN: opt -mtriple=i8080-unknown-v6clang -v6clang-tti-cost-hooks=0 \
; RUN:   -passes='print<cost-model>' -cost-kind=throughput \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=OFF

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

define void @costs(i8 %a, i16 %b, i32 %c, ptr %p, ptr %q) {
  %a2 = add i8 %a, 1
  %b2 = add i16 %b, 1
  %c2 = add i32 %c, 1
  %la = load i8, ptr %p
  %lb = load i16, ptr %q
  %ca = icmp eq i8 %a, %a2
  %cb = icmp eq i16 %b, %b2
  ret void
}

; --- Hooks ON (default) -----------------------------------------------------
; ON-LABEL: function 'costs':
; ON:       cost of 1 for instruction:   %a2 = add i8
; ON:       cost of 6 for instruction:   %b2 = add i16
; ON:       cost of 20 for instruction:   %c2 = add i32
; ON:       cost of 2 for instruction:   %la = load i8
; ON:       cost of 4 for instruction:   %lb = load i16
; ON:       cost of 1 for instruction:   %ca = icmp eq i8
; ON:       cost of 2 for instruction:   %cb = icmp eq i16

; --- Hooks OFF (BasicTTI fallback) ------------------------------------------
; OFF-LABEL: function 'costs':
; OFF:       cost of 2 for instruction:   %a2 = add i8
; OFF:       cost of 1 for instruction:   %b2 = add i16
; OFF:       cost of 2 for instruction:   %c2 = add i32
; OFF:       cost of 1 for instruction:   %la = load i8
; OFF:       cost of 1 for instruction:   %lb = load i16
; OFF:       cost of 1 for instruction:   %ca = icmp eq i8
; OFF:       cost of 1 for instruction:   %cb = icmp eq i16
