// Test case for O61 Stage 3: K=2 patched reloads + multi-source HL spill.
//
// Stage 3 extends Stage 2 with:
//   * single-source spills: K <= 2 patched reloads (was K <= 1);
//   * multi-source spills: K <= 1 (was rejected outright);
//   * the 2nd-patch chooser must skip HL-target candidates
//     (2nd-patch Δ = −12 cc — net loss per the design doc).
//
// Compile:
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\36\v6clang.c -o tests\features\36\v6clang_new01.asm \
//       -mllvm -mv6clang-spill-patched-reload \
//       -mllvm -v6clang-disable-shld-lhld-fold

__attribute__((leaf)) extern unsigned int op1(unsigned int x);
__attribute__((leaf)) extern unsigned int op2(unsigned int x);

// Multi-source HL spill: two SHLDs of `a` on diverging paths, one
// DE-target reload. Stage 2 rejected (size() != 1). Stage 3 must
// accept as K=1 multi-source: two `SHLD .Lo61_0+1` at the source
// points, one `LXI DE, 0` at the patched site.
unsigned int multi_src_de(unsigned int x, unsigned int y, unsigned int c) {
    unsigned int a;
    if (c)
        a = op1(x);
    else
        a = op2(x);
    unsigned int b = op2(y);   // clobbers HL → reload `a` into DE
    return a + b;
}

// Candidate for single-source K=2: one HL spill, two uses of `a`
// after an HL-clobbering call. The adds route through DE/BC giving
// the chooser two non-HL reload candidates of the same slot.
unsigned int k2_two_reloads(unsigned int x, unsigned int y, unsigned int z) {
    unsigned int a = op1(x);
    unsigned int b = op2(y);   // clobbers HL; reload `a` for add into b
    unsigned int s1 = a + b;
    unsigned int c = op2(z);   // clobbers HL; reload `a` again
    return s1 + a + c;
}

unsigned int g1, g2;

int main(void) {
    g1 = multi_src_de(0x1234, 0x5678, 1);
    g2 = k2_two_reloads(0xaaaa, 0xbbbb, 0xcccc);
    return 0;
}
