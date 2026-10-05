// RUN: clang -target i8080-unknown-v6clang -O1 -g -fno-v6clang-auto-include -nostdlib -Wl,-e,main %s -o %t-o1.elf
// RUN: llvm-dwarfdump --debug-info --debug-loclists %t-o1.elf | FileCheck %s
// RUN: llvm-dwarfdump --verify %t-o1.elf
// RUN: clang -target i8080-unknown-v6clang -O2 -g -fno-v6clang-auto-include -nostdlib -Wl,-e,main %s -o %t-o2.elf
// RUN: llvm-dwarfdump --debug-info --debug-loclists %t-o2.elf | FileCheck %s
// RUN: llvm-dwarfdump --verify %t-o2.elf
// RUN: clang -target i8080-unknown-v6clang -Os -g -fno-v6clang-auto-include -nostdlib -Wl,-e,main %s -o %t-os.elf
// RUN: llvm-dwarfdump --debug-info --debug-loclists %t-os.elf | FileCheck %s
// RUN: llvm-dwarfdump --verify %t-os.elf

// CHECK: DW_AT_name{{.*}}("o61_locations")
// CHECK: DW_TAG_formal_parameter
// CHECK: DW_AT_location{{.*}}loclist
// CHECK: DW_AT_name{{.*}}("input")
// CHECK: DW_TAG_variable
// CHECK: DW_AT_location{{.*}}loclist
// CHECK: DW_AT_name{{.*}}("first")
// CHECK: DW_TAG_variable
// CHECK: DW_AT_location{{.*}}loclist
// CHECK: DW_AT_name{{.*}}("second")
// CHECK: DW_TAG_variable
// CHECK: DW_AT_location{{.*}}loclist
// CHECK: DW_AT_name{{.*}}("third")
// CHECK: DW_LLE_offset_pair{{.*}}DW_OP_reg9 HL
// CHECK: DW_LLE_offset_pair{{.*}}DW_OP_addrx{{.*}}DW_OP_plus_uconst 0x1
// CHECK: DW_LLE_offset_pair{{.*}}DW_OP_reg9 HL
// CHECK: DW_LLE_offset_pair{{.*}}DW_OP_reg8 DE
// CHECK: DW_LLE_offset_pair{{.*}}DW_OP_reg7 BC

extern int transform(int);
extern void consume(int, int, int);

volatile int sink;

__attribute__((noinline))
int o61_locations(int input) {
  int first = transform(input);
  int second = transform(first);
  int third = transform(second);
  consume(first, second, third);
  sink = first + second + third;
  return second;
}

__attribute__((noinline))
int transform(int value) { return value + 1; }

__attribute__((noinline))
void consume(int first, int second, int third) {
  sink = first + second + third;
}

int main(void) { return o61_locations(3); }