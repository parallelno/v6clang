/* O17: Redundant Flag-Setting Elimination test case.
 *
 * These functions produce patterns where ALU operations set flags,
 * followed by ORA A that redundantly re-sets the same flags.
 *
 * The primary pattern: DCR A sets Z flag, so ORA A before Jcc is redundant.
 * Also tests 16-bit ALU+branch patterns for comparison.
 *
 * Savings: 4cc + 1 byte per eliminated ORA A.
 */

volatile unsigned char g_port;

/* Test 1: Countdown loop — DCR A sets Z, ORA A before JNZ is redundant */
void countdown(unsigned char n) {
    while (n != 0) {
        g_port = n;
        n--;
    }
}

/* Test 2: Count up loop — INR A sets Z (on overflow), tests flag tracking */
void countup(unsigned char start) {
    unsigned char i = start;
    while (i != 0) {
        g_port = i;
        i++;
    }
}

/* Test 3: 16-bit comparisons for reference */
int xor_test(int a, int b) {
    int r = a ^ b;
    if (r == 0)
        return 1;
    return 0;
}

int sub_test(int a, int b) {
    int r = a - b;
    if (r == 0)
        return 1;
    return 0;
}

int main(void) {
    countdown(5);
    countup(250);
    xor_test(5, 5);
    sub_test(10, 10);
    return 0;
}
