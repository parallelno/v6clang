/* O92: Unified cross-BB physical-register value forwarding.
 *
 * A loop-invariant value parked in a general register, but needed in the
 * accumulator for an i8 CMP each iteration, currently gets reloaded with a
 * per-iteration `MOV A, <reg>` inside the loop body even though A already
 * holds it on entry and the body never changes A or the source register.
 *
 * O92 adds a cross-BB value-forwarding dataflow pass that proves the reload
 * is redundant across the loop back-edge and erases it.
 *
 * The `volatile seed` forces the bound `n` to be materialized from memory
 * (so the register allocator parks it in a general register, not A), which is
 * what produces the redundant `MOV A, <reg>` reloads inside the loops — the
 * exact shape seen in the fannkuch benchmark.
 *
 * Expected: the in-loop `MOV A, D` (or whichever register parks the bound)
 * reloads disappear; the value is established once before each loop.
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

/* Non-A coverage: a 16-bit pointer parked in a register pair and reused
 * across two loops.  Exercises DE/HL/BC and many non-A moves
 * (MOV C,M / MOV B,M / MOV L,A / MOV H,A), confirming the value-forwarding
 * lattice is register-agnostic and does not miscompile non-A code.
 * (Deterministic per-register elision is proven in the lit test.) */
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
