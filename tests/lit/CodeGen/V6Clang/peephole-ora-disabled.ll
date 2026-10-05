; RUN: llc -march=v6clang -v6clang-disable-zero-test-opt < %s | FileCheck %s

; After O80, i8 zero-tests are emitted via the V6CLANG_CMP8_ZERO pseudo and
; never go through CPI 0 / V6ClangZeroTestOpt. The disable flag therefore
; has no effect on this path — the post-RA expander still produces ORA A
; (shape 1, since %a arrives in A).
; CHECK-LABEL: test_disabled:
; CHECK:       ORA A
; CHECK-NOT:   CPI
define i8 @test_disabled(i8 %a) {
entry:
  %c = icmp eq i8 %a, 0
  br i1 %c, label %then, label %else
then:
  ret i8 1
else:
  ret i8 0
}
