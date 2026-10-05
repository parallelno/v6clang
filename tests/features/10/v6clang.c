// Test case for O30: Conditional Return Peephole (Jcc RET → Rcc)
// Tests that conditional branches targeting RET-only blocks are replaced
// with conditional return instructions (RZ, RNZ, RC, etc.)

extern int bar(int x);
extern int baz(int x);

// Pattern A: if (x) return bar(x); return 0;
// The JZ to RET block should become RZ.
int test_ne_zero(int x) {
    if (x)
        return bar(x);
    return 0;
}

// Pattern B: if (!x) return 0; return bar(x);
// The JZ to RET block should become RZ.
int test_eq_zero(int x) {
    if (!x)
        return 0;
    return bar(x);
}

// Pattern C: multiple returns from different conditions
// Both branches to RET should become Rcc.
int test_multi_cond(int x) {
    if (x == 1)
        return 10;
    if (x == 2)
        return 20;
    return bar(x);
}

// Pattern D: null pointer guard
// The branch past the guard should become Rcc.
int test_null_guard(int *p) {
    if (p)
        return *p;
    return -1;
}

int main(void) {
    int r = test_ne_zero(5);
    r += test_eq_zero(0);
    r += test_multi_cond(1);
    r += test_multi_cond(2);
    r += test_multi_cond(3);
    int val = 42;
    r += test_null_guard(&val);
    return r;
}
