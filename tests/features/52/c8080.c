/* tests/features/52/c8080.c
 *
 * c8080 reference. Same shape as v6clang.c. c8080 has its own
 * builtin runtime so the same operators just work; we read the
 * generated asm to compare body length / CPU cycles against the
 * v6clang output.
 */

typedef unsigned char  uint8_t;
typedef unsigned short uint16_t;

uint8_t  g_u8a;
uint8_t  g_u8b;
uint8_t  g_u8r;
uint16_t g_u16a;
uint16_t g_u16b;
uint16_t g_u16r;

uint8_t mul_u8(uint8_t a, uint8_t b)            { return a * b; }
uint16_t mul_u16(uint16_t a, uint16_t b)        { return a * b; }
uint16_t div_u16(uint16_t a, uint16_t b)        { return a / b; }
uint16_t mod_u16(uint16_t a, uint16_t b)        { return a % b; }
uint16_t shl_u16(uint16_t a, uint8_t  n)        { return a << n; }

int main(int argc, char **argv) {
    g_u8r  = mul_u8 (g_u8a,  g_u8b);
    g_u16r = mul_u16(g_u16a, g_u16b);
    g_u16r = div_u16(g_u16a, g_u16b);
    g_u16r = mod_u16(g_u16a, g_u16b);
    g_u16r = shl_u16(g_u16a, g_u8a);
    return 0;
}
