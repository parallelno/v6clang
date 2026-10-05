extern unsigned char bar(unsigned char x);

unsigned char test_two_cond_tailcall(unsigned char x, unsigned char y) {
    if (x) return bar(x);
    if (y) return bar(x);
    return 0;
}

unsigned char test_simple_zero_check(unsigned char val) {
    if (val) return 1;
    return 0;
}

unsigned char test_nz_branch(unsigned char a, unsigned char b) {
    if (a) return b;
    return 0;
}

int main(void) {
    volatile unsigned char r;
    r = test_two_cond_tailcall(0, 0);
    r = test_two_cond_tailcall(1, 0);
    r = test_two_cond_tailcall(0, 1);
    r = test_simple_zero_check(0);
    r = test_simple_zero_check(5);
    r = test_nz_branch(0, 10);
    r = test_nz_branch(3, 10);
    return 0;
}
