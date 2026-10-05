; RUN: llc -march=v6clang -O2 < %s | FileCheck %s
; RUN: llc -march=v6clang -O2 -v6clang-disable-type-narrowing < %s | FileCheck %s --check-prefix=NONARROW

target triple = "i8080-unknown-v6clang"

; V6ClangTypeNarrowing: narrow an i16 up/down-counter whose PHI or AddOp has
; extra arithmetic users beyond just the exit icmp (O85 feature, Case B).
;
; When narrowing fires:
;   - Exit check becomes a single CPI + JNZ (no hi-byte secondary block).
;   - Counter uses INR/DCR instead of INX/DCX.
;   - Extra users of the old i16 IV receive a zext of the new i8 IV.
;
; When narrowing must NOT fire:
;   - PHI user of the old i16 PHI (per-edge zext not implemented).
;   - Extra arithmetic user exists but NO icmp survives (Case A guard).

; ---------------------------------------------------------------------------
; Test A — ExtraPNUses: the i16 PHI itself has an extra arithmetic user.
; Loop: acc += acc ^ i;  for i = 0..63.
; After narrowing: i8 counter in A, CPI 0x40, no secondary hi-byte block.
; ---------------------------------------------------------------------------
; CHECK-LABEL: extra_pn_uses:
; CHECK:       INR
; CHECK:       CPI 0x40
; CHECK-NOT:   {{.*in Loop.*bb.*}}
; NONARROW-LABEL: extra_pn_uses:
; NONARROW:       INX
; NONARROW:       MVI {{.*}}, 0x40
define i16 @extra_pn_uses(i8 %seed) {
entry:
  %wide = zext i8 %seed to i16
  br label %loop
loop:
  %i   = phi i16 [ 0, %entry ], [ %i.next, %loop ]
  %acc = phi i16 [ %wide,  %entry ], [ %acc.next, %loop ]
  %xor = xor i16 %acc, %i              ; extra PN user of %i
  %acc.next = add i16 %acc, %xor
  %i.next = add nuw nsw i16 %i, 1
  %done = icmp eq i16 %i.next, 64
  br i1 %done, label %exit, label %loop
exit:
  ret i16 %acc.next
}

; ---------------------------------------------------------------------------
; Test B — ExtraAddUses: AddOp (i.next) has an extra arithmetic user.
; Loop: acc += acc ^ (i+1);  for i = 0..63.
; The i16 i.next is used both as loop IV increment AND in the XOR.
; After narrowing: same single-step CPI exit; zext of i.next.narrow inserted.
; ---------------------------------------------------------------------------
; CHECK-LABEL: extra_add_uses:
; CHECK:       INR
; CHECK:       CPI 0x41
; NONARROW-LABEL: extra_add_uses:
; NONARROW:       INX
; NONARROW:       MVI {{.*}}, 0x41
define i16 @extra_add_uses(i8 %seed) {
entry:
  %wide = zext i8 %seed to i16
  br label %loop
loop:
  %i   = phi i16 [ 0, %entry ], [ %i.next, %loop ]
  %acc = phi i16 [ %wide,  %entry ], [ %acc.next, %loop ]
  %i.next = add nuw nsw i16 %i, 1
  %xor = xor i16 %acc, %i.next         ; extra AddOp user of %i.next
  %acc.next = add i16 %acc, %xor
  %done = icmp eq i16 %i.next, 64
  br i1 %done, label %exit, label %loop
exit:
  ret i16 %acc.next
}

; ---------------------------------------------------------------------------
; Test C — down-counter with ExtraPNUses: step = -1, init fits in i8.
; Loop: acc += acc ^ i;  for i = 63 down to 1 (exit when i.next == 0).
; ---------------------------------------------------------------------------
; CHECK-LABEL: down_counter_extra_pn:
; CHECK:       DCR
; CHECK-NOT:   DCX
; NONARROW-LABEL: down_counter_extra_pn:
; NONARROW:       DCX
define i16 @down_counter_extra_pn(i8 %seed) {
entry:
  %wide = zext i8 %seed to i16
  br label %loop
loop:
  %i   = phi i16 [ 63, %entry ], [ %i.next, %loop ]
  %acc = phi i16 [ %wide,  %entry ], [ %acc.next, %loop ]
  %xor = xor i16 %acc, %i              ; extra PN user of %i
  %acc.next = add i16 %acc, %xor
  %i.next = add nsw i16 %i, -1
  %done = icmp eq i16 %i.next, 0
  br i1 %done, label %exit, label %loop
exit:
  ret i16 %acc.next
}

; ---------------------------------------------------------------------------
; Test D — PHI user of %i: a downstream phi takes %i as an incoming value.
; Cannot safely insert per-edge zext; narrowing must NOT fire.
; ---------------------------------------------------------------------------
; CHECK-LABEL: phi_user_rejected:
; CHECK-NOT:   INR
; CHECK:       INX
define i16 @phi_user_rejected(i8 %seed) {
entry:
  %wide = zext i8 %seed to i16
  br label %loop
loop:
  %i   = phi i16 [ 0, %entry ], [ %i.next, %loop ]
  %acc = phi i16 [ %wide,  %entry ], [ %acc.next, %loop ]
  %acc.next = add i16 %acc, %i
  %i.next = add nuw nsw i16 %i, 1
  %done = icmp eq i16 %i.next, 64
  br i1 %done, label %exit, label %loop
exit:
  ; A phi that takes %i as an incoming value from the loop — blocks narrowing.
  %result = phi i16 [ %i, %loop ]
  ret i16 %result
}

; ---------------------------------------------------------------------------
; Test E — extra PN user but no icmp (Case A guard): LPI has replaced the
; exit icmp with a pointer comparison, so no constant-bound icmp is visible.
; Without a bound to prove the range fits in i8, narrowing must NOT fire.
; ---------------------------------------------------------------------------
; CHECK-LABEL: no_icmp_extra_pn:
; CHECK-NOT:   INR
; CHECK:       INX
@arr_e = dso_local global [64 x i8] zeroinitializer, align 1
define i16 @no_icmp_extra_pn(i8 %seed) {
entry:
  %wide = zext i8 %seed to i16
  br label %loop
loop:
  %i   = phi i16 [ 0, %entry ], [ %i.next, %loop ]
  %acc = phi i16 [ %wide,  %entry ], [ %acc.next, %loop ]
  ; Array access (imagine LPI already converted it; we simulate post-LPI IR
  ; where the exit is inttoptr+icmp-null, but there is ALSO an extra PN user):
  %xor = xor i16 %acc, %i              ; extra PN user — would want narrowing
  %acc.next = add i16 %acc, %xor
  %i.next = add nuw nsw i16 %i, 1
  ; No icmp eq i16 here — exit is via a pointer compare (null sentinel),
  ; which the narrowing pass cannot use to prove range ⊆ [0, 255].
  %ptr = inttoptr i16 %i.next to ptr
  %done = icmp eq ptr %ptr, null
  br i1 %done, label %exit, label %loop
exit:
  ret i16 %acc.next
}
