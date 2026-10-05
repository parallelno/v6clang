// Test case for O61 Stage 4: i8 patched reload (A spill, r8 reload).
//
// Stage 4 extends O61 from 16-bit slots (i16 / HL source, DE/BC/HL
// reloads) to 8-bit slots:
//   * Spill source must be A (Stage 4 scope);
//   * Reload destinations can be any r8 (A, B, C, D, E, H, L);
//   * K <= 2 single-source / K <= 1 multi-source (same as Stage 3);
//   * 2nd-patch chooser skips A and H/L targets.
//
// Compile:
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\37\v6clang.c -o tests\features\37\v6clang_new01.asm \
//       -mllvm -mv6clang-spill-patched-reload \
//       -mllvm -v6clang-disable-shld-lhld-fold

__attribute__((leaf)) extern unsigned char op1(unsigned char x);
__attribute__((leaf)) extern unsigned char op2(unsigned char x);
__attribute__((leaf)) extern void use2(unsigned char a, unsigned char b);

// Single A spill, single non-A reload. Stage 3 keeps classical i8
// path; Stage 4 must patch with `MVI r, 0` at the reload site.
unsigned char a_spill_r8_reload(unsigned char x, unsigned char y) {
    unsigned char a = op1(x);   // a held across op2 → spill A
    unsigned char b = op2(y);   // clobbers A
    return a + b;               // reload a into some r8, add
}

// Two uses of `a` across two A-clobbering calls → single-source K=2.
unsigned char k2_i8(unsigned char x, unsigned char y, unsigned char z) {
    unsigned char a = op1(x);
    unsigned char b = op2(y);   // reload #1 of a
    unsigned char s1 = (unsigned char)(a + b);
    unsigned char c = op2(z);   // reload #2 of a
    return (unsigned char)(s1 + a + c);
}

// Multi-source A spill: `a` defined on diverging paths, one reload.
// Stage 3 rejected (multi-source for i8 not handled). Stage 4 admits
// as multi-source K=1.
unsigned char multi_src_i8(unsigned char x, unsigned char y, unsigned char c) {
    unsigned char a;
    if (c)
        a = op1(x);
    else
        a = op2(x);
    unsigned char b = op2(y);   // A-clobbering call
    return a + b;
}

// Mixed i8 + i16 slots in one function — Stage 4 must patch both
// without interference.
unsigned int g_u16;
unsigned char g_u8;

void mixed_widths(unsigned int x16, unsigned char x8) {
    unsigned int a16 = (unsigned int)op1((unsigned char)x16) + x16;
    unsigned char a8  = op2(x8);
    unsigned int b16 = (unsigned int)op2((unsigned char)x16);
    unsigned char b8  = op1(x8);
    g_u16 = a16 + b16;
    g_u8  = (unsigned char)(a8 + b8);
}

int main(void) {
    use2(a_spill_r8_reload(0x11, 0x22), k2_i8(0x33, 0x44, 0x55));
    use2(multi_src_i8(0x66, 0x77, 1), 0);
    mixed_widths(0xabcd, 0xef);
    return 0;
}
