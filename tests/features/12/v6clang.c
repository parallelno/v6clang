// Test case for O34: SELECT_CC Zero-Test ISel Gap
// SELECT_CC with i16 EQ/NE against zero should use MOV+ORA zero test,
// not LXI+SUB+SBB register-register comparison.

int select_second(int a, int b, int c) {
    if (a) return b;
    return c;
}

int select_on_zero(int x, int a, int b) {
    if (x == 0) return a;
    return b;
}

int select_nonzero(int x, int a, int b) {
    if (x != 0) return a;
    return b;
}

int main() {
    volatile int r;
    r = select_second(1, 10, 20);
    r = select_second(0, 10, 20);
    r = select_on_zero(0, 100, 200);
    r = select_on_zero(5, 100, 200);
    r = select_nonzero(0, 100, 200);
    r = select_nonzero(5, 100, 200);
    return 0;
}
