// Test case for O36: Redundant LXI After Zero-Test Branch
// When a conditional branch/return proves HL==0 (via MOV A,H; ORA L; RNZ),
// the fallthrough path should not emit LXI HL, 0.

extern int bar(int x);
extern int baz(int x, int y);

// Pattern 1: if (x == 0) return bar(0); return x;
// After MOV A,H; ORA L; RNZ, the fallthrough has HL==0.
// LXI HL, 0 before JMP bar should be eliminated.
int test_cond_zero_tailcall(int x) {
    if (x == 0) return bar(0);
    return x;
}

// Pattern 2: if (x == 0) return bar(0); return 0;
// Similar but the non-zero path returns 0 instead of x.
int test_cond_zero_return_zero(int x) {
    if (x == 0) return bar(0);
    return 0;
}

// Pattern 3: if (x != 0) return x; return bar(0);
// After MOV A,H; ORA L; RZ (skip if zero), fallthrough is NZ path.
// NZ path does NOT prove HL==0, so no seeding should occur.
int test_nonzero_path(int x) {
    if (x != 0) return x;
    return bar(0);
}

int main() {
    volatile int r;
    r = test_cond_zero_tailcall(0);
    r = test_cond_zero_tailcall(5);
    r = test_cond_zero_return_zero(0);
    r = test_cond_zero_return_zero(5);
    r = test_nonzero_path(0);
    r = test_nonzero_path(5);
    return 0;
}
