/* tests/features/56/c8080.c
 *
 * c8080 reference. Mirrors v6clang.c functions for asm comparison.
 */

typedef unsigned char  uint8_t;
typedef unsigned short uint16_t;

uint16_t g_a;

void case1_val_hl(uint16_t v) {
    g_a = v;
}

void case2a_val_de_hl_dead(uint16_t a, uint16_t v) {
    g_a = v;
}

uint16_t case2b_val_de_hl_live(uint16_t hl_keep, uint16_t v) {
    g_a = v;
    return hl_keep;
}

void case3a_val_bc_hl_dead(uint16_t a, uint16_t b, uint16_t v) {
    g_a = v;
}

int main(int argc, char **argv) {
    case1_val_hl(0x1234);
    case2a_val_de_hl_dead(0, 0x55AA);
    uint16_t r = case2b_val_de_hl_live(0x9988, 0x6677);
    case3a_val_bc_hl_dead(0, 0, 0xABCD);
    return r;
}
