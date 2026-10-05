/* O54: Optimal stack adjustment via PUSH/POP for small frames.
 *
 * Goal: produce a function with a small (2- or 4-byte) hardware
 * stack frame so the prologue/epilogue's LXI+DAD+SPHL sequence is
 * exercised. Calling an opaque `extern` (without `nocallback`)
 * keeps `worker` ineligible for V6ClangAllocaPromote / V6ClangStaticStackAlloc
 * (O10), and holding multiple i8 values across the calls forces a
 * register spill.
 *
 * Compile (no extra flags needed under -O2):
 *   llvm-build\bin\clang.exe -target i8080-unknown-v6clang -O2 -S \
 *       tests\features\47\v6clang.c -o tests\features\47\v6clang_new01.asm
 */

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
