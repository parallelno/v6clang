// Test case for O16: Post-RA Store-to-Load Forwarding
// c8080 reference version.

void use8(unsigned char x) {
    /* extern in v6clang version; stub here for c8080 */
}

unsigned char get8(void) {
    return 42;
}

void interleaved_add(unsigned char *dst, const unsigned char *src1,
                     const unsigned char *src2, unsigned char n) {
    unsigned char i;
    for (i = 0; i < n; i++) {
        dst[i] = src1[i] + src2[i];
    }
    use8(dst[0]);
}

unsigned char multi_live(unsigned char a, unsigned char b, unsigned char c) {
    unsigned char x = a + 1;
    unsigned char y = b + 2;
    use8(c);
    return x + y;
}

int main(int argc, char **argv) {
    unsigned char buf_dst[4];
    unsigned char buf_src1[4];
    unsigned char buf_src2[4];
    volatile unsigned char r;

    buf_dst[0] = 0; buf_dst[1] = 0; buf_dst[2] = 0; buf_dst[3] = 0;
    buf_src1[0] = 10; buf_src1[1] = 20; buf_src1[2] = 30; buf_src1[3] = 40;
    buf_src2[0] = 1; buf_src2[1] = 2; buf_src2[2] = 3; buf_src2[3] = 4;

    interleaved_add(buf_dst, buf_src1, buf_src2, 4);
    r = buf_dst[0];
    r = multi_live(1, 2, 3);

    return r;
}
