; RUN: llc -march=v6clang < %s | FileCheck %s
;
; O55 Pattern 2: `MVI A, 0` → `XRA A` peephole, gated on FLAGS-dead.
;
; Saves 1 byte / 4 cycles per safe instance.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; --- Positive: trailing constant zero, no flags consumer.       ---
; --- Expect:   XRA A ; RET (and NO `MVI A, 0`).                 ---
; CHECK-LABEL: const_zero:
; CHECK-NOT:   MVI{{.*}}A{{.*}}0
; CHECK:       XRA{{.*}}A
; CHECK-NEXT:  RET
define i8 @const_zero() {
  ret i8 0
}

; --- Positive: cold-path constant zero, FLAGS already consumed   ---
; --- by the JP that runs *before* the MVI A, 0.                  ---
; CHECK-LABEL: cold_zero:
; CHECK-NOT:   MVI{{.*}}A{{.*}}0
; CHECK:       XRA{{.*}}A
define i8 @cold_zero(i8 %a, i8 %b) {
  %c = icmp slt i8 %a, %b
  br i1 %c, label %lo, label %hi
lo:
  ret i8 0
hi:
  ret i8 7
}

; --- Negative: i32 add lowers to a multi-byte SBB chain whose CY is ---
; --- read by a subsequent JNC; the codegen materialises 0 into A    ---
; --- BETWEEN the SBB and the JNC. The peephole MUST decline.        ---
; --- Expect a `MVI A, 0` to remain on that path. (Other flag-       ---
; --- preserving MOVs may schedule between MVI and JNC.)             ---
; CHECK-LABEL: add_i32:
; CHECK:       SBB
; CHECK-NEXT:  MVI{{.*}}A{{.*}}0
; CHECK:       JNC
define i32 @add_i32(i32 %a, i32 %b) {
  %r = add i32 %a, %b
  ret i32 %r
}
