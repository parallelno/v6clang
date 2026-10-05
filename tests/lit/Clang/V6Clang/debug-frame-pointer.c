// RUN: clang -target i8080-unknown-v6clang -O0 -fno-omit-frame-pointer -fno-v6clang-auto-include -S %s -o - | FileCheck %s --check-prefix=ASM
// RUN: clang -target i8080-unknown-v6clang -O0 -g -fno-omit-frame-pointer -fno-v6clang-auto-include -nostdlib -Wl,-e,main %s -o %t.elf
// RUN: llvm-dwarfdump --debug-frame %t.elf | FileCheck %s --check-prefix=FRAME
// RUN: llvm-dwarfdump --verify %t.elf

// ASM-LABEL: framed:
// ASM: PUSH B
// ASM: MOV B, H
// ASM-NEXT: MOV C, L
// ASM: MOV H, B
// ASM-NEXT: MOV L, C
// ASM-NEXT: SPHL
// ASM-NEXT: POP B
// ASM-NEXT: POP
// ASM-NEXT: POP
// ASM: RET

// FRAME: DW_CFA_def_cfa: SP +2
// FRAME: DW_CFA_def_cfa_offset: +8
// FRAME: DW_CFA_offset: BC -8
// FRAME: DW_CFA_def_cfa_register: BC
// FRAME: DW_CFA_def_cfa: SP +6
// FRAME: DW_CFA_restore: BC
// FRAME: DW_CFA_def_cfa_offset: +4
// FRAME: DW_CFA_def_cfa_offset: +2
// FRAME: CFA=BC+8: BC=[CFA-8], PC=[CFA-2]
// FRAME: CFA=SP+6: PC=[CFA-2]

volatile unsigned sink;

__attribute__((noinline))
unsigned framed(unsigned a, unsigned b) {
  volatile unsigned char data[5];
  data[0] = (unsigned char)a;
  data[4] = (unsigned char)b;
  sink = a + b;
  return sink + data[0] + data[4];
}

int main(void) { return (int)framed(0x1234, 0x5678); }
