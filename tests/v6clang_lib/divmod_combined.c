/* O70 Step 3.14 — divmod fusion runtime test.
 *
 * When source has both `q = a/b` and `r = a%b` of the same operands and the
 * mid-level optimizer keeps them as udiv+urem (rather than rewriting `r` as
 * `a - q*b`), ISel fuses to a single CALL __udivmodhi4. Verified at the
 * SDAG level by tests/lit/CodeGen/V6Clang/divmod-fusion.ll. This file is the
 * runtime correctness witness.
 *
 * Build / run:
 *   llvm-build\bin\clang.exe --target=i8080-unknown-v6clang -O2 \
 *       divmod_combined.c -o divmod_combined.rom
 *   v6emul.exe divmod_combined.rom
 * Expected output: 0x0F 0x05  (100/7=14, 100%7=2; signed -100/7=-14,
 *                              -100%7=-2; XOR'd as four bytes -> 0x0F05).
 */

typedef unsigned char  u8;
typedef unsigned short u16;
typedef signed   short i16;

static void out_port(u8 port, u8 v) { __builtin_v6clang_out(port, v); }

/* Volatile sinks prevent constant-folding through the function. */
volatile u16 g_uq, g_ur;
volatile i16 g_sq, g_sr;

static __attribute__((noinline))
void udivmod(u16 a, u16 b) {
    g_uq = a / b;
    g_ur = a % b;
}

static __attribute__((noinline))
void sdivmod(i16 a, i16 b) {
    g_sq = a / b;
    g_sr = a % b;
}

int main(void) {
    udivmod(100, 7);     /* uq=14, ur=2 */
    sdivmod(-100, 7);    /* sq=-14 (0xFFF2), sr=-2 (0xFFFE) */

    u16 chk = (u16)g_uq ^ (u16)g_ur ^ (u16)g_sq ^ (u16)g_sr;
    /* 14 ^ 2 ^ 0xFFF2 ^ 0xFFFE = 0x000C ^ 0x000C = 0 */
    out_port(0xED, (u8)(chk >> 8));
    out_port(0xED, (u8)chk);
    __builtin_v6clang_hlt();
    __builtin_unreachable();
    return 0;
}
