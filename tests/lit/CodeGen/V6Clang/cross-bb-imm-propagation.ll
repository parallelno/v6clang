; RUN: llc -march=v6clang < %s | FileCheck %s

; Test O29: Cross-BB Immediate Value Propagation
; 1) BR_CC16_IMM quick fix: skip hi-byte MVI when lo8 == hi8
; 2) General cross-BB propagation: inherit predecessor exit state

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare void @action_a()
declare void @action_b()

; --- Test 1: NE with lo8 == hi8 (0x4242) → only one MVI A, 0x42 ---
; CHECK-LABEL: test_ne_same_bytes:
; CHECK:       MVI A, 0x42
; CHECK-NEXT:  CMP L
; CHECK-NEXT:  JNZ
; CHECK-NOT:   MVI A, 0x42
; CHECK:       CMP H
define void @test_ne_same_bytes(i16 %x) {
entry:
  %cmp = icmp ne i16 %x, 16962
  br i1 %cmp, label %if.then, label %if.end

if.then:
  call void @action_a()
  br label %if.end

if.end:
  call void @action_b()
  ret void
}

; --- Test 2: EQ with lo8 == hi8 (0x4242) → only one MVI A, 0x42 ---
; CHECK-LABEL: test_eq_same_bytes:
; CHECK:       MVI A, 0x42
; CHECK-NEXT:  CMP L
; CHECK:       JNZ
; CHECK-NOT:   MVI A, 0x42
; CHECK:       CMP H
define void @test_eq_same_bytes(i16 %x) {
entry:
  %cmp = icmp eq i16 %x, 16962
  br i1 %cmp, label %if.then, label %if.end

if.then:
  call void @action_a()
  br label %if.end

if.end:
  call void @action_b()
  ret void
}

; --- Test 3: NE with lo8 != hi8 (0x1234) → both MVI instructions ---
; CHECK-LABEL: test_ne_diff_bytes:
; CHECK:       MVI A, 0x34
; CHECK:       CMP L
; CHECK:       MVI A, 0x12
; CHECK:       CMP H
define void @test_ne_diff_bytes(i16 %x) {
entry:
  %cmp = icmp ne i16 %x, 4660
  br i1 %cmp, label %if.then, label %if.end

if.then:
  call void @action_a()
  br label %if.end

if.end:
  call void @action_b()
  ret void
}

; --- Test 4: NE with 0x0101 → only one MVI A, 1 ---
; CHECK-LABEL: test_ne_0101:
; CHECK:       MVI A, 1
; CHECK-NEXT:  CMP L
; CHECK-NEXT:  JNZ
; CHECK-NOT:   MVI A, 1
; CHECK:       CMP H
define void @test_ne_0101(i16 %x) {
entry:
  %cmp = icmp ne i16 %x, 257
  br i1 %cmp, label %if.then, label %if.end

if.then:
  call void @action_a()
  br label %if.end

if.end:
  call void @action_b()
  ret void
}
