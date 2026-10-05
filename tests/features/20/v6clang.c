// Test case for O16: Post-RA Store-to-Load Forwarding
// Exercises spill/reload patterns where registers hold their spilled value
// at the reload point, enabling forwarding.

extern void use8(unsigned char x);
extern unsigned char get8(void);

// Case 1: Interleaved pointer loop — 4 ptrs + counter = high register pressure.
// The loop body has NO calls, so Avail is not cleared between spill and reload.
// The call to use8 at the end makes the function non-leaf, preventing static stack.
void interleaved_add(unsigned char *dst, const unsigned char *src1,
                     const unsigned char *src2, unsigned char n) {
    unsigned char i;
    for (i = 0; i < n; i++) {
        dst[i] = src1[i] + src2[i];
    }
    use8(dst[0]);
}

// Case 2: Multiple live values across a call — registers spilled, then reloaded
// (Calls clear Avail, so no forwarding expected here — serves as negative test)
unsigned char multi_live(unsigned char a, unsigned char b, unsigned char c) {
    unsigned char x = a + 1;
    unsigned char y = b + 2;
    use8(c);
    return x + y;
}

int main(void) {
    unsigned char buf_dst[4] = {0, 0, 0, 0};
    unsigned char buf_src1[4] = {10, 20, 30, 40};
    unsigned char buf_src2[4] = {1, 2, 3, 4};
    volatile unsigned char r;

    interleaved_add(buf_dst, buf_src1, buf_src2, 4);
    r = buf_dst[0];
    r = multi_live(1, 2, 3);

    return r;
}
