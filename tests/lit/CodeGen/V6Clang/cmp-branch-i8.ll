; RUN: llc -march=v6clang < %s | FileCheck %s

; Test conditional branch (eq) — CMP then Jcc
; CHECK-LABEL: branch_eq:
; CHECK:       CMP B
; CHECK-NEXT:  J{{NZ|Z}}
define i8 @branch_eq(i8 %a, i8 %b) {
entry:
  %c = icmp eq i8 %a, %b
  br i1 %c, label %then, label %else
then:
  ret i8 1
else:
  ret i8 0
}

; Test conditional branch (unsigned less than) — CMP then Jcc
; CHECK-LABEL: branch_ult:
; CHECK:       CMP B
; CHECK-NEXT:  J{{NC|C}}
define i8 @branch_ult(i8 %a, i8 %b) {
entry:
  %c = icmp ult i8 %a, %b
  br i1 %c, label %then, label %else
then:
  ret i8 1
else:
  ret i8 0
}

; Test conditional branch (signed less than) — CMP then Jcc
; CHECK-LABEL: branch_slt:
; CHECK:       CMP B
; CHECK-NEXT:  J{{P|M}}
define i8 @branch_slt(i8 %a, i8 %b) {
entry:
  %c = icmp slt i8 %a, %b
  br i1 %c, label %then, label %else
then:
  ret i8 1
else:
  ret i8 0
}

; Test compare with immediate
; CHECK-LABEL: branch_eq_imm:
; CHECK:       CPI 0x2a
; CHECK-NEXT:  J{{NZ|Z}}
define i8 @branch_eq_imm(i8 %a) {
entry:
  %c = icmp eq i8 %a, 42
  br i1 %c, label %then, label %else
then:
  ret i8 1
else:
  ret i8 0
}
