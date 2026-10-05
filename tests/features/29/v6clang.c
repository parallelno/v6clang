// Test case for O43-fix: SHLD/LHLD→PUSH/POP Safety Guard
// v6clang version with leaf-attributed extern functions.
// Interleaved 3-pointer loop with high register pressure.
// The leaf attr enables static stack allocation (SHLD/LHLD/STA/LDA).
//
// Bug: Without the fix, O43 folds SHLD+LHLD (for __v6clang_ss+0) into
// PUSH+POP, removing the writeback to the static slot. The LHLD at
// the top of the loop reads stale data on subsequent iterations.
//
// Expected: After the fix, the SHLD for __v6clang_ss+0 is preserved
// (not folded to PUSH HL) because the LHLD at the loop top is an
// uncovered reader.

__attribute__((leaf)) extern void use8(unsigned char x);

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
