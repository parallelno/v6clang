/* tests/features/53/c8080.c
 *
 * c8080 reference. Mirrors v6clang.c functions for asm-comparison.
 * c8080 doesn't compile __builtin_v6clang_out, so main() just returns
 * after calling each helper.
 */

typedef unsigned char  uint8_t;
typedef unsigned short uint16_t;

uint16_t g_a;
uint16_t g_b;
uint16_t g_r;
uint8_t  g_byte;

uint16_t bug3_de_de(uint16_t sum_in_hl, uint16_t *p_in_de) {
    uint16_t v = *p_in_de;
    return sum_in_hl + v;
}

uint16_t case2_hl_reused(uint16_t *p) {
    uint16_t lo = p[0];
    uint16_t hi = p[0];
    return lo + hi;
}

uint16_t case5_bc_with_hl_live(uint16_t *p, uint16_t hl_keep) {
    uint16_t v = *p;
    return v + hl_keep;
}

uint8_t case16_a_live(uint16_t *p, uint8_t a_keep) {
    uint16_t v = *p;
    return (uint8_t)(v >> 8) ^ a_keep;
}

uint16_t buf[2];

int main(int argc, char **argv) {
    buf[0] = 0x1234;
    buf[1] = 0x5678;

    g_r = bug3_de_de(0x1000, &buf[0]);
    g_byte = (uint8_t)g_r;

    g_r = case2_hl_reused(&buf[1]);
    g_r = case5_bc_with_hl_live(&buf[0], 0x0001);
    g_byte = case16_a_live(&buf[1], 0x42);

    return 0;
}
