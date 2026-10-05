; RUN: llc -march=v6clang -O2 < %s | FileCheck %s --check-prefix=IPRA
; RUN: llc -march=v6clang -O2 -enable-ipra=false < %s | FileCheck %s --check-prefix=NOIPRA

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@sink = global i16 0, align 1

define void @action_b() {
entry:
  store volatile i16 2, ptr @sink, align 1
  ret void
}

declare void @extern_action()

define i16 @test_external(i16 returned %x) {
entry:
  call void @extern_action()
  call void @action_b()
  ret i16 %x
}

define i16 @test_direct(i16 returned %x) {
entry:
  call void @action_b()
  ret i16 %x
}

; IPRA-LABEL: test_external:
; The extern_action call's clobbers are unknown, so %x is spilled to
; stack. O54 picks PUSH PSW (1B/16cc) over LXI+DAD+SPHL (5B/32cc) for
; the 2-byte even frame. Since PUSH PSW does not clobber HL, frame
; lowering no longer emits a redundant HL save in the prologue;
; the SPILL16 expansion handles HL preservation across the call.
; IPRA:       PUSH PSW
; IPRA-NEXT:  XCHG
; IPRA:       CALL extern_action
; IPRA-NEXT:  CALL action_b
; IPRA:       MOV E, M
; IPRA:       MOV D, M
; IPRA:       POP PSW

; IPRA-LABEL: test_direct:
; IPRA:       MOV D, H
; IPRA-NEXT:  MOV E, L
; IPRA-NEXT:  CALL action_b
; IPRA-NEXT:  XCHG
; IPRA-NEXT:  RET
; IPRA-NOT:   LXI H, 0xfffe
; IPRA-NOT:   PUSH D

; NOIPRA-LABEL: test_external:
; NOIPRA:       PUSH PSW
; NOIPRA-NEXT:  XCHG
; NOIPRA:       CALL extern_action
; NOIPRA-NEXT:  CALL action_b
; NOIPRA:       MOV E, M
; NOIPRA:       MOV D, M
; NOIPRA:       POP PSW

; NOIPRA-LABEL: test_direct:
; Without IPRA, %x must still be spilled around action_b's call (its
; clobbers are unknown to the register allocator before IPRA). But
; action_b's body is visible and contains no further calls, so the
; V6ClangStaticStackAlloc transitive-evidence analysis proves the function
; non-reentrant and O61 emits a self-modifying-code spill (SHLD imm of
; a later LXI H) instead of a dynamic-stack PUSH/POP. This is strictly
; better than the old PUSH PSW form.
; NOIPRA:       SHLD .LLo61_{{[0-9]+}}+1
; NOIPRA-NEXT:  CALL action_b
; NOIPRA:       LXI H, 0
; NOIPRA-NEXT:  RET
; NOIPRA-NOT:   PUSH PSW