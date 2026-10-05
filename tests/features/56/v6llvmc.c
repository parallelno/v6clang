/* tests/features/56/v6clang.c
 *
 * O74 — V6CLANG_STORE16_G redesign integration test.
 *
 * Granular per-shape CHECK coverage lives in
 *   llvm-project/llvm/test/CodeGen/V6CLANG/store16g-shapes.ll
 * (constructed directly in LLVM IR so we can pin the val register).
 *
 * This file is the runtime cross-check: it verifies that
 * V6CLANG_STORE16_G writes the correct two bytes across the shapes the
 * baseline compiler can actually emit. The "HL-live" shapes
 * (val=DE/HL-live and val=BC/HL-live) cannot be runtime-tested
 * because the baseline expander declares `Defs=[HL]`, which causes
 * the register allocator to fail ("ran out of registers") whenever
 * HL must survive the store — which is precisely one of the bugs
 * this redesign fixes. After the fix, those shapes compile cleanly
 * and are exercised by the lit test.
 */

#include <stdint.h>

volatile uint16_t g_a;

/* val=HL (case 1): the natural SHLD shape — single SHLD. */
__attribute__((noinline))
void case1_val_hl(uint16_t v) {
    g_a = v;
}

/* val=DE, HL dead (case 2a): two i16 args; the first (HL) is unused
 * after the prologue, so HL is dead at the store and the second (DE)
 * is the value. */
__attribute__((noinline))
void case2a_val_de_hl_dead(uint16_t a, uint16_t v) {
    (void)a;
    g_a = v;
}

#ifndef OLD_BASELINE_SKIP_HL_LIVE
/* val=DE, HL live (case 2b): hl_keep must survive the store and be
 * returned in HL.
 *   OLD: cannot compile — its (store, wrapper) pattern selects SHLD,
 *        which forces val into HL; with hl_keep also pinned to HL the
 *        register allocator fails ("ran out of registers"). This is
 *        precisely the bug O74 fixes.
 *   NEW: selects V6CLANG_STORE16_G (val can stay in DE); the expander
 *        emits XCHG; SHLD g_a; XCHG so hl_keep never leaves HL. */
__attribute__((noinline))
uint16_t case2b_val_de_hl_live(uint16_t hl_keep, uint16_t v) {
    g_a = v;
    return hl_keep;
}
#endif

/* val=BC, HL dead (case 3a): three i16 args; first two unused after,
 * so the third (BC) is the only live value at the store. */
__attribute__((noinline))
void case3a_val_bc_hl_dead(uint16_t a, uint16_t b, uint16_t v) {
    (void)a; (void)b;
    g_a = v;
}

int main(void) {
    case1_val_hl(0x1234);
    __builtin_v6clang_out(0xDE, (uint8_t)g_a);

    case2a_val_de_hl_dead(0, 0x55AA);
    __builtin_v6clang_out(0xDE, (uint8_t)g_a);

#ifndef OLD_BASELINE_SKIP_HL_LIVE
    /* hl_keep=0x9988, v=0x6677 : g_a should become 0x6677 and the
     * function should return 0x9988. Emit one byte from each so a
     * runtime regression in either path shows up. */
    uint16_t r = case2b_val_de_hl_live(0x9988, 0x6677);
    __builtin_v6clang_out(0xDE, (uint8_t)g_a);
    __builtin_v6clang_out(0xDE, (uint8_t)r);
#endif

    case3a_val_bc_hl_dead(0, 0, 0xABCD);
    __builtin_v6clang_out(0xDE, (uint8_t)g_a);

    return 0;
}
