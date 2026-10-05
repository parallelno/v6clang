; RUN: llc -march=v6clang -mtriple=i8080-unknown-v6clang -filetype=obj %s -o %t.o
; RUN: python %scripts/elf_text_hex.py %t.o | FileCheck %s

; ADI 0x0A (0xC6 0x0A) + RET (0xC9)
; CHECK: C6 0A C9
define i8 @add_imm(i8 %a) {
  %c = add i8 %a, 10
  ret i8 %c
}
