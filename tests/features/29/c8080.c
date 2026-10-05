// Test case for O43-fix: SHLD/LHLD→PUSH/POP Safety Guard
// c8080 reference version.
// Interleaved 3-pointer loop with high register pressure.
// c8080 uses static allocation natively — no stack spills.

void use8(unsigned char x) {
    /* extern in v6clang version; stub here for c8080 */
}

void interleaved_add(unsigned char *dst, const unsigned char *src1,
                     const unsigned char *src2, unsigned char n) {
    unsigned char i;
    for (i = 0; i < n; i++) {
        dst[i] = src1[i] + src2[i];
    }
    use8(dst[0]);
}

int main(int argc, char **argv) {
    unsigned char buf_dst[4];
    unsigned char buf_src1[4];
    unsigned char buf_src2[4];

    buf_src1[0] = 10; buf_src1[1] = 20; buf_src1[2] = 30; buf_src1[3] = 40;
    buf_src2[0] = 1;  buf_src2[1] = 2;  buf_src2[2] = 3;  buf_src2[3] = 4;

    interleaved_add(buf_dst, buf_src1, buf_src2, 4);

    return buf_dst[0];
}
