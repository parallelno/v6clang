// Test case for O31: Dead PHI-Constant Elimination
// Tests that redundant LXI constants for PHI nodes are eliminated
// when a branch proves the register already holds the constant value.

// bar is extern to prevent inlining — the optimization fires on the
// conditional return-0 pattern which requires bar to be opaque.
extern int bar(int x);

// Pattern A: if (x) bar(x); return 0;
// PHI [0, entry] + icmp eq x, 0 → constant 0 eliminated (COND_Z taken edge)
// Should NOT have LXI HL, 0 or MOV D,H/MOV E,L shuffle
int test_ne_zero(int x) {
    if (x)
        return bar(x);
    return 0;
}

// Pattern B: if (!x) return 0; return bar(x);
// PHI [0, entry] + icmp ne x, 0 → constant 0 eliminated (COND_NZ fallthrough)
int test_eq_zero(int x) {
    if (!x)
        return 0;
    return bar(x);
}

// Pattern C: if (x == 42) return 42; return bar(x);
// PHI [42, entry] + icmp eq x, 42 → general constant eliminated
int test_const_42(int x) {
    if (x == 42)
        return 42;
    return bar(x);
}

// Pattern D (negative): if (x == 1) return 0; return bar(x);
// PHI [0, entry] + icmp eq x, 1 → NO elimination (different constants)
int test_different_const(int x) {
    if (x == 1)
        return 0;
    return bar(x);
}

int main(void) {
    int r = test_ne_zero(5);
    r += test_eq_zero(0);
    r += test_const_42(42);
    r += test_different_const(1);
    return r;
}
