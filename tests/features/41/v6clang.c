// Test case for O49 — direct memory ALU/store ISel (M-operand
// instructions: ADD/SUB/AND/OR/XOR/CMP M, MVI M, INR M, DCR M).
//
// Exercises the 11 M-operand forms through a pointer parameter so the
// register allocator sees addresses in all of HL/DE/BC across call
// sites. Every function has a single accumulator-heavy statement
// folding a loaded byte into an ALU op.
//
// Compile:
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\41\v6clang.c -o tests\features\41\v6clang_new01.asm \
//       -mllvm -mv6clang-annotate-pseudos

// ADD M via pointer.
unsigned char add_m(unsigned char a, const unsigned char *p) {
    return a + *p;
}

// SUB M via pointer.
unsigned char sub_m(unsigned char a, const unsigned char *p) {
    return a - *p;
}

// ANA M via pointer.
unsigned char and_m(unsigned char a, const unsigned char *p) {
    return a & *p;
}

// ORA M via pointer.
unsigned char or_m(unsigned char a, const unsigned char *p) {
    return a | *p;
}

// XRA M via pointer.
unsigned char xor_m(unsigned char a, const unsigned char *p) {
    return a ^ *p;
}

// CMP M via pointer.
int cmp_m(unsigned char a, const unsigned char *p) {
    return a == *p;
}

// MVI M via pointer (store immediate through pointer).
void store_imm(unsigned char *p) {
    *p = 0x42;
}

// INR M via pointer (read-modify-write through pointer).
void inc_m(unsigned char *p) {
    (*p)++;
}

// DCR M via pointer.
void dec_m(unsigned char *p) {
    (*p)--;
}

// Reduction loop — tight inner body folding load+ADD every iteration.
unsigned char sum_bytes(const unsigned char *p, unsigned char n) {
    unsigned char s = 0;
    for (unsigned char i = 0; i < n; ++i) s += p[i];
    return s;
}

int main(void) {
    static unsigned char buf[4] = {1, 2, 3, 4};
    unsigned char a = 0x10;
    a = add_m(a, buf);
    a = sub_m(a, buf + 1);
    a = and_m(a, buf + 2);
    a = or_m(a, buf + 3);
    a = xor_m(a, buf);
    cmp_m(a, buf);
    store_imm(buf);
    inc_m(buf + 1);
    dec_m(buf + 2);
    return sum_bytes(buf, 4);
}
