/* tests/features/54/c8080.c
 *
 * c8080 reference. Mirrors v6clang.c functions for asm-comparison.
 * c8080 doesn't compile __builtin_v6clang_out, so main() just stores
 * results into globals.
 */

typedef unsigned char  uint8_t;
typedef unsigned short uint16_t;

uint16_t g_a;
uint16_t g_b;
uint16_t g_r;

void row3_de_hl(uint16_t v, uint16_t *p) {
    *p = v;
    g_r = (uint16_t)p;
}

uint16_t row2_hl_reused(uint16_t *p, uint16_t v) {
    p[0] = v;
    return p[0];
}

uint8_t row5_bc_hl_a_live(uint16_t v, uint8_t a_keep, uint16_t *p) {
    *p = v;
    return a_keep ^ 0x42;
}

void row6_bc_bc(uint16_t a, uint16_t b, uint16_t *p) {
    *p = (uint16_t)p;
    g_a = a;
    g_b = b;
}

uint16_t row4_de_de(uint16_t hl_keep, uint16_t *p) {
    *p = (uint16_t)p;
    return hl_keep;
}

uint16_t buf[3];

int main(int argc, char **argv) {
    buf[0] = 0;
    buf[1] = 0;
    buf[2] = 0;

    row3_de_hl(0xAA55, &buf[0]);
    g_r = row2_hl_reused(&buf[1], 0x1234);
    g_r = row5_bc_hl_a_live(0xCAFE, 0x99, &buf[2]);
    row6_bc_bc(0x1111, 0x2222, &buf[0]);
    g_r = row4_de_de(0xBEEF, &buf[1]);

    return 0;
}
