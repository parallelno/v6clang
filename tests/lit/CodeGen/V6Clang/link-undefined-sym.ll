; RUN: llc -mtriple=i8080-unknown-v6clang -filetype=obj -o %t.o %s
; RUN: not ld.lld -m elf32v6clang -Ttext=0x0100 -e main -o %t.elf %t.o 2>&1 | FileCheck %s

; Test: Undefined symbol detection.
; Linking a file that references an undefined function must produce an error.

; CHECK: undefined symbol: nonexistent_func

declare i8 @nonexistent_func()

define i8 @main() {
  %r = call i8 @nonexistent_func()
  ret i8 %r
}
