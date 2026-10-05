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
    return x;
}

int main(void) {
    int r = test_ne_zero(5);
    return r;
}
