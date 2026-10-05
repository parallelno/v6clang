/* O91: Elide V6CLANG_CMP8_ZERO after flag-setting ALU op (MOV R,A bridge)
 *
 * After O89 (dead hi-byte elision), the pattern:
 *
 *   MOV  A, E     ; A = lhs_lo
 *   XRA  L        ; A = lo result, Z = (result==0)  ← Z ALREADY VALID
 *   MOV  L, A     ; DstLo = result; FLAGS untouched
 *   XRA  A        ; ← CMP8_ZERO shape 2 start — REDUNDANT
 *   CMP  L        ; ← REDUNDANT
 *
 * O91 extends V6ClangRedundantFlagElim to recognize that XRA A + CMP R is
 * redundant when R holds A's value from the last flag-setting ALU op.
 * Result: the MOV L,A + XRA A + CMP L triple is eliminated (-16cc, -3B).
 *
 * Expected output after O91:
 *   MOV  A, E
 *   XRA  L        ; Z used directly
 *   JZ / JNZ ...
 */
typedef unsigned char  u8;
typedef unsigned short u16;

/* 1. XOR i16 -> compare lo-byte to zero
 * Before O91: MOV A,E; XRA L; MOV L,A; XRA A; CMP L; Jcc   (60cc 11B worst)
 * After  O91: MOV A,E; XRA L; Jcc                           (44cc  8B worst)
 */
__attribute__((noinline)) u8 xor16_cmp_zero(u16 a, u16 b) {
    return (u8)(a ^ b) == 0;
}

/* 2. AND i16 -> compare lo-byte to zero
 * Before O91: MOV A,L; ANA E; MOV L,A; XRA A; CMP L; Jcc   (60cc 11B worst)
 * After  O91: MOV A,L; ANA E; Jcc                           (44cc  8B worst)
 */
__attribute__((noinline)) u8 and16_cmp_zero(u16 a, u16 b) {
    return (u8)(a & b) == 0;
}

/* 3. OR i16 -> compare lo-byte to zero
 * Before O91: MOV A,E; ORA L; MOV L,A; XRA A; CMP L; Jcc   (60cc 11B worst)
 * After  O91: MOV A,E; ORA L; Jcc                           (44cc  8B worst)
 */
__attribute__((noinline)) u8 or16_cmp_zero(u16 a, u16 b) {
    return (u8)(a | b) == 0;
}

/* 4. Control: truncate only, no zero-test — must not regress (O89 result) */
__attribute__((noinline)) u8 xor16_to_i8(u16 a, u16 b) {
    return (u8)(a ^ b);
}

/* 5. Control: full 16-bit result — DstHi live, O91 must not fire */
__attribute__((noinline)) u16 xor16_full(u16 a, u16 b) {
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
