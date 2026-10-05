/* O89: Dead high-byte elision — c8080 reference
 * c8080 works natively with 8-bit values and its arithmetic never generates
 * a 16-bit pseudo for a truncated-to-u8 result. This is the expected baseline
 * for comparison with v6clang's improved output after O89.
 *
 * NOTE: c8080 uses 'unsigned int' for 16-bit and 'unsigned char' for 8-bit.
 *       Explicit casts to unsigned char select 8-bit operations directly.
 */
typedef unsigned char u8;
typedef unsigned int  u16;

u8 xor16_to_i8(u16 a, u16 b) {
    return (u8)(a ^ b);
}

u8 or16_to_i8(u16 a, u16 b) {
    return (u8)(a | b);
}

u8 and16_to_i8(u16 a, u16 b) {
    return (u8)(a & b);
}

u8 xor_bytes(u16 a) {
    return (u8)((u8)a ^ (u8)(a >> 8));
}

u8 xor16_cmp_zero(u16 a, u16 b) {
    return (u8)(a ^ b) == 0;
}

u8 and16_cmp_zero(u16 a, u16 b) {
    return (u8)(a & b) == 0;
}

u8 or16_cmp_zero(u16 a, u16 b) {
    return (u8)(a | b) == 0;
}

u16 xor16_full(u16 a, u16 b) {
    return a ^ b;
}

int main(int argc, char **argv) {
    volatile u8  r1 = xor16_to_i8(0x1234, 0x5678);
    volatile u8  r2 = or16_to_i8(0xA5A5, 0x5A5A);
    volatile u8  r3 = and16_to_i8(0xF0F0, 0x0F0F);
    volatile u8  r4 = xor_bytes(0x1234);
    volatile u8  r5 = xor16_cmp_zero(0x1234, 0x1234);
    volatile u8  r6 = and16_cmp_zero(0x00FF, 0xFF00);
    volatile u8  r7 = or16_cmp_zero(0x0001, 0x0000);
    volatile u16 r8 = xor16_full(0x1234, 0x5678);
    return 0;
}
