/* O22: TTI Cost Hooks Expansion — V6CLANG test.
 *
 * The new TTI cost hooks (getArithmeticInstrCost / getMemoryOpCost /
 * getCmpSelInstrCost / getScalingFactorCost) are intended to keep IR-
 * level passes (loop unroller, inliner, SLP) from over-aggressive
 * transforms on i16 work, where the i8080 has no cheap encoding.
 *
 * The two functions below are loop bodies the unroller might
 * duplicate. Without proper costs the unroller sees i16 ops as cheap
 * as i8 ops; with the new hooks it should leave the loop alone.
 *
 * Compile:
 *   llvm-build\bin\clang -target i8080-unknown-v6clang -O3 -S \
 *       tests\features\51\v6clang.c -o tests\features\51\v6clang_new01.asm
 */

extern unsigned short ext_sink16(unsigned short v);

/* i16 accumulate with multiply: stresses the unroller on i16 work. */
unsigned short sum_array(const unsigned short *a, unsigned char n) {
    unsigned short s = 0;
    unsigned char i;
    for (i = 0; i < n; i++) {
        s += a[i] * 3 + 7;
    }
    return s;
}

/* Larger loop body — would cause heavy spilling if unrolled. */
unsigned short poly(const unsigned short *a, unsigned char n) {
    unsigned short s = 0;
    unsigned char i;
    for (i = 0; i < n; i++) {
        unsigned short x = a[i];
        s += x * 5 + (x >> 1) + 3;
    }
    return s;
}

unsigned short g_arr[8];

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    g_arr[0] = 1; g_arr[1] = 2; g_arr[2] = 3; g_arr[3] = 4;
    g_arr[4] = 5; g_arr[5] = 6; g_arr[6] = 7; g_arr[7] = 8;
    unsigned short r1 = sum_array(g_arr, 8);
    unsigned short r2 = poly(g_arr, 8);
    return ext_sink16(r1 + r2);
}
