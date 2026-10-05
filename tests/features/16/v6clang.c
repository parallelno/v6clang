// Test case for O37: Deferred Zero-Load After Zero-Test
// When both paths after a zero-test need HL=0, the compiler should
// sink LXI HL,0 past the branch instead of hoisting it before.
// On the zero-taken path, HL is already 0 (branch-proven by O36).

extern int bar(int x);

// Pattern 1: if (x == 0) return bar(0); return 0;
// Both paths need HL=0. The LXI HL,0 should be sunk past the branch.
int test_cond_zero_return_zero(int x) {
    if (x == 0) return bar(0);
    return 0;
}

// Pattern 2: if (x == 0) return bar(0); return bar(0);
// Both paths call bar(0). The LXI HL,0 should be sunk.
int test_both_call_zero(int x) {
    if (x == 0) return bar(0);
    return bar(0);
}

// Pattern 3: Negative — only one path uses zero, no sinking needed.
int test_one_path_zero(int x) {
    if (x == 0) return bar(0);
    return x;
}

int main() {
    volatile int r;
    r = test_cond_zero_return_zero(0);
    r = test_cond_zero_return_zero(5);
    r = test_both_call_zero(0);
    r = test_both_call_zero(5);
    r = test_one_path_zero(0);
    r = test_one_path_zero(5);
    return 0;
}
