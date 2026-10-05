/* O54: Optimal stack adjustment via PUSH/POP for small frames.
 * c8080 reference compile target. c8080 does not support recursion;
 * the v6clang test relies on an opaque extern call to force a
 * hardware stack frame, the same pattern is used here. */

extern unsigned char ext_fn(unsigned char x, unsigned char y);

volatile unsigned int g_sink;

unsigned int worker(unsigned char a, unsigned char b, unsigned char c) {
    unsigned char r1 = ext_fn(a, b);
    unsigned char r2 = ext_fn(b, c);
    unsigned char r3 = ext_fn(a, c);
    return (unsigned int)r1 + r2 + r3;
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    g_sink = worker(1, 2, 3);
    return 0;
}
