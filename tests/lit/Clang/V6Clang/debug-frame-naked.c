// RUN: clang -target i8080-unknown-v6clang -O1 -g -fno-v6clang-auto-include -nostdlib -Wl,-e,main %s -o %t.elf
// RUN: llvm-dwarfdump --debug-frame %t.elf | FileCheck %s
// RUN: llvm-dwarfdump --verify %t.elf

// CHECK: FDE
// CHECK: DW_CFA_def_cfa: SP +2
// CHECK-NEXT: DW_CFA_undefined: PC
// CHECK: CFA=SP+2: PC=undefined

__attribute__((naked, noinline, used)) void naked_helper(void) {
  __asm__ volatile("RET");
}

int main(void) {
  naked_helper();
  return 0;
}
