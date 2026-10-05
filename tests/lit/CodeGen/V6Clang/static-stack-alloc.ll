; RUN: llc -march=v6clang -O2 -mv6clang-static-stack -mv6clang-no-spill-patched-reload < %s | FileCheck %s

; Test O10: Static Stack Allocation for Non-Reentrant Functions.
; Non-reentrant functions with spills should use STA/LDA/SHLD/LHLD
; for static memory access instead of DAD SP stack-relative sequences.

declare void @sink(i16)

; CHECK-LABEL: spill_test:
; Static mode: should use SHLD/LHLD for spills instead of DAD SP.
; CHECK-NOT: DAD SP
; CHECK: SHLD __v6clang_ss.spill_test
; CHECK: CALL sink
; CHECK: LHLD __v6clang_ss.spill_test
; CHECK-NOT: DAD SP
define i16 @spill_test(i16 %a, i16 %b) norecurse {
entry:
  %x = add i16 %a, 1
  %y = add i16 %b, 2
  call void @sink(i16 %x)
  %r = add i16 %y, %x
  ret i16 %r
}

; Verify that functions without norecurse still use DAD SP.
; CHECK-LABEL: recursive_func:
; CHECK: DAD SP
define i16 @recursive_func(i16 %n) {
entry:
  %cmp = icmp eq i16 %n, 0
  br i1 %cmp, label %base, label %recurse
base:
  ret i16 1
recurse:
  %nm1 = sub i16 %n, 1
  call void @sink(i16 %n)
  %r = call i16 @recursive_func(i16 %nm1)
  %res = add i16 %r, %n
  ret i16 %res
}
