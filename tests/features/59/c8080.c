// c8080 reference for O77 — V6CLANG_STORE8_P per-shape redesign.
//
// c8080 cannot pin specific physical registers, so this is a plain
// baseline: each test stores a byte through a pointer alongside a
// live carrier value, forcing the compiler to keep both alive
// across the store. The cycle/byte cost from c8080 is the
// comparison anchor for v6clang's old vs new shapes.

typedef unsigned char u8;
typedef unsigned short u16;

extern volatile u8 g_sink;

void store_use_b(unsigned hl_keep, u8 *p, u8 a_keep, u8 v) {
    *p = v;
    g_sink = a_keep;
    g_sink = (u8)hl_keep;
}

void store_use_c(unsigned hl_keep, u8 *p, u8 a_keep, u8 v) {
    *p = v;
    g_sink = a_keep;
    g_sink = (u8)hl_keep;
}

void store_use_h(unsigned hl_keep, u8 *p, u8 a_keep, u8 v) {
    *p = v;
    g_sink = a_keep;
}

void store_use_l(unsigned hl_keep, u8 *p, u8 a_keep, u8 v) {
    *p = v;
    g_sink = a_keep;
}

void store_via_bc(unsigned hl_keep, unsigned de_keep, u8 *p, u8 a_keep, u8 v) {
    *p = v;
    g_sink = a_keep;
    g_sink = (u8)hl_keep;
    g_sink = (u8)de_keep;
}

volatile u8  g_a    = 0x12;
volatile u8  g_v    = 0x77;
volatile u8  g_buf  = 0x00;
volatile u16 g_hl   = 0x1234;
volatile u16 g_de   = 0x5678;
volatile u8  g_sink;

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    u8 *p = (u8 *)&g_buf;
    store_use_b(g_hl, p, g_a, g_v);
    store_use_c(g_hl, p, g_a, g_v);
    store_use_h(g_hl, p, g_a, g_v);
    store_use_l(g_hl, p, g_a, g_v);
    store_via_bc(g_hl, g_de, p, g_a, g_v);
    return 0;
}
