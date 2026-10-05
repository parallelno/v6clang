/* tests/features/52/v6clang.c
 *
 * O70 — header-only math runtime. The headline win this feature
 * test isolates is i8 multiply: today `MUL i8` is `Promote`d to i16
 * and runs `__mulhi3` (16 iterations); after O70 it lowers to
 * `__mulqi3` (8 iterations).
 *
 * Secondary: i16 *, /, %, << exercise the rest of the runtime.
 */

#include <stdint.h>

volatile uint8_t  g_u8a;
volatile uint8_t  g_u8b;
volatile uint8_t  g_u8r;
volatile uint16_t g_u16a;
volatile uint16_t g_u16b;
volatile uint16_t g_u16r;

uint8_t mul_u8(uint8_t a, uint8_t b)            { return a * b; }
uint16_t mul_u16(uint16_t a, uint16_t b)        { return a * b; }
uint16_t div_u16(uint16_t a, uint16_t b)        { return a / b; }
uint16_t mod_u16(uint16_t a, uint16_t b)        { return a % b; }
uint16_t shl_u16(uint16_t a, uint8_t  n)        { return a << n; }

int main(void) {
    g_u8r  = mul_u8 (g_u8a,  g_u8b);
    g_u16r = mul_u16(g_u16a, g_u16b);
    g_u16r = div_u16(g_u16a, g_u16b);
    g_u16r = mod_u16(g_u16a, g_u16b);
    g_u16r = shl_u16(g_u16a, g_u8a);
    return 0;
}
