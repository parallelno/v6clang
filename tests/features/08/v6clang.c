// Test case for O27: i16 Zero-Test Optimization
// Tests that 16-bit comparisons against zero use MOV+ORA idiom
// instead of the full MVI+CMP MBB-splitting expansion.

extern int bar(int x);
extern int baz(int x);

// Pattern A: if (x) — basic non-zero test (NE)
// Should use: MOV A,H; ORA L; JNZ
int test_ne_zero(int x) {
    if (x)
        return bar(x);
    return 0;
}

// Pattern B: if (!x) — zero test (EQ)
// Should use: MOV A,H; ORA L; JZ
int test_eq_zero(int x) {
    if (!x)
        return 0;
    return bar(x);
}

// Pattern C: while (n) loop — loop condition zero test
// Should use: MOV A,H; ORA L; JNZ for loop back-edge
// Uses volatile to prevent SCEV closed-form optimization.
int test_while_loop(int n) {
    volatile int sum = 0;
    while (n) {
        sum += n;
        n--;
    }
    return sum;
}

// Pattern D: null pointer check
// Should use: MOV A,H; ORA L; JZ or JNZ
int test_null_ptr(int *p) {
    if (p)
        return *p;
    return -1;
}

int main(void) {
    int r = test_ne_zero(5);
    r += test_eq_zero(0);
    r += test_while_loop(10);
    int val = 42;
    r += test_null_ptr(&val);
    return r;
}
