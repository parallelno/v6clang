// Test case for O64 — liveness-aware i8 spill/reload lowering on
// static-stack functions.
//
// Exercises Shape B (src/dst in {B,C,D,E}) and Shape C (src/dst in
// {H,L}) spill/reload sites where HL (or the other half of HL) is
// live while A is dead — O64's main win.
//
// Compile:
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\38\v6clang.c -o tests\features\38\v6clang_new01.asm \
//       -mllvm -mv6clang-annotate-pseudos

__attribute__((leaf)) extern unsigned char op(unsigned char x);
__attribute__((leaf)) extern void use5(unsigned char, unsigned char,
                                       unsigned char, unsigned char,
                                       unsigned char);

// Five live i8 values across five A-clobbering calls.
// Drives the RA to spill several i8 values to i8 stack slots; every
// reload site after an `op` call has HL live (call-clobbered and reloaded
// for return address / next-call setup) and A dead immediately after the
// return value is consumed.
unsigned char many_i8(unsigned char a, unsigned char b, unsigned char c,
                      unsigned char d, unsigned char e) {
    unsigned char x1 = op(a);
    unsigned char x2 = op(b);
    unsigned char x3 = op(c);
    unsigned char x4 = op(d);
    unsigned char x5 = op(e);
    use5(x1, x2, x3, x4, x5);
    return (unsigned char)(x1 ^ x2 ^ x3 ^ x4 ^ x5);
}

int main(int argc, char **argv) {
    many_i8(0x11, 0x22, 0x33, 0x44, 0x55);
    return 0;
}
