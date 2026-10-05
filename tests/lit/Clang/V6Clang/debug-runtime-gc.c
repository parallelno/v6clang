// RUN: clang -target i8080-unknown-v6clang -O1 -g -nostdlib -Wl,-e,main %s -o %t.elf
// RUN: llvm-readelf -s %t.elf | FileCheck %s --check-prefix=SYMS
// RUN: llvm-dwarfdump --verify %t.elf

// SYMS: main
// SYMS-NOT: __mulqi3
// SYMS-NOT: __mulhi3
// SYMS-NOT: __udivhi3

int main(void) { return 0; }
