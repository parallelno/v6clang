/* O93: V6CLANG_AND16_IMM / V6CLANG_OR16_IMM / V6CLANG_XOR16_IMM — c8080 reference
 *
 * c8080 baseline for 16-bit bitwise ops against constants. Used to compare
 * against v6clang's improved output after O93.
 *
 * NOTE: c8080 uses 'unsigned int' for 16-bit and 'unsigned char' for 8-bit.
 */
typedef unsigned char u8;
typedef unsigned int  u16;

u16 xor16_const(u16 x) {
    return x ^ 0xB43C;
}

u16 xor16_hi_only(u16 x) {
    return x ^ 0xB400;
}

u16 or16_lo_only(u16 x) {
    return x | 0x0080;
}

u16 and16_clear_lo(u16 x) {
    return x & 0xFF00;
}

u16 and16_mask(u16 x) {
    return x & 0xF00F;
}

u16 or16_set_all(u16 x) {
    return x | 0xFFFF;
}

u16 lfsr_run(u16 seed, u8 steps) {
    u16 x = seed;
    u8 i;
    for (i = 0; i < steps; i++) {
        if (x & 1)
            x = (x >> 1) ^ 0xB400;
        else
            x = x >> 1;
    }
    return x;
}

int main(int argc, char **argv) {
    volatile u16 r1 = xor16_const(0x1234);
    volatile u16 r2 = xor16_hi_only(0x1234);
    volatile u16 r3 = or16_lo_only(0x1234);
    volatile u16 r4 = and16_clear_lo(0x1234);
    volatile u16 r5 = and16_mask(0x1234);
    volatile u16 r6 = or16_set_all(0x1234);
    volatile u16 r7 = lfsr_run(0xACE1, 16);
    return 0;
}
