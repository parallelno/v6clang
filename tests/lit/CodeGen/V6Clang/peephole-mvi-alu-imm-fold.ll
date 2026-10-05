; RUN: llc -march=v6clang -O2 -mv6clang-spill-patched-reload < %s | FileCheck %s
; RUN: llc -march=v6clang -O2 -mv6clang-spill-patched-reload \
; RUN:     -v6clang-disable-mvi-alu-fold < %s | FileCheck --check-prefix=DIS %s
;
; O79: `MVI R, NN; ... ; ALU R` -> `... ; ALU-immediate NN` fold
; when R is dead after the ALU op and nothing in between reads/writes R.
;
; Saves 1B / 4cc per fire and frees R for register allocation.
;
; The natural ISel paths already select ALU-immediate forms when an
; operand is a compile-time constant. The fold targets the residual
; post-RA O61 patched-reload landing pads, where the spill emits
;   STA  .LLo61_0+1
; and the reload site emits
;   .LLo61_0:
;     MVI  R, 0
;     XRA  R      ; or any other ALU-on-R consumer
;
; O79 collapses the reload to
;   .LLo61_0:
;     XRI  0
;
; preserving the `.LLo61_0:` label and the imm byte offset (+1 from
; the label still lands on the imm byte of the new ALU-immediate
; instruction, which has the same 2-byte opcode+imm layout as MVI).

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; Eight i8 args force a static-stack spill: x0..x4 are passed in
; A,B,C,D,E and x5..x7 on the stack. The chained XOR through the
; accumulator forces RA to spill at least one carrier through a
; non-A GR8, lowered by O61 (Stage 6) to a patched-reload landing
; pad whose reload site is `MVI R, 0; XRA R` -- exactly the O79
; fold target.
;
; CHECK-LABEL: fold_spill:
; CHECK:       LXI H, .LLo61_0+1
; CHECK-NEXT:  MOV M, B
; CHECK:       .LLo61_0:
; CHECK-NEXT:  XRI     0
; CHECK-NOT:   MVI     {{[BCDEHL]}}, 0
;
; DIS-LABEL:   fold_spill:
; DIS:         LXI H, .LLo61_0+1
; DIS-NEXT:    MOV M, B
; DIS:         .LLo61_0:
; DIS-NEXT:    MVI     {{[BCDEHL]}}, 0
; DIS-NEXT:    XRA     {{[BCDEHL]}}
define i8 @fold_spill(i8 %x0, i8 %x1, i8 %x2, i8 %x3,
                       i8 %x4, i8 %x5, i8 %x6, i8 %x7) norecurse {
  %t1 = xor i8 %x1, %x0
  %t2 = xor i8 %t1, %x2
  %t3 = xor i8 %t2, %x3
  %t4 = xor i8 %t3, %x4
  %t5 = xor i8 %t4, %x5
  %t6 = xor i8 %t5, %x6
  %t7 = xor i8 %t6, %x7
  ret i8 %t7
}
