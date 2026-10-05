// c8080 reference for O76 — V6CLANG_LOAD8_P per-shape redesign.
//
// c8080 cannot pin specific physical registers, so this is a plain
// baseline: each test reads a byte through a pointer and consumes
// it alongside another live value, forcing the compiler to keep
// both alive across the load. The cycle/byte cost from c8080 is
// the comparison anchor for v6clang's old vs new shapes.

typedef unsigned char u8;
typedef unsigned short u16;

extern volatile u8 g_a;
extern volatile u8 g_sink;
extern volatile u16 g_hl;
extern volatile u16 g_de;

// Load a byte and combine with two live carriers.
u8 load_use_b(unsigned hl_keep, const u8 *p, u8 a_keep) {
    u8 v = *p;
    g_sink = a_keep;
    g_sink = (u8)hl_keep;
    return v;
}

u8 load_use_c(unsigned hl_keep, const u8 *p, u8 a_keep) {
    u8 v = *p;
    g_sink = a_keep;
    g_sink = (u8)hl_keep;
    return v;
}

u8 load_use_h(unsigned hl_keep, const u8 *p, u8 a_keep) {
    u8 v = *p;
    g_sink = a_keep;
    return v;
}

u8 load_use_l(unsigned hl_keep, const u8 *p, u8 a_keep) {
    u8 v = *p;
    g_sink = a_keep;
    return v;
}

u8 load_via_bc(unsigned hl_keep, unsigned de_keep, const u8 *p, u8 a_keep) {
    u8 v = *p;
    g_sink = a_keep;
    g_sink = (u8)hl_keep;
    g_sink = (u8)de_keep;
    return v;
}

volatile u8  g_a    = 0x12;
volatile u8  g_buf  = 0x77;
volatile u16 g_hl   = 0x1234;
volatile u16 g_de   = 0x5678;
volatile u8  g_sink;

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    const u8 *p = (const u8 *)&g_buf;
    g_sink = load_use_b(g_hl, p, g_a);
    g_sink = load_use_c(g_hl, p, g_a);
    g_sink = load_use_h(g_hl, p, g_a);
    g_sink = load_use_l(g_hl, p, g_a);
    g_sink = load_via_bc(g_hl, g_de, p, g_a);
    return 0;
}
