; RUN: llc -march=v6clang < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; O93: V6CLANG_AND16_IMM / V6CLANG_OR16_IMM / V6CLANG_XOR16_IMM.
;
; A 16-bit bitwise op against a compile-time constant must NOT materialise the
; constant into a scratch register pair (no LXI). Instead the constant is loaded
; into A byte-wise and the cheaper 4cc register ALU form is applied. Trivial
; bytes (0x00 / 0xFF identities) fold away.

; ─── XOR full-width constant (both bytes non-trivial) ───────────────────────
; CHECK-LABEL: xor16_const:
; CHECK-NOT:   LXI
; CHECK:       MVI A, 0x3c
; CHECK:       XRA L
; CHECK:       MOV L, A
; CHECK:       MVI A, 0xb4
; CHECK:       XRA H
; CHECK:       MOV H, A
define dso_local i16 @xor16_const(i16 noundef %x) local_unnamed_addr {
  %r = xor i16 %x, 46140  ; 0xB43C
  ret i16 %r
}

; ─── XOR hi-only (lo byte 0x00 is a XOR identity → folded) ──────────────────
; CHECK-LABEL: xor16_hi_only:
; CHECK-NOT:   LXI
; CHECK-NOT:   XRA L
; CHECK:       MVI A, 0xb4
; CHECK:       XRA H
; CHECK:       MOV H, A
define dso_local i16 @xor16_hi_only(i16 noundef %x) local_unnamed_addr {
  %r = xor i16 %x, 46080  ; 0xB400
  ret i16 %r
}

; ─── OR lo-only (hi byte 0x00 is an OR identity → folded) ───────────────────
; CHECK-LABEL: or16_lo_only:
; CHECK-NOT:   LXI
; CHECK:       MVI A, 0x80
; CHECK:       ORA L
; CHECK:       MOV L, A
; CHECK-NOT:   ORA H
define dso_local i16 @or16_lo_only(i16 noundef %x) local_unnamed_addr {
  %r = or i16 %x, 128  ; 0x0080
  ret i16 %r
}

; ─── AND clearing the low byte: lo 0x00 → MVI L,0 ; hi 0xFF → AND identity ───
; CHECK-LABEL: and16_clear_lo:
; CHECK-NOT:   LXI
; CHECK:       MVI L, 0
; CHECK-NOT:   ANA
define dso_local i16 @and16_clear_lo(i16 noundef %x) local_unnamed_addr {
  %r = and i16 %x, 65280  ; 0xFF00
  ret i16 %r
}

; ─── AND with full mask (both bytes non-trivial) ────────────────────────────
; CHECK-LABEL: and16_mask:
; CHECK-NOT:   LXI
; CHECK:       MVI A, 0xf
; CHECK:       ANA L
; CHECK:       MOV L, A
; CHECK:       MVI A, 0xf0
; CHECK:       ANA H
; CHECK:       MOV H, A
define dso_local i16 @and16_mask(i16 noundef %x) local_unnamed_addr {
  %r = and i16 %x, 61455  ; 0xF00F
  ret i16 %r
}

; ─── Dead-hi: (u8)(x ^ C) — only the low byte is used, so DAGCombiner narrows
; the whole op to i8 (XRI), which is even better than the _IMM expansion. ────
; CHECK-LABEL: xor16_imm_dead_hi:
; CHECK-NOT:   LXI
; CHECK:       XRI 0x3c
; CHECK-NOT:   MVI A, 0xb4
define dso_local i8 @xor16_imm_dead_hi(i16 noundef %x) local_unnamed_addr {
  %r = xor i16 %x, 46140  ; 0xB43C
  %t = trunc i16 %r to i8
  ret i8 %t
}

; ─── Control: register RHS must still use the reg/reg V6CLANG_XOR16 path ─────────
; (two XRA against GP registers, lo and hi).
; CHECK-LABEL: xor16_reg:
; CHECK:       XRA
; CHECK:       XRA
define dso_local i16 @xor16_reg(i16 noundef %a, i16 noundef %b) local_unnamed_addr {
  %r = xor i16 %a, %b
  ret i16 %r
}

; ─── Control: narrowable zero-test (C <= 0xFF, only used by icmp) stays on the
; O90 i8-narrowing path → ANI, no _IMM expansion. ───────────────────────────
; CHECK-LABEL: and16_zero_test:
; CHECK:       ANI 1
define dso_local i1 @and16_zero_test(i16 noundef %x) local_unnamed_addr {
  %r = and i16 %x, 1
  %c = icmp ne i16 %r, 0
  ret i1 %c
}
