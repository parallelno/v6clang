; RUN: clang --target=i8080-unknown-v6clang -c %s -o %t.o
; RUN: llvm-readobj -r --expand-relocs %t.o | FileCheck %s

; The V6CLANG asm parser accepts the lo8/hi8 byte-extraction prefix operators
;   <(expr)  -> low  byte of a (possibly link-time) 16-bit value -> R_V6CLANG_LO8 (3)
;   >(expr)  -> high byte of a (possibly link-time) 16-bit value -> R_V6CLANG_HI8 (4)
; These let inline asm take one byte of an address resolved at link time.

        .text
        .globl  f
f:
        MVI     H, >(sym)       ; high byte -> R_V6CLANG_HI8
        MVI     L, <(sym)       ; low  byte -> R_V6CLANG_LO8

        .data
sym:
        .byte   0x42

; CHECK:      Type: R_V6CLANG_HI8 (4)
; CHECK-NEXT: Symbol: {{.*}}
; CHECK:      Type: R_V6CLANG_LO8 (3)
; CHECK-NEXT: Symbol: {{.*}}
