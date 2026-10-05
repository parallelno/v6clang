// O79 — MVI R, NN + ALU R → ALU-Immediate NN fold feature test.
//
// Each function exercises one of the eight i8 ALU operations being
// fed an immediate that ISel/post-RA materialized into a non-A GPR.
// After O79 the compiler should emit the immediate-form ALU op
// directly (ADI/ACI/SUI/SBI/ANI/XRI/ORI/CPI), saving 1B/4cc per
// fire and freeing the constant-holding register.

#include <stdint.h>

volatile uint8_t g_sink;

// case 1 — ADD imm (ADDr → ADI)
uint8_t fold_add(uint8_t a) {
    return a + 0x0F;
}

// case 2 — SUB imm (SUBr → SUI)
uint8_t fold_sub(uint8_t a) {
    return a - 0x05;
}

// case 3 — AND imm (ANAr → ANI)
uint8_t fold_and(uint8_t a) {
    return a & 0xF0;
}

// case 4 — OR imm (ORAr → ORI)
uint8_t fold_or(uint8_t a) {
    return a | 0x01;
}

// case 5 — XOR imm (XRAr → XRI)
uint8_t fold_xor(uint8_t a) {
    return a ^ 0x55;
}

// case 6 — CMP imm (CMPr → CPI), used as a branch test.
int fold_cmp(uint8_t a) {
    return (a == 0x42) ? 1 : 0;
}

// case 7 — chained ALU on the same value (two folds in a row).
uint8_t fold_chain(uint8_t a) {
    return ((a + 5) & 0xF0) ^ 0x10;
}

// case 8 — small spill driver to exercise the post-O64 reload+ALU
// shape. With many live i8 carriers the RA must spill, and the
// reload landing pad emits MVI R, 0 + ADD R consumed inside the
// epilogue chain. After O79 this collapses to ADI 0.
uint8_t fold_spill(uint8_t x0, uint8_t x1, uint8_t x2,
                   uint8_t x3, uint8_t x4, uint8_t x5,
                   uint8_t x6, uint8_t x7) {
    uint8_t s = x0;
    s ^= x1; s ^= x2; s ^= x3;
    s ^= x4; s ^= x5; s ^= x6;
    s ^= x7;
    return s;
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    g_sink = fold_add(0x10);
    g_sink = fold_sub(0x10);
    g_sink = fold_and(0xAB);
    g_sink = fold_or(0xAA);
    g_sink = fold_xor(0xAA);
    g_sink = (uint8_t)fold_cmp(0x42);
    g_sink = fold_chain(0x07);
    g_sink = fold_spill(1, 2, 3, 4, 5, 6, 7, 8);
    return 0;
}
