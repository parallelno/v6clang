; RUN: llc -mtriple=i8080-unknown-v6clang -filetype=obj -o %t_a.o %s
; RUN: llc -mtriple=i8080-unknown-v6clang -filetype=obj -o %t_b.o %S/Inputs/link-global-data-b.ll
; RUN: ld.lld -m elf32v6clang -Ttext=0x0100 -e main -o %t.elf %t_a.o %t_b.o
; RUN: llvm-objcopy -O binary %t.elf %t.bin
; RUN: python -c "import sys; d=open(sys.argv[1],'rb').read(); print(len(d),'bytes'); assert len(d)>0" %t.bin

; Test: Cross-file global variable access. main.o reads a global defined in b.o.
; This tests 16-bit address relocations across objects.
; Success = ld.lld exits 0 and llvm-objcopy produces non-empty binary.

@shared_val = external global i8

define i8 @main() {
  %v = load i8, ptr @shared_val
  ret i8 %v
}
