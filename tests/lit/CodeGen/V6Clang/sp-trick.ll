; RUN: llc -march=v6clang < %s | FileCheck %s

; Test V6ClangSPTrickOpt: SP-trick optimization for memcpy.
; This pass replaces byte-by-byte copy sequences with the SP-based
; POP/SHLD fast copy when >= 6 bytes are copied.

; For now, this test verifies the pass doesn't break normal code.
; The SP-trick pattern matching operates on expanded memcpy sequences
; which will be more common after runtime library (M11) integration.

; CHECK-LABEL: test_sp_trick_basic:
; CHECK:       RET
define i8 @test_sp_trick_basic(i8 %a) {
  ret i8 %a
}

; Test with disabled pass.
; RUN: llc -march=v6clang -v6clang-disable-sp-trick < %s | FileCheck %s --check-prefix=OFF
; OFF-LABEL: test_sp_trick_basic:
; OFF:       RET
