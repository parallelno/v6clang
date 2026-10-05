; RUN: llc -mtriple=i8080-unknown-v6clang -filetype=obj -o %t_main.o %s
; RUN: llc -mtriple=i8080-unknown-v6clang -filetype=obj -o %t_helper.o %S/Inputs/link-helper.ll
; RUN: ld.lld -m elf32v6clang -Ttext=0x0100 -e main -o %t_0100.elf %t_main.o %t_helper.o
; RUN: ld.lld -m elf32v6clang -Ttext=0x8000 -e main -o %t_8000.elf %t_main.o %t_helper.o
; RUN: llvm-objcopy -O binary %t_0100.elf %t_0100.bin
; RUN: llvm-objcopy -O binary %t_8000.elf %t_8000.bin
; RUN: python -c "import sys; open(sys.argv[2],'w').write(' '.join(f'{b:02X}' for b in open(sys.argv[1],'rb').read()))" %t_0100.bin %t_0100.hex
; RUN: python -c "import sys; open(sys.argv[2],'w').write(' '.join(f'{b:02X}' for b in open(sys.argv[1],'rb').read()))" %t_8000.bin %t_8000.hex
; RUN: not diff %t_0100.hex %t_8000.hex

; Test: Start address relocation.
; The same program linked at base 0x0100 and 0x8000 must produce different
; binaries (because CALL addresses are relocated).
; The 'not diff' checks the files are different.

declare i8 @helper(i8 %x)

define i8 @main() {
  %r = call i8 @helper(i8 7)
  ret i8 %r
}
