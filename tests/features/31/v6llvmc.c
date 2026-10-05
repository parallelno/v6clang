// Test case for O60: Commutable ALU Operand Selection
//
// Demonstrates the shuffle pattern that arises when a commutative 8-bit
// ALU operation is selected with its operands placed in registers such
// that the LHS (A) and RHS (GR8) mapping forces extra MOVs.
//
// The compiler should pick, for each commutative op (+, &, |, ^),
// whichever operand ordering requires fewer copies.
//
// Layer 1 (isCommutable + TwoAddressInstructionPass): covers sum_xx.
// Layer 2 (ISel A-aligned LHS pref): covers cases where both live past op.
// Layer 3 (post-RA AccPlanning commute): covers spill-induced residuals.

__attribute__((leaf)) extern void use8(unsigned char x);
__attribute__((leaf)) extern void use16(unsigned int x);

// --- Layer 1 (primary) ---
// arg0=A, arg1=E. Pre-O60: MOV L,A; MOV A,E; ADD L; RET
// Post-O60:         ADD E; RET
unsigned char sum_add(unsigned char a, unsigned char b) {
    return a + b;
}
unsigned char sum_and(unsigned char a, unsigned char b) {
    return a & b;
}
unsigned char sum_or (unsigned char a, unsigned char b) {
    return a | b;
}
unsigned char sum_xor(unsigned char a, unsigned char b) {
    return a ^ b;
}

// --- Layer 2 (ISel pref) ---
// Both args must live past the ALU op so TwoAddressPass cannot commute.
// Side-effect via global sink keeps both a and b live without needing
// an extra function call from inside the test function.
volatile unsigned char g_sink8;
unsigned char both_live(unsigned char a, unsigned char b) {
    unsigned char s = a + b;
    g_sink8 = a;
    g_sink8 = b;
    return s;
}

// --- Layer 3 (post-RA commute) ---
// Enough register pressure to force a spill/reload around the ADD.
unsigned char spill_pressure(unsigned char a, unsigned char b,
                             unsigned char c, unsigned char d) {
    unsigned char t1 = c + d;
    g_sink8 = t1;
    return a + b;
}

unsigned char arr_sum(unsigned char* arr, unsigned char n) {
    unsigned char sum = 0;
    for (unsigned char i = 0; i < n; ++i) {
        sum += arr[i];
        unsigned char tmp2 = (int)(arr) >> 8;
        unsigned char tmp = tmp2 & 0xFF + n & arr[i-1];
    }
    return sum;
}

// --- 16-bit commute ---
// i16 add — one operand in HL, the other in DE. Commute should choose
// HL as LHS to avoid DE↔HL shuffle before V6CLANG_ADD16 expansion.
unsigned int sum16(unsigned int a, unsigned int b) {
    return a + b;
}

unsigned char* arr;

int main(void) {
    use8(sum_add(3, 4));
    use8(sum_and(0xF0, 0x0F));
    use8(sum_or (0x10, 0x20));
    use8(sum_xor(0xAA, 0x55));
    use8(both_live(7, 9));
    use8(spill_pressure(1, 2, 3, 4));
    use16(sum16(0x1234, 0x5678));
    use8(arr_sum(arr, 5));
    return 0;
}
