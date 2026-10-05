; RUN: llc -march=v6clang < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare dso_local i8 @bar(i8 noundef) local_unnamed_addr

; O80 (formerly O38): zero-tests no longer emit MOV A,r; ORA A. The
; V6CLANG_CMP8_ZERO pseudo expands by liveness:
;   %x in A, tested first      → ORA A      (shape 1)
;   %y in B, tested with A dead → XRA A; CMP B (shape 2)
;
; CHECK-LABEL: test_xra_cmp_jz:
; CHECK:       ORA A
; CHECK:       XRA A
; CHECK-NEXT:  CMP B
; CHECK-NOT:   MOV A, B
; CHECK-NOT:   CPI
define dso_local i8 @test_xra_cmp_jz(i8 noundef %x, i8 noundef %y) local_unnamed_addr {
  %cmpx = icmp eq i8 %x, 0
  br i1 %cmpx, label %test_y, label %call_bar

test_y:
  %cmpy = icmp eq i8 %y, 0
  br i1 %cmpy, label %ret_zero, label %call_bar_zero

call_bar:
  %r1 = tail call i8 @bar(i8 noundef %x)
  br label %exit

call_bar_zero:
  %r2 = tail call i8 @bar(i8 noundef 0)
  br label %exit

ret_zero:
  br label %exit

exit:
  %result = phi i8 [ %r1, %call_bar ], [ %r2, %call_bar_zero ], [ 0, %ret_zero ]
  ret i8 %result
}
