/* tests/features/55/v6clang.c
 *
 * O73 — V6CLANG_LOAD16_G redesign integration test.
 *
 * Granular per-shape CHECK coverage lives in
 *   llvm-project/llvm/test/CodeGen/V6Clang/load16g_shapes.ll
 * (constructed directly in LLVM IR so we can pin the dst register).
 *
 * This file is the runtime cross-check: it verifies that V6CLANG_LOAD16_G
 * still produces the correct loaded value across the natural shapes
 * RA picks for plain C source, before and after the redesign.
 *
 * The V6CLANG calling convention places i16 args in HL, DE, BC, so a
 * 3-i16-arg call site forces the third arg to be loaded into BC.
 * We use that to bring the dst=BC shape into reach without resorting
 * to inline asm.
 */

#include <stdint.h>

volatile uint16_t g_a;
volatile uint16_t g_b;
volatile uint16_t g_c;
volatile uint16_t g_r;
volatile uint8_t  g_byte;

/* dst=HL (case 1): the natural LHLD shape — single LHLD. */
uint16_t case1_dst_hl(void) {
    return g_a;
}

/* dst=DE (case 2): RA picks DE because HL holds the result of an
 * earlier op, so the new load goes elsewhere. Should remain
 * XCHG;LHLD;XCHG. */
uint16_t case2_dst_de(uint16_t hl_keep) {
    /* hl_keep is in HL on entry. The global load needs to go to a
     * non-HL register so that the final DAD can fuse. */
    return hl_keep + g_a;
}

/* dst=BC (case 3): three i16 globals into a 3-arg call.
 * The third argument forces a global load into BC. After the call
 * returns, the result flows through HL. */
__attribute__((noinline))
uint16_t add3(uint16_t a, uint16_t b, uint16_t c) {
    /* noinline so the call site is forced to materialise three real
     * i16 args (HL, DE, BC) — this brings the dst=BC shape of
     * V6CLANG_LOAD16_G into reach. */
    return a + b + c;
}

uint16_t case3_dst_bc(void) {
    return add3(g_a, g_b, g_c);
}

int main(void) {
    g_a = 0x1234;
    g_b = 0x5678;
    g_c = 0x0001;

    g_r = case1_dst_hl();              /* 0x1234 */
    __builtin_v6clang_out(0xDE, (uint8_t)g_r);

    g_r = case2_dst_de(0x0100);        /* 0x1334 */
    __builtin_v6clang_out(0xDE, (uint8_t)g_r);

    g_r = case3_dst_bc();              /* 0x68AD */
    __builtin_v6clang_out(0xDE, (uint8_t)g_r);

    return 0;
}
