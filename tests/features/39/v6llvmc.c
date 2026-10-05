// Test case for O61 Stage 5: DE/BC i16 spill sources.
//
// Stage 5 widens O61 from "spill source must be HL" (Stages 1-4) to
// "spill source in {HL, DE, BC}". The reload-target set ({HL, DE, BC})
// and i8 paths are unchanged.
//
// Compile:
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\39\v6clang.c -o tests\features\39\v6clang_new01.asm \
//       -mllvm -mv6clang-spill-patched-reload \
//       -mllvm -v6clang-disable-shld-lhld-fold

__attribute__((leaf)) extern unsigned int op_u16(unsigned int x);
__attribute__((leaf)) extern unsigned int op2_u16(unsigned int x);
__attribute__((leaf)) extern void use3_u16(unsigned int a, unsigned int b,
                                           unsigned int c);
__attribute__((leaf)) extern void use2_u16(unsigned int a, unsigned int b);

// Three i16 values held across two A/HL-clobbering calls. The RA
// is forced to spill at least one to DE or BC (HL is occupied by
// the call returns). Stage 4 rejects (spill source != HL); Stage 5
// must patch with `XCHG; SHLD .Lo61_N+1; [XCHG]` (DE) or
// `[PUSH H;] MOV L,C; MOV H,B; SHLD .Lo61_N+1; [POP H]` (BC).
unsigned int de_bc_three(unsigned int x, unsigned int y, unsigned int z) {
    unsigned int a = op_u16(x);   // HL
    unsigned int b = op2_u16(y);  // HL — a spilled
    unsigned int c = op_u16(z);   // HL — a, b spilled
    use3_u16(a, b, c);
    return (unsigned int)(a + b + c);
}

// Single DE-source spill, single HL-target reload. Smallest Stage 5
// shape.
unsigned int de_one_reload(unsigned int x, unsigned int y) {
    unsigned int a = op_u16(x);   // HL
    unsigned int b = op2_u16(y);  // HL — a spilled (likely DE-sourced)
    return (unsigned int)(a + b);
}

int main(void) {
    use2_u16(de_bc_three(0x1111, 0x2222, 0x3333),
             de_one_reload(0x4444, 0x5555));
    return 0;
}
