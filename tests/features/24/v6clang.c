// Pre-RA INX/DCX Pseudo — O41 feature test
// Tests that small-constant pointer arithmetic (±1..±3) uses INX/DCX
// pseudos instead of allocating a register pair for the constant.
//
// Key patterns exercised:
// 1. Single-pointer store loop with step +1 (fill_array)
// 2. Dual-pointer copy loop with step +1 (copy_loop)
// 3. General i16 add with small constant (add_small)

#include <stdint.h>

#define LEN 100

uint8_t array1[LEN];
uint8_t array2[LEN];

// Single-pointer store loop — main O41 target.
// ptr+1 should use INX without allocating a register pair for constant 1.
// Before O41: LXI BC, 1 in preheader, DAD BC → INX (BC wasted).
// After O41: V6CLANG_INX16 pseudo, no constant register needed.
__attribute__((noinline))
void fill_array(uint8_t start_val) {
    for (uint8_t i = 0; i < LEN; ++i)
        array1[i] = start_val + i;
}

// Dual-pointer copy loop — both pointers increment by 1.
// Should use INX for both source and destination pointers.
__attribute__((noinline))
void copy_loop(void) {
    for (uint8_t i = 0; i < LEN; ++i)
        array2[i] = array1[i];
}

// General i16 add with small constant — not pointer context.
// add i16 x, 2 should use 2×INX instead of LXI+ADD16.
__attribute__((noinline))
uint16_t add_small(uint16_t x) {
    return x + 2;
}

// Subtraction with small constant.
// sub i16 x, 1 should use DCX instead of LXI+SUB16.
__attribute__((noinline))
uint16_t sub_small(uint16_t x) {
    return x - 1;
}

int main(void) {
    fill_array(10);
    copy_loop();
    uint16_t a = add_small(100);
    uint16_t b = sub_small(200);
    return array2[0] + array2[99] + (uint8_t)a + (uint8_t)b;
}
