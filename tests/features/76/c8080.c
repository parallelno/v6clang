/* O92: Unified cross-BB physical-register value forwarding — c8080 reference.
 *
 * Same source as v6clang.c. c8080 uses 'unsigned char' for 8-bit values.
 */
typedef unsigned char u8;

u8 perm1[8];
u8 count[8];

u8 repro(void) {
    volatile u8 seed = 7;
    u8 n = seed;
    u8 i, r;

    for (i = 0; i < n; i++)
        perm1[i] = i;
    r = n;

    for (;;) {
        while (r != 1) {
            count[r - 1] = r;
            r--;
        }
        if (r == n)
            return r;
        count[r] = (u8)(count[r] - 1);
        r++;
    }
}

typedef unsigned int u16;

u16 walk16(u16 *p, u8 n) {
    volatile u8 seed = n;
    u8 m = seed;
    u16 acc = 0;
    u8 i;
    for (i = 0; i < m; i++)
        acc = (u16)(acc + p[i]);
    for (i = 0; i < m; i++)
        acc = (u16)(acc ^ p[i]);
    return acc;
}

static u16 buf[8];

int main(int argc, char **argv) {
    volatile u8  a = repro();
    volatile u16 b = walk16(buf, 4);
    return 0;
}
