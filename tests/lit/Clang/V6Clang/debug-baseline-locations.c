// RUN: clang -target i8080-unknown-v6clang -O0 -g -fno-v6clang-auto-include -nostdlib -Wl,-e,main %s -o %t.elf
// RUN: llvm-dwarfdump --debug-info %t.elf | FileCheck %s
// RUN: llvm-dwarfdump --verify %t.elf

// CHECK: DW_AT_name{{.*}}("static_vars")
// CHECK: DW_TAG_formal_parameter
// CHECK: DW_AT_location{{.*}}(DW_OP_addrx
// CHECK: DW_AT_name{{.*}}("parameter")
// CHECK: DW_TAG_variable
// CHECK: DW_AT_location{{.*}}(DW_OP_addrx {{.*}} DW_OP_plus_uconst 0x2)
// CHECK: DW_AT_name{{.*}}("local")
// CHECK: DW_TAG_variable
// CHECK: DW_AT_location{{.*}}(DW_OP_addrx {{.*}} DW_OP_plus_uconst 0x4)
// CHECK: DW_AT_name{{.*}}("addressable")
// CHECK: DW_AT_frame_base{{.*}}(DW_OP_call_frame_cfa, DW_OP_consts -14, DW_OP_plus)
// CHECK: DW_AT_name{{.*}}("dynamic_vars")
// CHECK: DW_TAG_formal_parameter
// CHECK: DW_AT_location{{.*}}(DW_OP_fbreg +10)
// CHECK: DW_AT_name{{.*}}("parameter")
// CHECK: DW_TAG_variable
// CHECK: DW_AT_location{{.*}}(DW_OP_fbreg +8)
// CHECK: DW_AT_name{{.*}}("local")
// CHECK: DW_TAG_variable
// CHECK: DW_AT_location{{.*}}(DW_OP_fbreg +6)
// CHECK: DW_AT_name{{.*}}("addressable")

volatile int sink;

__attribute__((noinline))
int static_vars(int parameter) {
  int local = parameter + 0x123;
  volatile int addressable = local + 1;
  sink = addressable;
  return local;
}

__attribute__((noinline))
int dynamic_vars(int parameter) {
  int local = parameter + 0x234;
  volatile int addressable = local + 1;
  sink = addressable;
  return local;
}

int (*volatile keep_dynamic)(int) = dynamic_vars;

int main(void) { return static_vars(0x1122) + dynamic_vars(0x3344); }
