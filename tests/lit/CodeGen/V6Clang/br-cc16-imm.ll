; RUN: llc -march=v6clang -O2 < %s | FileCheck %s

; Test that NE comparison against a global+offset uses MVI+CMP, not LXI+MOV+CMP.
define void @ne_imm_global(ptr %p) {
; CHECK-LABEL: ne_imm_global:
; CHECK-NOT:   LXI {{[A-Z]+}}, arr+100
; CHECK:       MVI A, <(arr+100)
; CHECK:       CMP
; CHECK:       MVI A, >(arr+100)
; CHECK:       CMP
entry:
  %end = getelementptr i8, ptr @arr, i16 100
  %cmp = icmp ne ptr %p, %end
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

; Test that EQ against a global+offset uses MVI+CMP.
define void @eq_imm_global(ptr %p) {
; CHECK-LABEL: eq_imm_global:
; CHECK-NOT:   LXI {{[A-Z]+}}, arr+100
; CHECK:       MVI A, <(arr+100)
; CHECK:       CMP
; CHECK:       MVI A, >(arr+100)
; CHECK:       CMP
entry:
  %end = getelementptr i8, ptr @arr, i16 100
  %cmp = icmp eq ptr %p, %end
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

; Test that NE against a plain integer constant uses MVI+CMP.
; 1000 = 0x03E8, so lo=0xE8, hi=3.
define void @ne_imm_int(i16 %x) {
; CHECK-LABEL: ne_imm_int:
; CHECK-NOT:   LXI
; CHECK:       MVI A,
; CHECK:       CMP
; CHECK:       MVI A,
; CHECK:       CMP
entry:
  %cmp = icmp ne i16 %x, 1000
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

; Test that NE with a register RHS still uses MOV+CMP (reg variant).
define void @ne_reg(i16 %a, i16 %b) {
; CHECK-LABEL: ne_reg:
; CHECK:       MOV A,
; CHECK:       CMP
entry:
  %cmp = icmp ne i16 %a, %b
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

; Test that unsigned LT (not EQ/NE) still uses register variant even with constant.
define void @lt_still_register(i16 %x) {
; CHECK-LABEL: lt_still_register:
; CHECK:       SUB
; CHECK:       SBB
entry:
  %cmp = icmp ult i16 %x, 1000
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

@arr = global [100 x i8] zeroinitializer
declare void @use()
