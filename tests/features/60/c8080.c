// c8080 reference for O78 — V6CLANG_STORE8_IMM_P per-shape redesign.
//
// c8080 cannot pin specific physical registers, so this is a plain
// baseline: each test stores an immediate byte through a pointer
// alongside live carrier values. Cycle/byte costs serve as the
// comparison anchor for v6clang's old vs new shapes.

typedef unsigned char u8;
typedef unsigned short u16;

extern volatile u8 g_sink;

void store_hl(u8 *p) {
    *p = 0x42;
}

void store_bc_a_dead(unsigned hl_keep, unsigned de_keep, u8 *p) {
    *p = 0x42;
    g_sink = (u8)hl_keep;
    g_sink = (u8)de_keep;
}

void store_de_a_dead(unsigned hl_keep, u8 *p) {
    *p = 0x42;
    g_sink = (u8)hl_keep;
}

void store_de_a_live(unsigned hl_keep, u8 *p, u8 a_keep) {
    *p = 0x42;
    g_sink = a_keep;
    g_sink = (u8)hl_keep;
}

void store_bc_hl_dead(unsigned hl_keep, unsigned de_keep, u8 *p, u8 a_keep) {
    g_sink = (u8)hl_keep;
    *p = 0x42;
    g_sink = a_keep;
    g_sink = (u8)de_keep;
}

void store_bc_de_dead(unsigned hl_keep, unsigned de_keep, u8 *p, u8 a_keep) {
    g_sink = (u8)de_keep;
    *p = 0x42;
    g_sink = a_keep;
    g_sink = (u8)hl_keep;
}

void store_bc_all_live(unsigned hl_keep, unsigned de_keep, u8 *p, u8 a_keep) {
    *p = 0x42;
    g_sink = a_keep;
    g_sink = (u8)hl_keep;
    g_sink = (u8)de_keep;
}

volatile u8  g_a    = 0x12;
volatile u8  g_buf  = 0x00;
volatile u16 g_hl   = 0x1234;
volatile u16 g_de   = 0x5678;
volatile u8  g_sink;

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    u8 *p = (u8 *)&g_buf;
    store_hl(p);
    store_bc_a_dead(g_hl, g_de, p);
    store_de_a_dead(g_hl, p);
    store_de_a_live(g_hl, p, g_a);
    store_bc_hl_dead(g_hl, g_de, p, g_a);
    store_bc_de_dead(g_hl, g_de, p, g_a);
    store_bc_all_live(g_hl, g_de, p, g_a);
    return 0;
}
