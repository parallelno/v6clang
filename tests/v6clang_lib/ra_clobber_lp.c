/* Lower-pressure RA test.  Only 1 i16 value is alive across the
 * doubler call; the rest of the function does no further i16
 * arithmetic that would force HL-routing.  This isolates whether RA
 * actually keeps the i16 in HL across each variant.
 */
#include <stdint.h>

extern volatile uint16_t sink16;
extern volatile uint8_t  sink8;

static __attribute__((noinline))
uint8_t doubler_static_noinline(uint8_t x) {
    uint8_t r;
    __asm__("ADD A" : "=a"(r) : "a"(x) : "FLAGS");
    return r;
}

__attribute__((noinline, weak))
uint8_t doubler_weak_noinline(uint8_t x) {
    uint8_t r;
    __asm__("ADD A" : "=a"(r) : "a"(x) : "FLAGS");
    return r;
}

__attribute__((noinline, weak))
uint8_t doubler_body(uint8_t x) {
    uint8_t r;
    __asm__("ADD A" : "=a"(r) : "a"(x) : "FLAGS");
    return r;
}
static inline __attribute__((always_inline))
uint8_t doubler_wrapper(uint8_t x) {
    uint8_t r;
    __asm__("CALL doubler_body" : "=a"(r) : "a"(x) : "FLAGS");
    return r;
}

static inline __attribute__((always_inline))
uint8_t doubler_inline(uint8_t x) {
    uint8_t r;
    __asm__("ADD A" : "=a"(r) : "a"(x) : "FLAGS");
    return r;
}

/* ------- low-pressure callers: only ONE i16 alive across op ------- */

uint16_t lp1_static_noinline(uint16_t hl_val, uint8_t d) {
    sink8 = doubler_static_noinline(d);
    return hl_val;          /* hl_val must survive in HL across call */
}
uint16_t lp2_weak_noinline(uint16_t hl_val, uint8_t d) {
    sink8 = doubler_weak_noinline(d);
    return hl_val;
}
uint16_t lp3_wrapper(uint16_t hl_val, uint8_t d) {
    sink8 = doubler_wrapper(d);
    return hl_val;
}
uint16_t lp4_inline(uint16_t hl_val, uint8_t d) {
    sink8 = doubler_inline(d);
    return hl_val;
}
uint16_t lp5_plain(uint16_t hl_val, uint8_t d) {
    sink8 = (uint8_t)(d + d);
    return hl_val;
}

volatile uint16_t sink16;
volatile uint8_t  sink8;
