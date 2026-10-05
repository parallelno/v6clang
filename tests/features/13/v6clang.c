// Test case for O28: Branch Threading Through JMP-Only Blocks
// Conditional branch to a block containing only JMP should be
// redirected directly to the JMP's target (thread through).

extern int bar(int x);
extern int baz(int x);

// Pattern A: if (x == 0) return bar(0); return 0;
// The tail call block is JMP-only (HL already holds 0).
// Threading redirects Jcc directly to bar.
int test_cond_zero_tailcall(int x) {
    if (x == 0) return bar(0);
    return 0;
}

// Pattern B: Two conditions → same tail call block.
// First conditional branch gets threaded to bar.
int test_two_cond_tailcall(int x, int y) {
    if (x) return bar(x);
    if (y) return bar(x);
    return 0;
}

// Pattern C: Simple pass-through tail call (baseline - no threading).
int test_simple_tailcall(int x) {
    if (x) return bar(x);
    return 0;
}

int main() {
    volatile int r;
    r = test_cond_zero_tailcall(0);
    r = test_cond_zero_tailcall(5);
    r = test_two_cond_tailcall(1, 0);
    r = test_two_cond_tailcall(0, 1);
    r = test_two_cond_tailcall(0, 0);
    r = test_simple_tailcall(5);
    r = test_simple_tailcall(0);
    return 0;
}
