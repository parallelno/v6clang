// Test case for O35: Conditional Return Over RET (Jcc-over-RET → Rcc)
// When a conditional branch jumps over a fallthrough RET, replace
// Jcc + RET with a single inverted Rcc instruction.

extern int bar(int x);
extern int baz(int x);

// Pattern A: if (x == 0) return bar(y); return 0;
// The target block needs XCHG (move y from DE to HL) before JMP bar,
// so it's NOT a JMP-only block. O35 fires: JZ+RET → RNZ.
int test_two_arg_tailcall(int x, int y) {
    if (x == 0) return bar(y);
    return 0;
}

// Baseline: if (x == 0) return bar(0); return 0;
// Target block is JMP-only — O35 defers to threading (JZ bar / RET).
int test_cond_zero_tailcall(int x) {
    if (x == 0) return bar(0);
    return 0;
}

// Pattern B: Simple early return guard.
// Handled by foldConditionalReturns (O30), not O35.
int test_early_return(int x) {
    if (x) return bar(x);
    return 0;
}

int main() {
    volatile int r;
    r = test_two_arg_tailcall(0, 5);
    r = test_two_arg_tailcall(3, 5);
    r = test_cond_zero_tailcall(0);
    r = test_cond_zero_tailcall(5);
    r = test_early_return(3);
    r = test_early_return(0);
    return 0;
}
