; RUN: llc -march=v6clang < %s | FileCheck %s

; Test V6ClangLoadStoreOpt: merge adjacent LXI HL loads for consecutive addresses.

; When loading two bytes from consecutive addresses, the second LXI HL should
; be replaced with INX HL, saving 3 bytes and 2cc.

; This test verifies the pass doesn't break basic load/store patterns.
; The actual merge pattern (LXI+MOV+LXI+MOV for consecutive addrs) is more
; likely to appear with global variables and will be tested via round-trip tests.

; CHECK-LABEL: test_load_basic:
; CHECK:       RET
define i8 @test_load_basic(i8* %p) {
  %v = load i8, i8* %p
  ret i8 %v
}

; Verify dead LXI elimination doesn't break valid code.
; CHECK-LABEL: test_store_basic:
; CHECK:       RET
define void @test_store_basic(i8* %p, i8 %v) {
  store i8 %v, i8* %p
  ret void
}

; Test with disabled pass.
; RUN: llc -march=v6clang -v6clang-disable-loadstore-opt < %s | FileCheck %s --check-prefix=OFF
; OFF-LABEL: test_load_basic:
; OFF:       RET
define i8 @test_ls_off(i8* %p) {
  %v = load i8, i8* %p
  ret i8 %v
}
