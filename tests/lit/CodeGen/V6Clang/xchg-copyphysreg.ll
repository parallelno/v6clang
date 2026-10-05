; RUN: llc -march=v6clang < %s | FileCheck %s

; O32: XCHG in copyPhysReg — when copying DE↔HL with KillSrc=true,
; emit XCHG (1B/4cc) instead of two MOVs (2B/16cc).

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; The second i16 arg arrives in DE. Returning it copies DE→HL with KillSrc=true.
; CHECK-LABEL: return_second:
; CHECK:       XCHG
; CHECK-NEXT:  RET
; CHECK-NOT:   MOV	H, D
; CHECK-NOT:   MOV	L, E
define i16 @return_second(i16 %a, i16 %b) {
  ret i16 %b
}
