// Test case for O13: Load-Immediate Combining (Register Value Tracking)
// This test exercises patterns where MVI r, imm can be replaced with
// MOV r, r' (when another register holds the same value) or INR/DCR
// (when the register holds imm±1).

// Volatile to prevent optimization
volatile unsigned char sink8;
volatile unsigned int sink16;

void use8(unsigned char val) { sink8 = val; }
void use16(unsigned int val) { sink16 = val; }
unsigned char get8(void) { return sink8; }

// Test 1: Multiple zero-extensions — duplicate MVI 0 should be combined
void test_multi_zext(unsigned char a, unsigned char b) {
    unsigned int wide_a = a;   // zext: MVI high, 0
    unsigned int wide_b = b;   // zext: MVI high, 0 → MOV high, known_zero_reg
    use16(wide_a + wide_b);
}

// Test 2: Same immediate loaded into different registers
void test_same_imm(void) {
    use8(42);   // MVI r, 42
    use8(42);   // MVI r, 42 → can reuse if reg still holds 42
}

// Test 3: Sequential values — MVI N then MVI N+1 → INR
void test_sequential_values(void) {
    use8(10);   // MVI r, 10
    use8(11);   // MVI r, 11 → INR r
}

// Test 4: Value propagation through MOV
void test_mov_propagation(unsigned char a) {
    unsigned int w1 = a;   // zext: MVI zero_reg, 0
    use16(w1);
    unsigned int w2 = a;   // zext: should reuse zero from earlier
    use16(w2);
}

// Test 5: Main entry that calls all tests
int main(void) {
    test_multi_zext(5, 10);
    test_same_imm();
    test_sequential_values();
    test_mov_propagation(7);
    return 0;
}
