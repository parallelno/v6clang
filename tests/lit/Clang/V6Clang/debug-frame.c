// RUN: clang -target i8080-unknown-v6clang -O0 -g -fno-v6clang-auto-include -nostdlib -Wl,-e,main %s -o %t.elf
// RUN: llvm-readelf -S %t.elf | FileCheck %s --check-prefix=SECTIONS
// RUN: llvm-dwarfdump --debug-frame %t.elf | FileCheck %s --check-prefix=FRAME
// RUN: llvm-dwarfdump --verify %t.elf

// SECTIONS: .debug_frame
// SECTIONS-NOT: .eh_frame

// FRAME: Return address column: 11
// FRAME: DW_CFA_def_cfa: SP +2
// FRAME: DW_CFA_offset: PC -2
// FRAME: DW_CFA_def_cfa_offset: +4
// FRAME: DW_CFA_def_cfa_offset: +6
// FRAME: DW_CFA_def_cfa_offset: +4
// FRAME: DW_CFA_def_cfa_offset: +2
// FRAME: DW_CFA_def_cfa: SP +2
// FRAME: DW_CFA_def_cfa_offset: +8
// FRAME: DW_CFA_def_cfa_offset: +2
// FRAME: DW_CFA_def_cfa: SP +2
// FRAME: DW_CFA_def_cfa_offset: +13
// FRAME: DW_CFA_def_cfa_offset: +2

typedef unsigned char u8;

__attribute__((noinline)) int frame2(int x) {
  volatile u8 data[2];
  data[0] = (u8)x;
  data[1] = (u8)(x + 1);
  return data[0] + data[1];
}

__attribute__((noinline)) int frame4(int x) {
  volatile u8 data[4];
  data[0] = (u8)x;
  data[3] = (u8)(x + 3);
  return data[0] + data[3];
}

__attribute__((noinline)) int frame7(int x) {
  volatile u8 data[7];
  data[0] = (u8)x;
  data[6] = (u8)(x + 6);
  return data[0] + data[6];
}

int (*volatile keep2)(int) = frame2;
int (*volatile keep4)(int) = frame4;
int (*volatile keep7)(int) = frame7;

int main(void) { return frame2(1) + frame4(2) + frame7(3); }
