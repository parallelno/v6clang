// Test case for O61 Stage 2: cost-model chooser + DE/BC reload patching.
//
// Stage 2 extends the Stage 1 prototype (HL-only, first-reload patch) with:
//   * a per-reload cycle-saving Δ table (HL=+8, DE-dead=+12, DE-live=+16,
//     BC-dead=+24, BC-live=+52),
//   * a `BlockFrequency × Δ` chooser (still K ≤ 1 patched reload per slot),
//   * patch emission for `LXI DE, 0` and `LXI BC, 0` in addition to the
//     Stage 1 `LXI HL, 0` shape.
//
// Each test below produces a single-source HL spill that Stage 1 *rejects*
// because at least one reload of the slot targets DE (or a mix of HL+DE).
// Stage 2 picks the DE reload for patching (Δ = +12..+16 outranks the
// HL alternative's Δ = +8) and emits `LXI DE, 0` with a pre-instr label.
//
// Compile:
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\35\v6clang.c -o tests\features\35\v6clang_new01.asm \
//       -mllvm -mv6clang-spill-patched-reload \
//       -mllvm -v6clang-disable-shld-lhld-fold

__attribute__((leaf)) extern unsigned int op1(unsigned int x);
__attribute__((leaf)) extern unsigned int op2(unsigned int x);

// Single HL spill, single DE-target reload (HL holds the second call's
// result; the spilled value must be reloaded into DE for the i16 ADD16
// expansion that uses XCHG; DAD DE).
unsigned int de_one_reload(unsigned int x, unsigned int y) {
    unsigned int a = op1(x);
    unsigned int b = op2(y);   // clobbers HL → spill `a`, b stays in HL
    return a + b;              // RA reloads `a` into DE for DAD-based add
}

// Single HL spill, mixed reloads: one HL, one DE.
// Stage 1 would reject (mixed). Stage 2 must pick the DE reload as
// the patch winner (Δ = +12..+16 vs HL's Δ = +8).
unsigned int mixed_hl_de(unsigned int x, unsigned int y) {
    unsigned int a = op1(x);
    unsigned int t1 = op2(a);  // first reload of `a`: HL (passed as arg)
    unsigned int t2 = op2(y);  // clobbers HL → spill `a`
    return t1 + t2 + a;        // second reload of `a`: DE (ADD16)
}

unsigned int g1, g2;

int main(void) {
    g1 = de_one_reload(0x1234, 0x5678);
    g2 = mixed_hl_de(0xaaaa, 0xbbbb);
    return 0;
}
