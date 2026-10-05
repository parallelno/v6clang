; RUN: llc -march=v6clang < %s | FileCheck %s

; Test V6ClangLoadImmCombine cross-block value seeding: after a zero-test
; branch proves register values, redundant LXI/MVI should be eliminated.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare i16 @bar(i16)

; --- Test 1: 16-bit zero-test + JZ ??? LXI HL,0 eliminated ---
; if (x == 0) return bar(0); return x;
; After MOV A,H; ORA L; JZ target, the target block has HL==0.
; CHECK-LABEL: test_zero_tailcall:
; CHECK:       MOV A, H
; CHECK-NEXT:  ORA L
; CHECK-NEXT:  JZ bar
; CHECK-NOT:   LXI H, 0
define i16 @test_zero_tailcall(i16 %x) {
entry:
  %cmp = icmp eq i16 %x, 0
  br i1 %cmp, label %if.then, label %if.end

if.then:
  %call = tail call i16 @bar(i16 0)
  ret i16 %call

if.end:
  ret i16 %x
}

; --- Test 2: Negative test ??? NZ fallthrough should NOT seed from JZ ---
; if (x != 0) does not prove HL==0 on the NZ path.
; The structure is same as test 1 but the paths are swapped.
; CHECK-LABEL: test_nonzero_no_seed:
; CHECK:       MOV A, H
; CHECK-NEXT:  ORA L
; CHECK:       JZ
; CHECK:       RET
define i16 @test_nonzero_no_seed(i16 %x) {
entry:
  %cmp = icmp ne i16 %x, 0
  br i1 %cmp, label %if.then, label %if.else

if.then:
  ret i16 %x

if.else:
  %call = tail call i16 @bar(i16 0)
  ret i16 %call
}

; --- Test 3: Multiple predecessors ??? no seeding (LXI kept) ---
; CHECK-LABEL: test_multi_pred:
; CHECK:       LXI H, 0
define i16 @test_multi_pred(i16 %x, i16 %y) {
entry:
  %cmp1 = icmp eq i16 %x, 0
  br i1 %cmp1, label %merge, label %check2

check2:
  %cmp2 = icmp eq i16 %y, 0
  br i1 %cmp2, label %merge, label %done

merge:
  %call = tail call i16 @bar(i16 0)
  ret i16 %call

done:
  ret i16 %y
}
