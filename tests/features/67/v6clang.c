// O85 feature test — TypeNarrowing: narrow i16 up-counter when IV has arithmetic users.
// Used for:
//   Baseline:  llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S -mllvm --v6clang-disable-type-narrowing tests\features\67\v6clang.c -o tests\features\67\v6clang_old.asm
//   Post-O85:  llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S tests\features\67\v6clang.c -o tests\features\67\v6clang_new01.asm
//
// BEFORE O85: i16 counter stays i16; zext of i keeps D (hi-byte) in loop body.
//             exit check uses two-byte compare.
// AFTER  O85: counter narrowed to i8; zext collapses to MVI H,0 (hoistable) + MOV L,E;
//             hi-byte exit check eliminated; 8+cc saved per iteration.

#include <stdint.h>

// -------------------------------------------------------------------------
// PRIMARY test: iter_xor_mix  (Case B — ExtraPNUses path)
// No array access, no GEP, so LPI does not fire and the exit icmp survives.
// Runtime input `seed` prevents constant-folding.
// Counter i is used directly in `acc ^= acc ^ i` (extra PN user).
// BEFORE: i16 counter in D:E pair; D stays 0 inside loop (wasted register).
// AFTER:  i8 counter in single register (e.g. E); MVI D,0 hoisted before loop;
//         exit uses CPI (single-byte compare).
// -------------------------------------------------------------------------
uint16_t iter_xor_mix(uint8_t seed) {
    uint16_t acc = seed;
    uint16_t i;
    for (i = 0; i < 64; i++) {
        acc += acc ^ i;  // recursive dep; i is extra PHI user; no GEP
    }
    return acc;
}

// -------------------------------------------------------------------------
// SECONDARY test: iter_xor_next  (Case B — ExtraAddUses path)
// Same structure but `i+1` (= AddOp) is the arithmetic operand.
// Tests the ExtraAddUses rewrite path.
// BEFORE: i.next stays i16; D kept in loop for hi-byte of i.next.
// AFTER:  zext of narrow i.next inserted; D cleared before loop and reused.
// -------------------------------------------------------------------------
uint16_t iter_xor_next(uint8_t seed) {
    uint16_t acc = seed;
    uint16_t i;
    for (i = 0; i < 64; i++) {
        acc += acc ^ (i + 1);  // i+1 == AddOp == extra AddOp user
    }
    return acc;
}

// -------------------------------------------------------------------------
// TERTIARY test: weighted_sum  (Case A — limitation, no improvement yet)
// LPI fires on arr[i] and replaces the exit icmp with a pointer comparison,
// so no constant bound icmp survives for the range check.
// O85 correctly bails out (Case A guard). Shown here to document the gap.
// -------------------------------------------------------------------------
uint16_t weighted_sum(uint8_t *arr) {
    uint16_t s = 0;
    uint16_t i;
    for (i = 0; i < 64; i++) {
        s += (uint16_t)arr[i] + i;
    }
    return s;
}

int main(void) {
    uint8_t arr[64];
    for (uint8_t k = 0; k < 64; k++) arr[k] = k;
    return (int)(iter_xor_mix(7) + iter_xor_next(7) + weighted_sum(arr)) & 0xFF;
}
