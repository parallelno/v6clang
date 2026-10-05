// RUN: clang -target i8080-unknown-v6clang -O1 -g -fno-v6clang-auto-include -nostdlib -Wl,-e,bytes %s -o %t.elf
// RUN: llvm-readobj --file-headers %t.elf | FileCheck %s --check-prefix=ELF
// RUN: llvm-dwarfdump --debug-info %t.elf | FileCheck %s --check-prefix=DWARF
// RUN: llvm-dwarfdump --verify %t.elf

// ELF: Format: elf32-v6clang
// ELF: Arch: i8080
// ELF: AddressSize: 32bit

// DWARF: addr_size = 0x02
// DWARF: DW_AT_frame_base{{.*}}DW_OP_call_frame_cfa
// DWARF-DAG: DW_OP_reg0 A
// DWARF-DAG: DW_OP_reg1 B
// DWARF-DAG: DW_OP_reg2 C
// DWARF-DAG: DW_OP_reg3 D
// DWARF-DAG: DW_OP_reg4 E
// DWARF-DAG: DW_OP_reg5 H
// DWARF-DAG: DW_OP_reg6 L
// DWARF-DAG: DW_OP_reg7 BC
// DWARF-DAG: DW_OP_reg8 DE
// DWARF-DAG: DW_OP_reg9 HL

volatile unsigned char byte_sink;
volatile unsigned word_sink;

__attribute__((noinline))
void bytes(unsigned char a, unsigned char b, unsigned char c,
           unsigned char d, unsigned char e, unsigned char f,
           unsigned char g) {
  byte_sink = a;
  byte_sink = b;
  byte_sink = c;
  byte_sink = d;
  byte_sink = e;
  byte_sink = f;
  byte_sink = g;
}

__attribute__((noinline))
void words(unsigned a, unsigned b, unsigned c) {
  word_sink = a;
  word_sink = b;
  word_sink = c;
}
