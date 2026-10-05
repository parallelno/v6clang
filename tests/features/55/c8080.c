/* tests/features/55/c8080.c
 *
 * c8080 reference. Mirrors v6clang.c functions for asm-comparison.
 */

typedef unsigned char  uint8_t;
typedef unsigned short uint16_t;

uint16_t g_a;
uint16_t g_b;
uint16_t g_c;
uint16_t g_r;
uint8_t  g_byte;

uint16_t case1_dst_hl(void) {
    return g_a;
}

uint16_t case2_dst_de(uint16_t hl_keep) {
    return hl_keep + g_a;
}

uint16_t add3(uint16_t a, uint16_t b, uint16_t c) {
    return a + b + c;
}

uint16_t case3_dst_bc(void) {
    return add3(g_a, g_b, g_c);
}


int main(int argc, char **argv) {
    g_a = 0x1234;
    g_b = 0x5678;
    g_c = 0x0001;

    g_r = case1_dst_hl();
    g_r = case2_dst_de(0x0100);
    g_r = case3_dst_bc();

    return 0;
}
