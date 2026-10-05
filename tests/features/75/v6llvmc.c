/* Feature 75 — O92 LXI-half-through-MOV collapse
 *
 * Goal: when a 16-bit constant is loaded with LXI RP, Imm16, and one byte
 * of that constant is later read into a register via MOV A, RP_HALF, the
 * peephole should rewrite that MOV to a direct MVI carrying the byte.
 *
 * Both compilers (c8080 and v6clang) build a single main() that calls
 * every test function so the produced assembly is directly comparable.
 */

typedef unsigned char  u8;
typedef unsigned short u16;

volatile u16 g_sink16;
volatile u8  g_sink8;

/* 1. lo byte extracted after the 16-bit XOR consumes the pair.
 *    The XOR forces LXI DE, 0xB4FF to survive ISel; the lo byte (0xFF)
 *    must be re-materialised because E is dirty after the XOR.
 *    Expected: MVI A, 0xFF replaces MOV A, E.
 */
u8 lxi_lo_used(u16 x) {
    const u16 mask = 0xB4FF;
    g_sink16 = x ^ mask;
    return (u8)(mask & 0xFF);
}

/* 2. hi byte extracted after the 16-bit XOR consumes the pair.
 *    Expected: MVI A, 0xB4 replaces MOV A, D.
 */
u8 lxi_hi_used(u16 x) {
    const u16 mask = 0xB4FF;
    g_sink16 = x ^ mask;
    return (u8)(mask >> 8);
}

/* 3. lo byte extracted; non-A destination.  Forces MOV to a register
 *    other than A, exercising the Z != A path of the peephole.
 */
u16 lxi_lo_to_b(u16 x) {
    const u16 mask = 0x9A37;
    g_sink16 = x ^ mask;
    return (u16)((u8)(mask & 0xFF));   /* lo = 0x37 */
}

/* 4. Negative case — constant 0xB400 has lo byte = 0.  Pre-existing
 *    foldMviZeroToXraA already handles this via XRA A; behaviour must
 *    remain unchanged (no regression).
 */
u8 lxi_lo_zero(u16 x) {
    const u16 mask = 0xB400;
    g_sink16 = x ^ mask;
    return (u8)(mask & 0xFF);          /* = 0 */
}

int main(void) {
    g_sink8 = lxi_lo_used(0x1234);
    g_sink8 = lxi_hi_used(0x5678);
    g_sink16 = lxi_lo_to_b(0x9abc);
    g_sink8 = lxi_lo_zero(0xdef0);
    return 0;
}
