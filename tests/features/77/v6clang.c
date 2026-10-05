/* O93: V6CLANG_AND16_IMM / V6CLANG_OR16_IMM / V6CLANG_XOR16_IMM
 *
 * 16-bit bitwise ops against a compile-time constant. Currently each emits
 * an LXI to materialise the constant into a scratch register pair, then a
 * 6-instruction pair-wise V6CLANG_*16. With O93 the constant goes into A per byte
 * (commutativity: A^r == r^A), so no scratch pair is needed and trivial bytes
 * (0x00 / 0xFF identities) fold away.
 *
 * Each result is returned as u16 (register-persistent) so O90's zero-test
 * i8-narrowing does NOT fire — these are exactly the cases O93 owns.
 */
typedef unsigned char  u8;
typedef unsigned short u16;

/* 1. XOR with full-width constant — both bytes non-trivial.
 * Before: LXI B,0xB43C; 6-insn XOR16   (52cc / 9B)
 * After : MVI A,0x3C; XRA L; MOV L,A; MVI A,0xB4; XRA H; MOV H,A  (40cc / 8B)
 */
__attribute__((noinline)) u16 xor16_const(u16 x) {
    return x ^ 0xB43C;
}

/* 2. XOR with hi-only constant (lo byte 0x00 → XOR identity, folded).
 * Before: LXI + XOR16   (52cc)
 * After : MVI A,0xB4; XRA H; MOV H,A   (20cc / 4B)
 */
__attribute__((noinline)) u16 xor16_hi_only(u16 x) {
    return x ^ 0xB400;
}

/* 3. OR with lo-only constant (hi byte 0x00 → OR identity, folded).
 * After : MVI A,0x80; ORA L; MOV L,A   (20cc / 4B)
 */
__attribute__((noinline)) u16 or16_lo_only(u16 x) {
    return x | 0x0080;
}

/* 4. AND clearing the low byte (lo 0x00 → MVI L,0; hi 0xFF → AND identity).
 * After : MVI L, 0   (8cc / 2B)
 */
__attribute__((noinline)) u16 and16_clear_lo(u16 x) {
    return x & 0xFF00;
}

/* 5. AND with full mask — both bytes non-trivial.
 * After : MVI A,0x0F; ANA L; MOV L,A; MVI A,0xF0; ANA H; MOV H,A
 */
__attribute__((noinline)) u16 and16_mask(u16 x) {
    return x & 0xF00F;
}

/* 6. OR setting both bytes high (0xFFFF) — lo 0xFF → MVI L,0xFF; hi 0xFF → MVI H,0xFF. */
__attribute__((noinline)) u16 or16_set_all(u16 x) {
    return x | 0xFFFF;
}

/* 7. LFSR-style hot loop: x ^= 0xB400 per step. This is the motivating case
 * where the constant-pair LXI forces a spill/reload around the loop body.
 */
__attribute__((noinline)) u16 lfsr_run(u16 seed, u8 steps) {
    u16 x = seed;
    for (u8 i = 0; i < steps; i++) {
        if (x & 1)
            x = (x >> 1) ^ 0xB400;
        else
            x = x >> 1;
    }
    return x;
}

int main(void) {
    volatile u16 r1 = xor16_const(0x1234);
    volatile u16 r2 = xor16_hi_only(0x1234);
    volatile u16 r3 = or16_lo_only(0x1234);
    volatile u16 r4 = and16_clear_lo(0x1234);
    volatile u16 r5 = and16_mask(0x1234);
    volatile u16 r6 = or16_set_all(0x1234);
    volatile u16 r7 = lfsr_run(0xACE1, 16);
    (void)r1; (void)r2; (void)r3; (void)r4;
    (void)r5; (void)r6; (void)r7;
    return 0;
}
