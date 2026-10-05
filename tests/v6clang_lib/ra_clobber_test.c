/* RA-awareness test for the v6clang_arith.h inlining policy.
 *
 * Defines the SAME operation (double a u8 value: result = x + x) in
 * multiple function-definition styles, then in main() exercises high
 * register pressure across each call to see which live values RA can
 * keep in registers vs has to spill.
 *
 * The operation itself clobbers ONLY A and FLAGS. So:
 *   - If RA sees the asm clobber list (inlined-asm path) it can keep
 *     HL, DE, BC live across the operation.
 *   - If RA goes through a real CALL (noinline path), it must assume
 *     the empty getCallPreservedMask -> everything clobbered, so all
 *     three pair regs spill to the stack.
 *
 * Build:
 *   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 \
 *       -S tests\v6clang_lib\ra_clobber_test.c -o temp\ra_clobber_test.s
 *
 * Inspect each callerN function in the .s file.
 */
#include <stdint.h>

/* ===== Variant 1: noinline static C function, asm body ===========
 * Result: emits CALL. RA assumes empty preserved mask. Single
 * per-TU copy due to `static`, but no user override possible.
 */
static __attribute__((noinline))
uint8_t doubler_static_noinline(uint8_t x) {
    uint8_t r;
    __asm__("ADD A"            /* A = A + A */
            : "=a"(r) : "a"(x) : "FLAGS");
    return r;
}

/* ===== Variant 2: weak noinline (non-static), asm body ============
 * Result: emits CALL just like variant 1. User can override with a
 * strong definition. One copy per program (linker dedupes weak).
 */
__attribute__((noinline, weak))
uint8_t doubler_weak_noinline(uint8_t x) {
    uint8_t r;
    __asm__("ADD A" : "=a"(r) : "a"(x) : "FLAGS");
    return r;
}

/* ===== Variant 3: wrapper trick =================================
 * Inline wrapper holds ONLY a CALL to the body, but with a precise
 * clobber list. The body is noinline.
 *
 * Hypothesis under test: does RA see the wrapper's clobber list at
 * the call site, even though the wrapper expands to a CALL? If yes,
 * HL/DE/BC stay live. If no, RA treats it like any other CALL.
 */
__attribute__((noinline))
static uint8_t doubler_body(uint8_t x) {
    uint8_t r;
    __asm__("ADD A" : "=a"(r) : "a"(x) : "FLAGS");
    return r;
}

static inline __attribute__((always_inline))
uint8_t doubler_wrapper(uint8_t x) {
    uint8_t r;
    __asm__("CALL doubler_body"
            : "=a"(r) : "a"(x) : "FLAGS");
    return r;
}

/* ===== Variant 4: small static always_inline with full asm body ==
 * Result: asm body inlined at every call site. RA sees the clobber
 * list directly, no CALL involved.
 */
static inline __attribute__((always_inline))
uint8_t doubler_inline(uint8_t x) {
    uint8_t r;
    __asm__("ADD A" : "=a"(r) : "a"(x) : "FLAGS");
    return r;
}

/* ===== Variant 5: plain C noinline (no asm) =====================
 * Baseline: a regular C function, no asm. RA must spill.
 */
static __attribute__((noinline))
uint8_t doubler_plain(uint8_t x) {
    return (uint8_t)(x + x);
}

/* ============================================================ */
/* Pressure-inducing callers.                                   */
/*                                                              */
/* Each takes 4 u16 args -> a in HL, b in DE, c in BC (per V6CLANG  */
/* CC), d on stack. We force a,b,c to be live across the call,  */
/* and then sum them into the return value.  If RA can keep     */
/* them in HL/DE/BC, the function is short.  If it has to spill */
/* across the call, we'll see SHLD/LHLD or PUSH/POP traffic.    */
/* ============================================================ */

extern volatile uint16_t sink;

/* Macro to keep the bodies identical except for the call. */
#define CALLER_BODY(CALL_EXPR)                                  \
    a = a + 1u;                                                 \
    b = b + 2u;                                                 \
    c = c + 3u;                                                 \
    sink = (uint16_t)(CALL_EXPR);                               \
    return (uint16_t)(a + b + c)

uint16_t caller1_static_noinline(uint16_t a, uint16_t b, uint16_t c, uint8_t d) {
    CALLER_BODY(doubler_static_noinline(d));
}

uint16_t caller2_weak_noinline(uint16_t a, uint16_t b, uint16_t c, uint8_t d) {
    CALLER_BODY(doubler_weak_noinline(d));
}

uint16_t caller3_wrapper(uint16_t a, uint16_t b, uint16_t c, uint8_t d) {
    CALLER_BODY(doubler_wrapper(d));
}

uint16_t caller4_inline(uint16_t a, uint16_t b, uint16_t c, uint8_t d) {
    CALLER_BODY(doubler_inline(d));
}

uint16_t caller5_plain(uint16_t a, uint16_t b, uint16_t c, uint8_t d) {
    CALLER_BODY(doubler_plain(d));
}

/* Force all callers to be retained. */
volatile uint16_t sink;
typedef uint16_t (*caller_t)(uint16_t, uint16_t, uint16_t, uint8_t);
caller_t callers[] = {
    caller1_static_noinline,
    caller2_weak_noinline,
    caller3_wrapper,
    caller4_inline,
    caller5_plain,
};
