// c8080 reference for O75 — flag-producing arithmetic SDNodes.
// Same shape as v6clang.c. Each function exercises one shape that
// the optimization is supposed to fold into a flag-producing arith
// instruction followed by a conditional branch, eliminating the
// trailing CPI 0 / ORA A and the accumulator round-trip.

typedef unsigned char u8;
typedef unsigned short u16;

// Loop counter — the canonical motivating case.
extern volatile u8 g_sink;
u16 dec_loop(u8 n) {
    u16 sum = 0;
    while (n) { g_sink = n; sum += n; --n; }
    return sum;
}

// Mask test — A becomes the natural location for the value, but no
// trailing CPI 0 should be emitted.
u8 mask_test(u8 x) {
    return (x & 0x0F) == 0 ? (u8)1 : (u8)0;
}

// XOR test — XRA r already sets Z; no CPI 0 needed.
u8 xor_test(u8 x, u8 y) {
    u8 z = x ^ y;
    g_sink = z;
    return z != 0 ? (u8)1 : (u8)0;
}

u8 sub_test(u8 x) {
    u8 z = x - 5;
    g_sink = z;
    return z != 0 ? (u8)1 : (u8)0;
}

// Counter that is also consumed AFTER the loop body — flags+value used.
u16 dec_loop_used(u8 n) {
    u16 sum = 0;
    while (n) { g_sink = n; sum += n; --n; }
    return sum + (u16)n;
}

volatile u8  g_n = 7;
volatile u8  g_x = 0x33;
volatile u8  g_y = 0x33;
volatile u16 g_out;
volatile u8  g_outb;
volatile u8  g_sink;

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    g_out  = dec_loop(g_n);
    g_outb = mask_test(g_x);
    g_outb = xor_test(g_x, g_y);
    g_outb = sub_test(g_x);
    g_out  = dec_loop_used(g_n);
    return 0;
}
