// O24: MVI+SUB/SBB Immediate Ordering Comparison — feature test
// Tests i16 ordering comparisons (< >= > <=) with immediate constants.
// Each function exercises one ordering condition with a 16-bit constant.

volatile unsigned int result;

void test_ult(unsigned int x) {
    if (x < 1000) result = 1;
}

void test_uge(unsigned int x) {
    if (x >= 1000) result = 2;
}

void test_ugt(unsigned int x) {
    if (x > 1000) result = 3;
}

void test_ule(unsigned int x) {
    if (x <= 1000) result = 4;
}

void test_slt(int x) {
    if (x < 500) result = 5;
}

void test_sge(int x) {
    if (x >= 500) result = 6;
}

int main(void) {
    test_ult(999);
    test_uge(1000);
    test_ugt(1001);
    test_ule(1000);
    test_slt(499);
    test_sge(500);
    return 0;
}
