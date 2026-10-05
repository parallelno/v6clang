/* O90: Pre-ISel i8 Narrowing — undo InstCombine widening
 *
 * InstCombine removes (u8) casts on bitwise ops with small constants:
 *   u8 lsb = (u8)(x & 1);  →  icmp i16 (and i16 x, 1), 0
 * This forces V6CLANG_AND16/OR16/XOR16 (6 insn each) instead of ANI/ORI/XRI (2B).
 *
 * V6ClangTypeNarrowing re-inserts the trunc before ISel, recovering ANI etc.
 * O90 fixes two gaps:
 *   1. PHI sibling guard was too conservative for pure zero-test uses.
 *   2. or/xor with small constants were not handled (only and was).
 */
typedef unsigned char  u8;
typedef unsigned short u16;

/* 1. AND with small constant — pure zero-test (the lfsr16 pattern)
 * The result is only used for a branch; no need to persist in a register.
 * Before: LXI rp,1; V6CLANG_AND16 (6 insn); SPILL; CMP16_ZERO  (~76cc)
 * After:  MOV A,L; ANI 1                                     (16cc)
 */
__attribute__((noinline)) u8 and_lsb_branch(u16 x) {
    return (u8)(x & 1) != 0;
}

/* 2. AND with small constant — result returned as u8
 * Before: V6CLANG_AND16 6 insn (36cc, 6B) + AccPlan reload
 * After:  MOV A,L; ANI 0x0F  (16cc, 3B)
 */
__attribute__((noinline)) u8 and_nibble(u16 x) {
    return (u8)(x & 0x0F);
}

/* 3. OR with small constant — result returned as u8
 * Before: V6CLANG_OR16 6 insn
 * After:  MOV A,L; ORI 0x80
 */
__attribute__((noinline)) u8 or_hi_bit(u16 x) {
    return (u8)(x | 0x80);
}

/* 4. XOR with small constant — result returned as u8
 * Before: V6CLANG_XOR16 6 insn
 * After:  MOV A,L; XRI 0x55
 */
__attribute__((noinline)) u8 xor_pattern(u16 x) {
    return (u8)(x ^ 0x55);
}

/* 5. AND with LARGE constant — must NOT narrow (C > 0xFF)
 * Control case: and i16 x, 0x0F0F is NOT a small constant.
 * Must still emit V6CLANG_AND16.
 */
__attribute__((noinline)) u16 and_wide(u16 x) {
    return x & 0x0F0F;
}

/* 6. AND in a loop with i16 PHI siblings (lfsr16 pattern)
 * Before O90: PHI sibling guard blocked the narrowing.
 * After  O90: pure zero-test → guard relaxed → ANI emitted.
 */
__attribute__((noinline)) u16 lfsr_step(u16 lfsr) {
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

int main(void) {
    volatile u8  r1 = and_lsb_branch(0x1235);
    volatile u8  r2 = and_nibble(0xABCD);
    volatile u8  r3 = or_hi_bit(0x0042);
    volatile u8  r4 = xor_pattern(0x00AA);
    volatile u16 r5 = and_wide(0xFFFF);
    volatile u16 r6 = lfsr_step(0xACE1);
    (void)r1; (void)r2; (void)r3; (void)r4; (void)r5; (void)r6;
    return 0;
}
