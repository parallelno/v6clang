/* O11: Dual Cost Model — feature test case
 *
 * Tests pointer increment thresholds where INX/DCX chains
 * compete with LXI+DAD sequences. The cost model should
 * derive the optimal cut-off automatically.
 *
 * ptr + 1 → 1×INX (8cc, 1B)   vs LXI+DAD (24cc, 4B)  → INX
 * ptr + 2 → 2×INX (16cc, 2B)  vs LXI+DAD (24cc, 4B)  → INX
 * ptr + 3 → 3×INX (24cc, 3B)  vs LXI+DAD (24cc, 4B)  → INX (tied cc, fewer bytes)
 * ptr + 4 → 4×INX (32cc, 4B)  vs LXI+DAD (24cc, 4B)  → DAD (cheaper cc, same bytes)
 */

volatile unsigned char mem[16];

unsigned char read_offset1(unsigned char *p) {
    return *(p + 1);
}

unsigned char read_offset2(unsigned char *p) {
    return *(p + 2);
}

unsigned char read_offset3(unsigned char *p) {
    return *(p + 3);
}

unsigned char read_offset4(unsigned char *p) {
    return *(p + 4);
}

/* Sum two adjacent bytes — exercises INX vs LXI for sequential access */
unsigned int sum_adjacent(unsigned char *p) {
    return (unsigned int)p[0] + p[1];
}

/* Sum three sequential bytes — exercises 2×INX after first load */
unsigned int sum_three(unsigned char *p) {
    return (unsigned int)p[0] + p[1] + p[2];
}

int main(int argc, char **argv) {
    unsigned char *p = (unsigned char *)mem;
    read_offset1(p);
    read_offset2(p);
    read_offset3(p);
    read_offset4(p);
    sum_adjacent(p);
    sum_three(p);
    return 0;
}
