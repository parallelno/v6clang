// Test case for O61 Stage 1 — c8080 reference version.
//
// c8080 does not implement the static stack alloc optimization the
// way v6clang does, so the spill/reload baseline shape will differ.
// This file exists for the standard tests/features comparison.

unsigned int op_acc;

unsigned int op1(unsigned int x) { op_acc ^= x; return x + 1; }
unsigned int op2(unsigned int x) { op_acc ^= x; return x + 2; }

unsigned int hl_one_spill(unsigned int x, unsigned int y) {
    unsigned int a = op1(x);
    unsigned int b = op2(y);
    return a + b;
}

unsigned int hl_two_reloads(unsigned int x) {
    unsigned int a = op1(x);
    unsigned int b1 = op2(a);
    unsigned int b2 = op2(a);
    return b1 + b2;
}

unsigned int g1, g2;

int main(int argc, char **argv) {
    g1 = hl_one_spill(0x1234, 0x5678);
    g2 = hl_two_reloads(0xabcd);
    return 0;
}
