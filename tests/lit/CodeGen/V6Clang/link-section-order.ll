; RUN: llc -mtriple=i8080-unknown-v6clang -filetype=obj -o %t.o %s
; RUN: ld.lld -m elf32v6clang -Ttext=0x0100 -e main -Map=%t.map -o %t.elf %t.o
; RUN: llvm-objcopy -O binary %t.elf %t.bin
; RUN: FileCheck %s < %t.map

; Test: Memory map output and section ordering.
; ld.lld emits a per-section map; .text must appear before .data.

; CHECK: .text
; CHECK: .data

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@mydata = global i8 77

define i8 @main() {
  %v = load i8, ptr @mydata
  ret i8 %v
}
