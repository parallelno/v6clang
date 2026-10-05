; RUN: llc -mtriple=i8080-unknown-v6clang -filetype=obj -o %t_main.o %s
; RUN: llc -mtriple=i8080-unknown-v6clang -filetype=obj -o %t_helper.o %S/Inputs/link-helper.ll
; RUN: ld.lld -m elf32v6clang -Ttext=0x0100 -e main -o %t.elf %t_main.o %t_helper.o
; RUN: llvm-objcopy -O binary %t.elf %t.bin
; RUN: python -c "import sys; d=open(sys.argv[1],'rb').read(); print(len(d),'bytes'); assert len(d)>0" %t.bin

; Test: Cross-file function call. main.o calls helper() defined in helper.o.
; The linker must resolve the cross-object symbol reference.
; Success = ld.lld exits 0 and llvm-objcopy produces non-empty binary.

declare i8 @helper(i8 %x)

define i8 @main() {
  %r = call i8 @helper(i8 42)
  ret i8 %r
}
