/* fib_crc - first 24 i16 Fibonacci numbers, accumulate CRC-16 over the
 * little-endian byte stream, OUT the low byte of the CRC.
 * Stresses i16 add + bit shift + xor. */
#include "bench.h"

#define CRC_POLY 0xA001  /* CRC-16/IBM, reflected */

static u16 crc_byte(u16 crc, u8 b) {
    int k;
    crc ^= (u16)b;
    for (k = 0; k < 8; k++) {
        if (crc & 1) crc = (u16)((crc >> 1) ^ CRC_POLY);
        else         crc = (u16)(crc >> 1);
    }
    return crc;
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    /* Volatile seeds prevent the whole computation from collapsing to a
     * constant under aggressive optimization (otherwise v6clang -O2
     * folds the program to a single OUT). */
    volatile u8 seed_a = 0;
    volatile u8 seed_b = 1;
    u16 a = seed_a;
    u16 b = seed_b;
    u16 crc = 0xFFFF;
    int i;

    for (i = 0; i < 24; i++) {
        u16 c = (u16)(a + b);
        crc = crc_byte(crc, (u8)(c & 0xFF));
        crc = crc_byte(crc, (u8)((c >> 8) & 0xFF));
        a = b;
        b = c;
    }

    bench_finish((u8)(crc & 0xFF));
    return 0;
}
