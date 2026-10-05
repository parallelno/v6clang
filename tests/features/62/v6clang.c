// O80 — i8 zero-test compare via INR/DCR (A-preserving pseudo).
//
// Three shapes the new V6CLANG_CMP8_ZERO pseudo expands:
//   shape_a       : src already in A          → ORA A           (1B / 4cc)
//   shape_a_dead  : src in non-A reg, A dead  → MOV A,r; ORA A  (2B / 12cc)
//   shape_a_live  : src in non-A reg, A live  → INR r; DCR r    (2B / 16cc)
//
// shape_a_live is the headline win. The pre-O80 emission saves A to a
// scratch GR8 and restores it: 4B / 28cc + scratch register burn.
//
// Compile (baseline):
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\62\v6clang.c -o tests\features\62\v6clang_old.asm

__attribute__((leaf)) extern unsigned char op1(unsigned char x);
__attribute__((leaf)) extern void          sink(unsigned char x);
__attribute__((leaf)) extern void          use2(unsigned char a, unsigned char b);

// Shape 1: argument arrives in A, branched on directly. Expansion: ORA A.
unsigned char shape_a(unsigned char a) {
    if (a) return 1;
    return 0;
}

// Shape 2: argument in non-A reg, A dead at the branch (no producer, no
// later A consumer). Expansion: MOV A,r; ORA A — same as today.
unsigned char shape_a_dead(unsigned char x, unsigned char y) {
    if (y) return x;     // y in C; A free; classic shape-2 path
    return 0;
}

// Shape 3 — headline case. op1() returns its result in A and that value
// is needed on both branches; the cond byte is in a non-A reg and must
// be tested without disturbing A. Today: MOV scratch,A; MOV A,cond;
// ORA A; ...; MOV A,scratch. After O80: INR cond; DCR cond. Saves
// 2B / 12cc per fire and frees the scratch GR8.
unsigned char shape_a_live(unsigned char val_in_A, unsigned char cond) {
    unsigned char r = op1(val_in_A);
    if (cond) return (unsigned char)(r + 1);
    return r;
}

// Loop variant — shape 3 inside a hot loop. Today's per-iteration cost
// includes scratch save/restore on every back-edge; after O80 the
// compare collapses to 2B / 16cc.
unsigned char shape_a_live_loop(unsigned char seed, unsigned char n) {
    unsigned char acc = seed;
    while (n) {
        acc = op1(acc);   // result in A, must survive cond test below
        n--;              // n is the cond next iter; A live across test
    }
    return acc;
}

int main(void) {
    use2(shape_a(0x11),        shape_a(0));
    use2(shape_a_dead(0x22, 0x33), shape_a_dead(0x44, 0));
    use2(shape_a_live(0x55, 1),    shape_a_live(0x66, 0));
    sink(shape_a_live_loop(0x77, 5));
    return 0;
}
