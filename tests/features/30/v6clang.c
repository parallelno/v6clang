// Test case for O48: Scavenger-Based Pseudo Expansion
// Tests that HL preservation is handled by the RA (Defs=[HL]) rather than
// per-expansion PUSH/POP logic (O42).
//
// copy_pair: Loads two i8 values through a pointer (LOAD8_P) and stores
// them through another pointer (STORE8_P). When addr is in BC, the
// fallback path borrows HL. Before O48, each expansion conditionally
// emits PUSH/POP HL. After O48, the RA keeps HL free.
//
// load16_via_ptr: Loads i16 through a pointer (LOAD16_P) with addr=BC.
// Same O42→O48 transition.
//
// load16_global: Loads i16 from a global (LOAD16_G) into BC/DE.
// Before O48: conditional PUSH/POP HL. After: RA handles HL.

__attribute__((leaf)) extern void use8(unsigned char x);
__attribute__((leaf)) extern void use16(unsigned int x);

void copy_pair(unsigned char *dst, const unsigned char *src) {
    unsigned char a = src[0];
    unsigned char b = src[1];
    dst[0] = a;
    dst[1] = b;
}

unsigned int load16_via_ptr(unsigned int *p) {
    return *p;
}

unsigned int g_val;

unsigned int load16_global(void) {
    return g_val;
}

// Exerciser that shows the pattern: multiple loads through pointer
// in a function with enough register pressure for HL conflict.
unsigned char sum_array(const unsigned char *arr, unsigned char n) {
    unsigned char sum = 0;
    unsigned char i;
    for (i = 0; i < n; i++) {
        sum += arr[i];
    }
    return sum;
}

int main(void) {
    unsigned char src[4] = {10, 20, 30, 40};
    unsigned char dst[4];
    copy_pair(dst, src);
    use8(dst[0]);
    use8(dst[1]);

    unsigned int val16 = 0x1234;
    unsigned int r16 = load16_via_ptr(&val16);
    use16(r16);

    g_val = 0xABCD;
    unsigned int r_g = load16_global();
    use16(r_g);

    unsigned char s = sum_array(src, 4);
    use8(s);

    return 0;
}
