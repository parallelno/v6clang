// c8080 reference for O68 Phase 2 — rotl i16 by 1 test.
// Same shape as v6clang.c.

typedef unsigned short u16;
typedef unsigned char  u8;

u16 rotl_u16_1(u16 x) { return (u16)((x << 1) | (x >> 15)); }

u16 crc16_step(u16 crc, u8 byte) {
    crc ^= ((u16)byte) << 8;
    for (int i = 0; i < 8; ++i) {
        u16 hi = crc & 0x8000;
        crc = (u16)(crc << 1);
        if (hi) crc ^= 0x1021;
    }
    return crc;
}

u16 rotl_u16_2(u16 x) { return (u16)((x << 2) | (x >> 14)); }

// c8080 doesn't recognise __builtin_rotateleft16 — express the
// funnel-shift longhand instead so the C source compiles.
u16 fshl_u16_1(u16 x) { return (u16)((x << 1) | (x >> 15)); }

volatile u16 g_in  = 0x1234;
volatile u8  g_byte = 0x5A;
volatile u16 g_out;

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    g_out = rotl_u16_1(g_in);
    g_out = crc16_step(g_in, g_byte);
    g_out = rotl_u16_2(g_in);
    g_out = fshl_u16_1(g_in);
    return 0;
}
