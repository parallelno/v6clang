/* tests/features/54/v6clang.c
 *
 * O72 — V6CLANG_STORE16_P redesign. Companion to O71 (LOAD16_P). The
 * old expander declares a blanket `Defs = [HL, A]` that
 * over-clobbers `A` on 6 of 9 shapes and forces RA to spill `A`
 * across every 16-bit pointer store. The redesigned expander
 * drops the blanket and emits per-shape preservation
 * (dead-GR8 spare, DCX rp recovery, XCHG for addr=DE, PUSH H
 * only as last resort on row 6).
 *
 * Test focuses:
 *
 *   1. addr=DE, val=HL  (row 3a) — XCHG path replaces STAX D /
 *      PUSH D / POP D.
 *   2. addr=HL, val∈{BC,DE} with HL reused (row 2) — DCX H
 *      recovery.
 *   3. addr=BC, val=HL (row 5) with A live across — SpareR-A
 *      preservation instead of unconditional A clobber.
 *   4. addr=BC, val=BC (row 6) — three-tier dispatch (HL dead
 *      common path).
 *   5. addr=DE, val=DE (row 4) — XCHG-wrapped per-byte spare.
 */

#include <stdint.h>

volatile uint16_t g_a;
volatile uint16_t g_r;

/* Row 3a: addr=DE, val=HL.
 * CC: arg1=HL=v, arg2=DE=p. */
void row3_de_hl(uint16_t v, uint16_t *p) {
    *p = v;
}

/* Row 2: addr=HL, val=DE, then HL pointer reused.
 * CC: arg1=HL=p, arg2=DE=v. Stores then reads back through p. */
uint16_t row2_hl_reused(uint16_t *p, uint16_t v) {
    p[0] = v;
    return p[0];   /* same address — needs HL preserved/restored */
}

/* Row 5: addr=BC, val=HL, with A live across the store.
 * CC: arg1=HL=v, arg2=DE=a_keep, arg3=BC=p. */
uint8_t row5_bc_hl_a_live(uint16_t v, uint8_t a_keep, uint16_t *p) {
    *p = v;
    return a_keep ^ 0x42;   /* forces a_keep to live through the store */
}

/* Row 6: addr=BC, val=BC.
 * CC: arg3=BC=p. Store the BC pointer at itself.
 * No HL/DE live across — exercises the row-6a (HL dead) path. */
void row6_bc_bc(uint16_t a, uint16_t b, uint16_t *p) {
    (void)a; (void)b;
    *p = (uint16_t)(uintptr_t)p;
}

/* Row 4: addr=DE, val=DE — pointer self-store via DE.
 * CC: arg1=HL=hl_keep, arg2=DE=p. */
uint16_t row4_de_de(uint16_t hl_keep, uint16_t *p) {
    *p = (uint16_t)(uintptr_t)p;
    return hl_keep;   /* HL must be preserved across the store */
}

int main(void) {
    static uint16_t buf[3];
    buf[0] = 0;
    buf[1] = 0;
    buf[2] = 0;

    row3_de_hl(0xAA55, &buf[0]);
    __builtin_v6clang_out(0xDE, (uint8_t)buf[0]);

    g_r = row2_hl_reused(&buf[1], 0x1234);
    __builtin_v6clang_out(0xDE, (uint8_t)g_r);

    g_a = row5_bc_hl_a_live(0xCAFE, 0x99, &buf[2]);
    __builtin_v6clang_out(0xDE, (uint8_t)g_a);

    row6_bc_bc(0x1111, 0x2222, &buf[0]);
    __builtin_v6clang_out(0xDE, (uint8_t)buf[0]);

    g_r = row4_de_de(0xBEEF, &buf[1]);
    __builtin_v6clang_out(0xDE, (uint8_t)g_r);

    return 0;
}
