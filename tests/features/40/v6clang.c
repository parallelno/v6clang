// Test case for O61 Stage 6: non-A i8 spill sources.
//
// Stage 6 extends O61 from Stage 4's A-only i8 spill source filter
// to any GR8 spill source (B, C, D, E, H, L also admitted). The
// reload-side machinery (MVI r, 0 for any GR8 target) is unchanged
// from Stage 4; Stage 6 reuses O64's shared expandSpill8Static
// helper to emit the spill ladder against a Sym+1 code-address
// target.
//
// Compile:
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\40\v6clang.c -o tests\features\40\v6clang_new01.asm \
//       -mllvm -mv6clang-spill-patched-reload \
//       -mllvm -v6clang-disable-shld-lhld-fold

__attribute__((leaf)) extern unsigned char op1(unsigned char x);
__attribute__((leaf)) extern unsigned char op2(unsigned char x);
__attribute__((leaf)) extern void use2(unsigned char a, unsigned char b);
__attribute__((leaf)) extern void use3(unsigned char a, unsigned char b,
                                       unsigned char c);
__attribute__((leaf)) extern void use4(unsigned char a, unsigned char b,
                                       unsigned char c, unsigned char d);

// Three i8 values held across two A-clobbering calls. RA distributes
// the live i8 values across A and non-A regs; at least one ends up
// held in B/C/D/E and must be spilled across a subsequent call.
// Stage 4 rejects non-A spills (fall-through to classical O64);
// Stage 6 patches the reload with MVI r, 0.
unsigned char three_i8(unsigned char x, unsigned char y, unsigned char z) {
    unsigned char a = op1(x);
    unsigned char b = op2(y);
    unsigned char c = op1(z);
    use3(a, b, c);
    return (unsigned char)(a + b + c);
}

// Four i8 values held across three A-clobbering calls — stronger
// pressure, higher chance of non-A sourced spill(s).
unsigned char four_i8(unsigned char x, unsigned char y,
                      unsigned char z, unsigned char w) {
    unsigned char a = op1(x);
    unsigned char b = op2(y);
    unsigned char c = op1(z);
    unsigned char d = op2(w);
    use4(a, b, c, d);
    return (unsigned char)(a + b + c + d);
}

int main(void) {
    use2(three_i8(0x11, 0x22, 0x33),
         four_i8(0x44, 0x55, 0x66, 0x77));
    return 0;
}
