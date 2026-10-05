// Test case for O29: Cross-BB Immediate Value Propagation
// Tests redundant MVI elimination when lo8 == hi8 in 16-bit comparisons.

extern void action_a(void);
extern void action_b(void);

// Case 1: NE with lo8 == hi8 (0x4242) — second MVI A, 0x42 should be eliminated
unsigned int test_ne_same_bytes(unsigned int x) {
    if (x != 0x4242) {
        action_a();
    }
    action_b();
    return x;
}

// Case 2: EQ with lo8 == hi8
unsigned int test_eq_same_bytes(unsigned int x) {
    if (x == 0x4242) {
        action_a();
    }
    action_b();
    return x;
}

// Case 3: NE with lo8 != hi8 (control — both MVI must remain)
unsigned int test_ne_diff_bytes(unsigned int x) {
    if (x != 0x1234) {
        action_a();
    }
    action_b();
    return x;
}

// Case 4: NE with 0x0101 — another lo8==hi8 case
unsigned int test_ne_0101(unsigned int x) {
    if (x != 0x0101) {
        action_a();
    }
    action_b();
    return x;
}

int main(void) {
    volatile unsigned int r;
    r = test_ne_same_bytes(0);
    r = test_ne_same_bytes(0x4242);
    r = test_ne_same_bytes(0x1234);
    r = test_eq_same_bytes(0);
    r = test_eq_same_bytes(0x4242);
    r = test_ne_diff_bytes(0);
    r = test_ne_diff_bytes(0x1234);
    r = test_ne_0101(0);
    r = test_ne_0101(0x0101);
    return 0;
}
