// RUN: clang -target i8080-unknown-v6clang -O0 -g -fno-v6clang-auto-include -nostdlib -Wl,-e,main %s -o %t.elf
// RUN: llvm-dwarfdump --debug-info %t.elf | FileCheck %s
// RUN: llvm-dwarfdump --verify %t.elf

// CHECK: DW_AT_name{{.*}}("stack_values")
// CHECK: DW_TAG_formal_parameter
// CHECK: DW_AT_location
// CHECK: DW_AT_name{{.*}}("first")
// CHECK: DW_TAG_formal_parameter
// CHECK: DW_AT_location
// CHECK: DW_AT_name{{.*}}("second")
// CHECK: DW_TAG_formal_parameter
// CHECK: DW_AT_location
// CHECK: DW_AT_name{{.*}}("third")
// CHECK: DW_TAG_formal_parameter
// CHECK: DW_AT_location{{.*}}(DW_OP_fbreg
// CHECK: DW_AT_name{{.*}}("stack_parameter")

__attribute__((noinline))
int stack_values(int first, int second, int third, int stack_parameter) {
  volatile int local = first + second + third + stack_parameter;
  return local;
}

int (*volatile keep_stack_values)(int, int, int, int) = stack_values;

int main(void) { return stack_values(1, 2, 3, 4); }
