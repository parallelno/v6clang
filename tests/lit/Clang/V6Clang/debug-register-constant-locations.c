// RUN: clang -target i8080-unknown-v6clang -O1 -g -fno-v6clang-auto-include -nostdlib -Wl,-e,main %s -o %t.elf
// RUN: llvm-dwarfdump --debug-info --debug-loclists %t.elf | FileCheck %s
// RUN: llvm-dwarfdump --verify %t.elf

// CHECK: DW_AT_name{{.*}}("register_values")
// CHECK: DW_AT_location{{.*}}(DW_OP_reg0 A)
// CHECK: DW_AT_name{{.*}}("byte")
// CHECK: DW_OP_reg9 HL
// CHECK: DW_AT_name{{.*}}("word")
// CHECK: DW_OP_reg8 DE
// CHECK: DW_AT_name{{.*}}("pointer")
// CHECK: DW_AT_name{{.*}}("constant_value")
// CHECK: DW_AT_const_value{{.*}}(42)
// CHECK: DW_AT_name{{.*}}("proven")

volatile int sink;

__attribute__((noinline))
int register_values(unsigned char byte, int word, int *pointer) {
  int local = word + byte;
  sink = *pointer + local;
  return local;
}

__attribute__((noinline))
int constant_value(void) {
  int proven = 42;
  sink = proven;
  return proven;
}

int main(void) {
  int value = 7;
  return register_values(3, 0x1234, &value) + constant_value();
}
