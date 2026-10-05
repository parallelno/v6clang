/* tests/features/53/v6clang.c
 *
 * O71 — V6CLANG_LOAD16_P redesign. The old expander has five
 * correctness bugs (see design/future_plans/O71_V6CLANG_LOAD16_P_redesign.md).
 * This test focuses on:
 *
 *   1. The bug-3 reproducer: addr=DE, dst=DE producing wrong values.
 *      Mirrors the shape from temp/asm_inline/custom_cc.c that
 *      first surfaced the bug.
 *   2. Shape coverage: load through three different pointer pairs,
 *      and a few "pointer reused after the load" patterns to force
 *      DCX rp recovery (case 2 / case 3).
 *   3. Runtime guard: main() prints a checksum via __builtin_v6clang_out
 *      so the v6emul --halt-exit run has a single-byte witness for
 *      bug 3.
 *
 * Per-shape granular CHECK coverage is in the lit tests
 * (llvm-project/llvm/test/CodeGen/V6Clang/load16p_*.ll); this file is
 * the integration-level cross-check.
 */

#include <stdint.h>

volatile uint16_t g_a;
volatile uint16_t g_b;
volatile uint16_t g_r;
volatile uint8_t  g_byte;

/* Case 4 reproducer (bug 3): addr=DE, dst=DE.
 * Force DE to hold a pointer that we then dereference into a value
 * we add to an HL-resident sum.  Returns sum + *p.
 *
 * The body is identical to the failing pattern in custom_cc.s. */
uint16_t bug3_de_de(uint16_t sum_in_hl, uint16_t *p_in_de) {
    /* DAD B is irrelevant here; what matters is the load-via-DE
     * happening between two uses of HL where HL must be preserved. */
    uint16_t v = *p_in_de;
    return sum_in_hl + v;
}

/* Case 2: addr=HL, dst=BC/DE, then HL pointer reused after the load
 * (forces DCX H recovery). */
uint16_t case2_hl_reused(uint16_t *p) {
    uint16_t lo = p[0];
    uint16_t hi = p[0];   /* same load — depends on p still pointing at p[0] */
    return lo + hi;
}

/* Case 5: addr=BC, dst=BC/DE, with HL live across the load. */
uint16_t case5_bc_with_hl_live(uint16_t *p, uint16_t hl_keep) {
    uint16_t v = *p;
    return v + hl_keep;
}

/* Case 1/6: addr=*, dst=HL, with A live across the load. */
uint8_t case16_a_live(uint16_t *p, uint8_t a_keep) {
    uint16_t v = *p;
    return (uint8_t)(v >> 8) ^ a_keep;
}

int main(void) {
    /* Fixed addresses; the volatile writes seed the load targets. */
    static uint16_t buf[2];
    buf[0] = 0x1234;
    buf[1] = 0x5678;

    g_r = bug3_de_de(0x1000, &buf[0]);          /* expect 0x2234 */
    g_byte = (uint8_t)g_r;                       /* witness lo byte */
    __builtin_v6clang_out(0xDE, g_byte);

    g_r = case2_hl_reused(&buf[1]);              /* expect 0xACF0 */
    __builtin_v6clang_out(0xDE, (uint8_t)g_r);

    g_r = case5_bc_with_hl_live(&buf[0], 0x0001); /* expect 0x1235 */
    __builtin_v6clang_out(0xDE, (uint8_t)g_r);

    g_byte = case16_a_live(&buf[1], 0x42);       /* expect 0x56^0x42 = 0x14 */
    __builtin_v6clang_out(0xDE, g_byte);

    return 0;
}
