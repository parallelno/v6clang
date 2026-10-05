// Test case for O61 Stage 2 — c8080 reference version.
//
// c8080 does not implement the static stack allocation / patched-reload
// optimizations that v6clang does. This file exists for the standard
// tests/features comparison.

unsigned int op_acc;

unsigned int op1(unsigned int x) { op_acc ^= x; return x + 1; }
unsigned int op2(unsigned int x) { op_acc ^= x; return x + 2; }

unsigned int de_one_reload(unsigned int x, unsigned int y) {
    unsigned int a = op1(x);
    unsigned int b = op2(y);
    return a + b;
}

unsigned int mixed_hl_de(unsigned int x, unsigned int y) {
    unsigned int a = op1(x);
    unsigned int t1 = op2(a);
    unsigned int t2 = op2(y);
    return t1 + t2 + a;
}

unsigned int g1, g2;

int main(int argc, char **argv) {
    g1 = de_one_reload(0x1234, 0x5678);
    g2 = mixed_hl_de(0xaaaa, 0xbbbb);
    return 0;
}
