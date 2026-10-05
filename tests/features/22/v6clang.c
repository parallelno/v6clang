// ADD16 DAD-Based Expansion — O40 feature test
// Tests that 16-bit additions use DAD-based sequences instead of
// the 6-instruction byte chain when possible.
//
// Key patterns exercised:
// Path A: rp = ADD16(HL, rp) → DAD rp; MOV rp_hi,H; MOV rp_lo,L
// Path B: HL = ADD16(rp1, rp2) → MOV H,rp1_hi; MOV L,rp1_lo; DAD rp2

volatile int sink_val;
__attribute__((noinline)) void use_val(int x) { sink_val = x; }
__attribute__((noinline)) int get_val(void)    { return sink_val; }

// Mimics the nested_calls pattern from O10 test.
// After two get_val() calls:
//   a → saved in BC (get_val returns in HL, moved to BC)
//   b → returned in HL by second get_val()
// Then: c = a + b + n
//   Step 1: t = HL + BC → stored in BC (Path A: bc = hl + bc)
//   Step 2: c = BC + DE → stored in HL (Path B: hl = bc + de)
// Final: use_val(c) needs HL, return a+b needs HL from BC.
int nested_add(int n) {
    int a = get_val();
    int b = get_val();
    int c = a + b + n;
    use_val(c);
    return a + b;
}

int main(void) {
    int r = nested_add(5);
    return r;
}
