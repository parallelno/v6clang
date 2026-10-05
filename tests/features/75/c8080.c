/* Feature 75 — O92 LXI-half-through-MOV collapse — c8080 reference
 *
 * c8080 uses 'unsigned int' for 16-bit and 'unsigned char' for 8-bit.
 * This program mirrors v6clang.c so the produced assembly is comparable.
 */

typedef unsigned char u8;
typedef unsigned int  u16;

u16 g_sink16;
u8  g_sink8;

u8 lxi_lo_used(u16 x) {
    u16 mask;
    mask = 0xB4FF;
    g_sink16 = x ^ mask;
    return (u8)(mask & 0xFF);
}

u8 lxi_hi_used(u16 x) {
    u16 mask;
    mask = 0xB4FF;
    g_sink16 = x ^ mask;
    return (u8)(mask >> 8);
}

u16 lxi_lo_to_b(u16 x) {
    u16 mask;
    mask = 0x9A37;
    g_sink16 = x ^ mask;
    return (u16)((u8)(mask & 0xFF));
}

u8 lxi_lo_zero(u16 x) {
    u16 mask;
    mask = 0xB400;
    g_sink16 = x ^ mask;
    return (u8)(mask & 0xFF);
}

int main(int argc, char** argv) {
    g_sink8 = lxi_lo_used(0x1234);
    g_sink8 = lxi_hi_used(0x5678);
    g_sink16 = lxi_lo_to_b(0x9abc);
    g_sink8 = lxi_lo_zero(0xdef0);
    return 0;
}
