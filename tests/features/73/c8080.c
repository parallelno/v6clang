/* O91: Elide V6CLANG_CMP8_ZERO after flag-setting ALU op — c8080 reference
 *
 * c8080 computes (u8)(a OP b)==0 directly as an 8-bit comparison using the
 * lo-byte register.  This is the expected c8080 baseline.
 *
 * NOTE: c8080 uses 'unsigned int' for 16-bit and 'unsigned char' for 8-bit.
 */
typedef unsigned char u8;
typedef unsigned int  u16;

/* (u8)(a ^ b) == 0 */
u8 xor16_cmp_zero(u16 a, u16 b) {
    return (u8)(a ^ b) == 0;
}

/* (u8)(a & b) == 0 */
u8 and16_cmp_zero(u16 a, u16 b) {
    return (u8)(a & b) == 0;
}

/* (u8)(a | b) == 0 */
u8 or16_cmp_zero(u16 a, u16 b) {
    return (u8)(a | b) == 0;
}

/* Control: truncate only, no zero-test (must not regress) */
u8 xor16_to_i8(u16 a, u16 b) {
    return (u8)(a ^ b);
}

/* Control: full 16-bit result used (must not regress) */
u16 xor16_full(u16 a, u16 b) {
    return a ^ b;
}

int main(int argc, char **argv) {
    volatile u8  r1 = xor16_cmp_zero(0x1234, 0x1234);
    volatile u8  r2 = and16_cmp_zero(0x00FF, 0xFF00);
    volatile u8  r3 = or16_cmp_zero(0x0001, 0x0000);
    volatile u8  r4 = xor16_to_i8(0x1234, 0x5678);
    volatile u16 r5 = xor16_full(0x1234, 0x5678);
    return 0;
}
