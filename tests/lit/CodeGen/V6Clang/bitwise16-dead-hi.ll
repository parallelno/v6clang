; RUN: llc -march=v6clang < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; O89: Dead high-byte elision in V6CLANG_AND16 / V6CLANG_OR16 / V6CLANG_XOR16.
;
; When the result of a 16-bit bitwise op is immediately truncated to i8
; (DstHi is dead), the hi-byte ALU instructions must NOT be emitted.
;
; ─── XOR dead-hi ────────────────────────────────────────────────────────────
; After O89 only the lo-byte XRA fires; no second XRA with a GP register.
; CHECK-LABEL: xor16_dead_hi:
; CHECK:       XRA {{[BCDEHL]}}
; CHECK-NOT:   XRA {{[BCDEHL]}}
define dso_local i8 @xor16_dead_hi(i16 noundef %a, i16 noundef %b) local_unnamed_addr {
  %r = xor i16 %a, %b
  %t = trunc i16 %r to i8
  ret i8 %t
}

; ─── OR dead-hi ─────────────────────────────────────────────────────────────
; CHECK-LABEL: or16_dead_hi:
; CHECK:       ORA {{[BCDEHL]}}
; CHECK-NOT:   ORA {{[BCDEHL]}}
define dso_local i8 @or16_dead_hi(i16 noundef %a, i16 noundef %b) local_unnamed_addr {
  %r = or i16 %a, %b
  %t = trunc i16 %r to i8
  ret i8 %t
}

; ─── AND dead-hi ────────────────────────────────────────────────────────────
; CHECK-LABEL: and16_dead_hi:
; CHECK:       ANA {{[BCDEHL]}}
; CHECK-NOT:   ANA {{[BCDEHL]}}
define dso_local i8 @and16_dead_hi(i16 noundef %a, i16 noundef %b) local_unnamed_addr {
  %r = and i16 %a, %b
  %t = trunc i16 %r to i8
  ret i8 %t
}

; ─── XOR dead-hi → compare to zero ─────────────────────────────────────────
; Only lo-byte XRA (register operand) from XOR16; the XRA A from CMP8_ZERO
; (shape 2 zero-clear) is allowed.
; CHECK-LABEL: xor16_cmp_zero:
; CHECK:       XRA {{[BCDEHL]}}
; CHECK-NOT:   XRA {{[BCDEHL]}}
define dso_local i1 @xor16_cmp_zero(i16 noundef %a, i16 noundef %b) local_unnamed_addr {
  %r = xor i16 %a, %b
  %t = trunc i16 %r to i8
  %c = icmp eq i8 %t, 0
  ret i1 %c
}

; ─── AND dead-hi → compare to zero ─────────────────────────────────────────
; CHECK-LABEL: and16_cmp_zero:
; CHECK:       ANA {{[BCDEHL]}}
; CHECK-NOT:   ANA {{[BCDEHL]}}
define dso_local i1 @and16_cmp_zero(i16 noundef %a, i16 noundef %b) local_unnamed_addr {
  %r = and i16 %a, %b
  %t = trunc i16 %r to i8
  %c = icmp eq i8 %t, 0
  ret i1 %c
}

; ─── XOR live-hi (control case) — full 16-bit result used ───────────────────
; Both hi-byte instructions MUST appear.
; CHECK-LABEL: xor16_live_hi:
; CHECK:       XRA {{[BCDEHL]}}
; CHECK:       XRA {{[BCDEHL]}}
define dso_local i16 @xor16_live_hi(i16 noundef %a, i16 noundef %b) local_unnamed_addr {
  %r = xor i16 %a, %b
  ret i16 %r
}

; ─── OR live-hi (control case) ──────────────────────────────────────────────
; CHECK-LABEL: or16_live_hi:
; CHECK:       ORA {{[BCDEHL]}}
; CHECK:       ORA {{[BCDEHL]}}
define dso_local i16 @or16_live_hi(i16 noundef %a, i16 noundef %b) local_unnamed_addr {
  %r = or i16 %a, %b
  ret i16 %r
}

; ─── AND live-hi (control case) ─────────────────────────────────────────────
; CHECK-LABEL: and16_live_hi:
; CHECK:       ANA {{[BCDEHL]}}
; CHECK:       ANA {{[BCDEHL]}}
define dso_local i16 @and16_live_hi(i16 noundef %a, i16 noundef %b) local_unnamed_addr {
  %r = and i16 %a, %b
  ret i16 %r
}
