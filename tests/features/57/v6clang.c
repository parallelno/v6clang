// O75 — flag-producing arithmetic SDNodes test cases.
// Each function should fold its trailing CPI 0 / ORA A into the
// flag set by the preceding arithmetic instruction, AND should not
// pin the value to A across the loop body.

typedef unsigned char u8;
typedef unsigned short u16;

// Loop counter — the canonical motivating case.
// Expected: DCR C; JNZ <body>  (no MOV A,C / DCR A / MOV C,A / CPI 0).
// Body must be opaque to LSR / LoopStrengthReduction so the counter
// is not closed-form-eliminated into a __mulhi3 call.
extern volatile u8 g_sink;
u16 dec_loop(u8 n) {
    u16 sum = 0;
    while (n) { g_sink = n; sum += n; --n; }
    return sum;
}

// Mask test — A is unavoidable for ANI, but trailing CPI 0 must go.
// Expected: MOV A,r; ANI 0x0F; JZ <true_lab>  (no CPI 0).
u8 mask_test(u8 x) {
    return (x & 0x0F) == 0 ? (u8)1 : (u8)0;
}

// XOR test — XRA r already sets Z. Store the result so
// (x ^ y) != 0 isn't folded back to (x != y).
// Expected: MOV A,x; XRA y; STA g_sink; JNZ <ne_lab>  (no CPI 0).
u8 xor_test(u8 x, u8 y) {
    u8 z = x ^ y;
    g_sink = z;
    return z != 0 ? (u8)1 : (u8)0;
}

// Subtract test — SUI imm already sets Z. Store the result so
// (x - 5) != 0 isn't folded back to (x != 5).
// Expected: MOV A,x; SUI 5; STA g_sink; JNZ <ne_lab>  (no CPI 0).
u8 sub_test(u8 x) {
    u8 z = x - 5;
    g_sink = z;
    return z != 0 ? (u8)1 : (u8)0;
}

// Counter that is also consumed AFTER the loop body — flags+value used.
// Expected: DCR C; JNZ <body>; …; ADD C  (counter not pinned to A,
// value of C still readable after loop).
u16 dec_loop_used(u8 n) {
    u16 sum = 0;
    while (n) { g_sink = n; sum += n; --n; }
    return sum + (u16)n;
}

volatile u8  g_n = 7;
volatile u8  g_x = 0x33;
volatile u8  g_y = 0x33;
volatile u16 g_out;
volatile u8  g_outb;
volatile u8  g_sink;

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    g_out  = dec_loop(g_n);
    g_outb = mask_test(g_x);
    g_outb = xor_test(g_x, g_y);
    g_outb = sub_test(g_x);
    g_out  = dec_loop_used(g_n);
    return 0;
}
