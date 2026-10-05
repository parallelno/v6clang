// Test case for O23: Conditional Tail Call Optimization
// Tests that CALL+RET across basic block boundaries
// is converted to JMP (tail call) when CALL is the last
// instruction in a block that falls through to a RET-only block.

extern int bar(int x);
extern int baz(int x);

// Pattern A: if (cond) return bar(x); return 0;
// The CALL bar is in a conditional block that falls through to RET.
int test_pattern_a(int x) {
    if (x)
        return bar(x);
    return 0;
}

// Pattern B: if (cond) return 0; return bar(x);
// The CALL bar is in a fallthrough block before the RET block.
int test_pattern_b(int x) {
    if (x)
        return 0;
    return bar(x);
}

// Pattern C: if/else with two tail calls.
// Both branches call a function and return — both should be JMP.
int test_pattern_c(int x) {
    if (x)
        return bar(x);
    return baz(x);
}

int main(void) {
    int r = test_pattern_a(1);
    r += test_pattern_b(0);
    r += test_pattern_c(1);
    return r;
}
