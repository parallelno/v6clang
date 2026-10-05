/* O02: Sequential LXI -> INX folding (extended).
 *
 * Tests three pattern shapes that the current V6ClangLoadStoreOpt
 * fails to fold:
 *   1) Chains of length > 2 (third LXI not folded).
 *   2) GlobalAddress operands (LXI H, g+1 etc.).
 *   3) HL-preserving instructions interleaved between LXI and
 *      MOV M / arith M (e.g. LDA, STA).
 *
 * Compile:
 *   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
 *       tests\features\50\v6clang.c -o tests\features\50\v6clang_new01.asm
 */

extern unsigned char ext_sink(unsigned char v);

struct S { unsigned char x, y, z, w; };
struct S g_s;

/* Pattern (1): chain of length 4 — three foldable LXIs. */
unsigned char sum4_global(void) {
    return g_s.x + g_s.y + g_s.z + g_s.w;
}

/* Pattern (2): write 4 consecutive globals after an HL-preserving
 * STA / LDA gap. */
volatile unsigned char g_a, g_b, g_c, g_d;
void write4_globals(unsigned char v) {
    g_a = v;
    g_b = v + 1;
    g_c = v + 2;
    g_d = v + 3;
}

/* Pattern (3): port-mapped sequential reads with HL-preserving
 * accumulator arithmetic between accesses. */
unsigned char sum4_array(const unsigned char *p) {
    unsigned char s = p[0];
    s += p[3];
    s += p[2];
    s += p[1];
    return s;
}

unsigned char g_arr[4];

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    g_arr[0] = 1; g_arr[1] = 2; g_arr[2] = 3; g_arr[3] = 4;
    unsigned char r1 = sum4_global();
    unsigned char r2 = sum4_array(g_arr);
    write4_globals(r1 + r2);
    return ext_sink(g_a + g_b + g_c + g_d);
}
