; RUN: llc -march=v6clang -v6clang-disable-alloca-promote -v6clang-disable-static-stack-alloc < %s | FileCheck %s

; O54: SP adjustment via PUSH/POP, DCX/INX SP, or LXI+DAD+SPHL.
; Even sizes prefer PUSH/POP of a dead pair (1B/16cc per pair).
; When no dead pair is available, fall back to DCX/INX SP for n in {2,4}
; (no clobber, costs 1B/8cc per step), else LXI+DAD+SPHL (5B/32cc).

; -----------------------------------------------------------------------------
; 2-byte even frame: prologue/epilogue use PUSH/POP of one pair.
; CHECK-LABEL: frame2:
; CHECK:       PUSH B
; CHECK:       POP B
; CHECK-NEXT:  RET
define i8 @frame2(i8 %x) {
  %p = alloca [2 x i8]
  %g = getelementptr [2 x i8], ptr %p, i16 0, i16 0
  store i8 %x, ptr %g
  %v = load i8, ptr %g
  ret i8 %v
}

; -----------------------------------------------------------------------------
; 4-byte even frame: prologue/epilogue use PUSH/POP x2 of a dead pair.
; CHECK-LABEL: frame4:
; CHECK:       PUSH B
; CHECK-NEXT:  PUSH B
; CHECK:       POP B
; CHECK-NEXT:  POP B
; CHECK-NEXT:  RET
define i8 @frame4(i8 %x) {
  %p = alloca [4 x i8]
  %g = getelementptr [4 x i8], ptr %p, i16 0, i16 0
  store i8 %x, ptr %g
  %v = load i8, ptr %g
  ret i8 %v
}

; -----------------------------------------------------------------------------
; 1-byte odd frame: cannot be expressed as PUSH/POP, must use LXI+DAD+SPHL.
; CHECK-LABEL: frame_odd1:
; CHECK:       LXI H, 0xffff
; CHECK-NEXT:  DAD SP
; CHECK-NEXT:  SPHL
; CHECK:       LXI H, 1
; CHECK-NEXT:  DAD SP
; CHECK-NEXT:  SPHL
; CHECK-NEXT:  RET
define i8 @frame_odd1(i8 %x) {
  %p = alloca i8
  store i8 %x, ptr %p
  %v = load i8, ptr %p
  ret i8 %v
}
