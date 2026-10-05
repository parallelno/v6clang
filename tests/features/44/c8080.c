// c8080 reference for O67 — i8 rotate ISel test. Same shape as v6clang.c.

typedef unsigned char u8;

u8 rotl1(u8 x) { return (u8)((x << 1) | (x >> 7)); }
u8 rotr1(u8 x) { return (u8)((x >> 1) | (x << 7)); }
u8 rotl3(u8 x) { return (u8)((x << 3) | (x >> 5)); }
u8 rotr3(u8 x) { return (u8)((x >> 3) | (x << 5)); }
u8 rotl7(u8 x) { return (u8)((x << 7) | (x >> 1)); }
u8 rotl4(u8 x) { return (u8)((x << 4) | (x >> 4)); }

volatile u8 g_in = 0x5A;
volatile u8 g_out;

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    g_out = rotl1(g_in);
    g_out = rotr1(g_in);
    g_out = rotl3(g_in);
    g_out = rotr3(g_in);
    g_out = rotl7(g_in);
    g_out = rotl4(g_in);
    return 0;
}
