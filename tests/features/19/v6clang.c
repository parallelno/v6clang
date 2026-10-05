// Test case for O39: Interprocedural Register Allocation (IPRA) Integration
// Exercises live-across-call values that should stop spilling once CALL
// clobbers are driven by the call-preserved mask.

volatile int sink;

__attribute__((noinline))
void action_a(void) {
    sink = 1;
}

__attribute__((noinline))
void action_b(void) {
    sink = 2;
}

int test_ne_same_bytes(int x) {
    if (x != 0x4242) {
        action_a();
    }
    action_b();
    return x;
}

int test_eq_same_bytes(int x) {
    if (x == 0x4242) {
        action_a();
    }
    action_b();
    return x;
}

int main(void) {
    volatile int r;
    r = test_ne_same_bytes(0);
    r = test_ne_same_bytes(0x4242);
    r = test_eq_same_bytes(0);
    r = test_eq_same_bytes(0x4242);
    return sink + r;
}
