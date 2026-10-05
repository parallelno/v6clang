; RUN: llc -march=v6clang -mtriple=i8080-unknown-v6clang -filetype=obj %s -o %t.o
; RUN: python %scripts/elf_text_hex.py %t.o | FileCheck %s

; Branch encoding test: conditional branch uses JNZ/JZ (3-byte) with address fixups.
; The .text section bytes will have branch targets as relocations (zeros before linking).
; We verify the opcodes are correct.

; ORA A = B7 (zero-test optimization replaces CPI 0x00 with ORA A)
; JZ = CA xx xx (branch-opt inverts JNZ+JMP into JZ, eliminating JMP)
; MVI A, 0x02 = 3E 02
; RET = C9
; INR A = 3C  (LoadImmCombine: A is known 0 on JZ target, MVI A,1 → INR A)
; RET = C9

; Verify opcodes: ORA_A(B7), JZ(CA), MVI(3E) 02, RET(C9), INR(3C), RET(C9)
; Branch addresses are zero (unresolved relocations in .o file)
; Branch-opt inverted the conditional and removed the unconditional JMP.
; CHECK: B7 CA 00 00 3E 02 C9 3C C9
define i8 @branch(i8 %x) {
entry:
  %cmp = icmp eq i8 %x, 0
  br i1 %cmp, label %then, label %else

then:
  ret i8 1

else:
  ret i8 2
}
