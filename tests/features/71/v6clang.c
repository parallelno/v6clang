/* O89: Dead high-byte elision in V6CLANG_AND16 / V6CLANG_OR16 / V6CLANG_XOR16
 *
 * Tests every pattern where a 16-bit bitwise op result is immediately
 * truncated to u8, so the high byte of the result is never used.
 *
 * The key improvement: when DstHi is dead, expandPostRAPseudo should skip
 * the hi-byte ALU+MOV block entirely, saving 20cc and 3B per occurrence.
 * AccumulatorPlanning then removes the MOV DstLo,A / MOV A,DstLo round-trip.
 */
typedef unsigned char  u8;
typedef unsigned short u16;

/* 1. XOR i16 → truncate to i8 (return)
 * Before: MOV A,E; XRA L; MOV L,A; MOV A,D; XRA H; MOV A,L; RET  (40cc 6B)
 * After:  MOV A,E; XRA L; RET                                       (12cc 2B)
 */
__attribute__((noinline)) u8 xor16_to_i8(u16 a, u16 b) {
    return (u8)(a ^ b);
}

/* 2. OR i16 → truncate to i8 (return)
 * Before: MOV A,E; ORA L; MOV L,A; MOV A,D; ORA H; MOV A,L; RET  (40cc 6B)
 * After:  MOV A,E; ORA L; RET                                       (12cc 2B)
 */
__attribute__((noinline)) u8 or16_to_i8(u16 a, u16 b) {
    return (u8)(a | b);
}

/* 3. AND i16 → truncate to i8 (return)
 * Before: MOV A,L; ANA E; MOV L,A; MOV A,H; ANA D; MOV A,L; RET  (40cc 6B)
 * After:  MOV A,L; ANA E; RET                                       (12cc 2B)
 */
__attribute__((noinline)) u8 and16_to_i8(u16 a, u16 b) {
    return (u8)(a & b);
}

/* 4. XOR lo and hi bytes (bench_finish checksum pattern)
 * a>>8 is SRL16_BYTE, then XOR16 result truncated to u8.
 * Before: MOV A,H; XRA L; MOV L,A; XRA A; XRA H; MOV A,L; RET  (36cc 6B)
 * After:  MOV A,H; XRA L; RET                                     (12cc 2B)
 */
__attribute__((noinline)) u8 xor_bytes(u16 a) {
    return (u8)((u8)a ^ (u8)(a >> 8));
}

/* 5. XOR i16 → compare to zero (branch pattern)
 * Before: full XOR16 + XRA A + CMP L  (hi-byte XOR wasted, CMP8_ZERO shape 2)
 * After:  lo-byte XRA + ORA A         (A = lo result → CMP8_ZERO shape 1)
 */
__attribute__((noinline)) u8 xor16_cmp_zero(u16 a, u16 b) {
    return (u8)(a ^ b) == 0;
}

/* 6. AND i16 → compare to zero (branch pattern)
 * Before: full AND16 + XRA A + CMP L
 * After:  lo-byte ANA + ORA A
 */
__attribute__((noinline)) u8 and16_cmp_zero(u16 a, u16 b) {
    return (u8)(a & b) == 0;
}

/* 7. OR i16 → compare to zero (branch pattern)
 * Before: full OR16 + XRA A + CMP L
 * After:  lo-byte ORA (Z already set by ORA itself!)
 */
__attribute__((noinline)) u8 or16_cmp_zero(u16 a, u16 b) {
    return (u8)(a | b) == 0;
}

/* 8. XOR i16 — full result used: high byte MUST be computed (control case)
 * This must NOT be affected by O89.
 */
__attribute__((noinline)) u16 xor16_full(u16 a, u16 b) {
    return a ^ b;
}

int main(void) {
    volatile u8  r1 = xor16_to_i8(0x1234, 0x5678);
    volatile u8  r2 = or16_to_i8(0xA5A5, 0x5A5A);
    volatile u8  r3 = and16_to_i8(0xF0F0, 0x0F0F);
    volatile u8  r4 = xor_bytes(0x1234);
    volatile u8  r5 = xor16_cmp_zero(0x1234, 0x1234);
    volatile u8  r6 = and16_cmp_zero(0x00FF, 0xFF00);
    volatile u8  r7 = or16_cmp_zero(0x0001, 0x0000);
    volatile u16 r8 = xor16_full(0x1234, 0x5678);
    (void)r1; (void)r2; (void)r3; (void)r4;
    (void)r5; (void)r6; (void)r7; (void)r8;
    return 0;
}
