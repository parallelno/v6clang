; RUN: llc -march=v6clang < %s | FileCheck %s
; RUN: llc -march=v6clang -v6clang-disable-type-narrowing < %s | FileCheck %s --check-prefix=OFF

target triple = "i8080-unknown-v6clang"

; Test V6ClangTypeNarrowing O90: relax PHI sibling guard for pure zero-test uses.
;
; When (and i16 PHI, C) is used ONLY for a zero-test (icmp eq/ne %, 0), the
; narrowed result is consumed only by a flag check (ANI sets Z directly) and
; never occupies a register.  The PHI sibling register-pressure guard should
; be relaxed in that case.
;
; The canonical trigger is the lfsr16 hot loop:
;   %lfsr = phi i16  — with i16 siblings (%acc, %i)
;   %7    = and i16 %lfsr, 1
;   %8    = icmp eq i16 %7, 0    ; ← sole user — pure zero-test
;
; After O90: AND16 (6 insn, 36cc) + CMP16_ZERO → ANI 1 (2B, 8cc).

; --------------------------------------------------------------------------
; Test 1: and i16 with small constant, PHI has i16 siblings, ONLY zero-test use.
; The guard must fire: emit ANI not LXI+AND16.
;
; CHECK-LABEL: and_zerotest_phi_siblings:
; CHECK-NOT:   LXI
; CHECK:       ANI
; CHECK-NOT:   ORA
; OFF-LABEL: and_zerotest_phi_siblings:
; OFF:         LXI
; --------------------------------------------------------------------------
define i8 @and_zerotest_phi_siblings(i16 %lfsr_init, i16 %acc_init) {
entry:
  br label %loop

loop:
  %lfsr = phi i16 [ %lfsr_init, %entry ], [ %lfsr_next, %loop ]
  %acc  = phi i16 [ %acc_init,  %entry ], [ %acc_next,  %loop ]
  %i    = phi i16 [ 0,          %entry ], [ %i_next,    %loop ]
  ; (lfsr & 1) used only for a zero-test — the O90 pattern
  %lsb  = and i16 %lfsr, 1
  %cmp  = icmp eq i16 %lsb, 0
  %lfsr_shr = lshr i16 %lfsr, 1
  %lfsr_xor = xor i16 %lfsr_shr, 180
  %lfsr_next = select i1 %cmp, i16 %lfsr_shr, i16 %lfsr_xor
  %acc_next  = xor i16 %acc, %lfsr_next
  %i_next = add i16 %i, 1
  %done   = icmp eq i16 %i_next, 16
  br i1 %done, label %exit, label %loop

exit:
  %r = trunc i16 %acc_next to i8
  ret i8 %r
}

; --------------------------------------------------------------------------
; Test 2: and i16 PHI, C — but result is also used outside the zero-test
; (stored / returned as i16). Guard must remain: should NOT narrow to ANI.
; After O93 the i16 op no longer needs an LXI scratch pair — it lowers via the
; V6CLANG_AND16_IMM constant-in-A expansion (ANA), preserving the high byte.
;
; CHECK-LABEL: and_live_result_no_narrow:
; CHECK-NOT:   ANI
; CHECK:       ANA
; --------------------------------------------------------------------------
define i16 @and_live_result_no_narrow(i16 %x) {
  %res = and i16 %x, 7
  ret i16 %res
}

; --------------------------------------------------------------------------
; Test 3: and i16 with LARGE constant (C > 0xFF). Must NOT narrow to ANI.
; After O93 this lowers via V6CLANG_AND16_IMM (two ANA bytes, no LXI scratch pair).
;
; CHECK-LABEL: and_large_const_no_narrow:
; CHECK-NOT:   ANI
; CHECK:       ANA
; --------------------------------------------------------------------------
define i16 @and_large_const_no_narrow(i16 %x) {
  %res = and i16 %x, 3855
  ret i16 %res
}

; --------------------------------------------------------------------------
; Test 4: and i16 PHI with C ≤ 0xFF, no i16 siblings — baseline (pre-existing
; behaviour, must still work correctly after O90).
; Loop that shifts until the LSB is set — %cmp actually drives the branch.
;
; CHECK-LABEL: and_no_siblings_baseline:
; CHECK:       ANI
; --------------------------------------------------------------------------
define i16 @and_no_siblings_baseline(i16 %x_init) {
entry:
  br label %loop

loop:
  %x    = phi i16 [ %x_init, %entry ], [ %x_next, %loop ]
  %lsb  = and i16 %x, 1
  %cmp  = icmp eq i16 %lsb, 0
  %x_next = lshr i16 %x, 1
  br i1 %cmp, label %loop, label %exit

exit:
  ret i16 %x
}
