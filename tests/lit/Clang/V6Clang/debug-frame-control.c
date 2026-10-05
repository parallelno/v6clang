// RUN: clang -target i8080-unknown-v6clang -O1 -g -fno-v6clang-auto-include -nostdlib -Wl,-e,main %s -o %t.elf
// RUN: clang -target i8080-unknown-v6clang -O1 -fno-v6clang-auto-include -S %s -o - | FileCheck %s --check-prefix=ASM
// RUN: llvm-dwarfdump --debug-frame %t.elf | FileCheck %s --check-prefix=FRAME
// RUN: llvm-dwarfdump --verify %t.elf

// ASM-LABEL: tail:
// ASM: JMP callee

// FRAME-COUNT-5: FDE
// FRAME: DW_CFA_offset: PC -2
// FRAME: CFA=SP+2: PC=[CFA-2]

__attribute__((noinline)) int callee(int value) { return value + 1; }

__attribute__((noinline)) int tail(int value) { return callee(value); }

__attribute__((noinline)) int stack_args(int a, int b, int c, int d) {
  return a + b + c + d;
}

__attribute__((noinline)) int multiple_returns(int value) {
  volatile unsigned char slot[3];
  slot[0] = (unsigned char)value;
  if (value < 0)
    return slot[0];
  return slot[0] + 1;
}

int (*volatile keep_multiple_returns)(int) = multiple_returns;

int main(void) {
  return tail(1) + stack_args(1, 2, 3, 4) + multiple_returns(5);
}
