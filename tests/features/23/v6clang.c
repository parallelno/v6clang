// Honest Store/Load Pseudo Defs — O20 feature test
// Tests that single-pointer store loops use HL directly
// without unnecessary DE→HL copy every iteration.
//
// Key patterns exercised:
// 1. Single-pointer store loop: pointer in HL, MOV M, r directly
// 2. Memcpy (dual pointer): one in HL, one in BC/DE, LDAX+MOV M

#include <stdint.h>

#define LEN 100

uint8_t array1[LEN];
uint8_t array2[LEN];

// Single-pointer store loop — main O20 target.
// Should use HL for pointer, emit MOV M, C directly.
// Before O20: pointer in DE, copy DE→HL every iteration (52cc/iter).
// After O20: pointer in HL, no copy (38cc/iter).
__attribute__((noinline))
void fill_array(uint8_t start_val) {
    for (uint8_t i = 0; i < LEN; ++i)
        array1[i] = start_val + i;
}

// Dual-pointer memcpy — should NOT regress.
// Two pointers: one in HL (store), one in BC/DE (load).
// Should emit LDAX BC + MOV M, A (14cc/iter).
__attribute__((noinline))
void copy_array(void) {
    for (uint8_t i = 0; i < LEN; ++i)
        array2[i] = array1[i];
}

int main(void) {
    fill_array(42);
    copy_array();
    return array2[0] + array2[99];
}
