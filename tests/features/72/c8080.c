/* O90: Pre-ISel i8 Narrowing — c8080 reference
 * c8080 compiler works natively with 8-bit values and applies bitwise
 * operations at the u8 level directly. This is the baseline for comparing
 * code quality of v6clang's improved output after O90.
 *
 * NOTE: c8080 uses 'unsigned int' for 16-bit, 'unsigned char' for 8-bit.
 */
typedef unsigned char u8;
typedef unsigned int  u16;

u8 and_lsb_branch(u16 x) {
    return (u8)(x & 1) != 0;
}

u8 and_nibble(u16 x) {
    return (u8)(x & 0x0F);
}

u8 or_hi_bit(u16 x) {
    return (u8)(x | 0x80);
}

u8 xor_pattern(u16 x) {
    return (u8)(x ^ 0x55);
}

u16 and_wide(u16 x) {
    return x & 0x0F0F;
}

u16 lfsr_step(u16 lfsr) {
    u16 acc = 0;
    u16 i;
    for (i = 0; i < 16; i++) {
        u8 lsb = (u8)(lfsr & 1);
        lfsr = (u16)(lfsr >> 1);
        if (lsb) lfsr = (u16)(lfsr ^ 0xB4);
        acc = (u16)(acc ^ lfsr);
    }
    return acc;
}

int main(int argc, char **argv) {
    volatile u8  r1 = and_lsb_branch(0x1235);
    volatile u8  r2 = and_nibble(0xABCD);
    volatile u8  r3 = or_hi_bit(0x0042);
    volatile u8  r4 = xor_pattern(0x00AA);
    volatile u16 r5 = and_wide(0xFFFF);
    volatile u16 r6 = lfsr_step(0xACE1);
    (void)r1; (void)r2; (void)r3; (void)r4; (void)r5; (void)r6;
    return 0;
}
