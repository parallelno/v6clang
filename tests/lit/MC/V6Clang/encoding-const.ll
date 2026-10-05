; RUN: llc -march=v6clang -mtriple=i8080-unknown-v6clang -filetype=obj %s -o %t.o
; RUN: python %scripts/elf_text_hex.py %t.o | FileCheck %s

; MVI A, 0xFF (0x3E 0xFF) + RET (0xC9)
; CHECK: 3E FF C9
define i8 @const_ff() {
  ret i8 255
}
