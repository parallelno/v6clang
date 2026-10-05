// Test case for O61 Stage 1: HL spill / HL reload via patched LXI.
//
// Each function holds a 16-bit value live across one or more calls to a
// leaf extern that the register allocator treats as clobbering HL. The
// allocator therefore spills the live value via SHLD __v6clang_ss.f+N and
// reloads via LHLD __v6clang_ss.f+N. Both source and destination of the
// spill/reload pair are HL — exactly the Stage 1 candidate shape.
//
// After Stage 1 (with -mllvm -mv6clang-spill-patched-reload), the LHLD
// becomes a patched LXI HL, 0 with a pre-instr label .Lo61_X, and the
// SHLD writes to .Lo61_X+1 (the LXI's imm bytes).

__attribute__((leaf)) extern unsigned int op1(unsigned int x);
__attribute__((leaf)) extern unsigned int op2(unsigned int x);

// Single HL spill, single HL reload (K = 1, the prototypical case).
unsigned int hl_one_spill(unsigned int x, unsigned int y) {
    unsigned int a = op1(x);
    unsigned int b = op2(y);   // clobbers HL → spill `a`
    return a + b;              // reload `a`
}

// Single HL spill, two HL reloads — exercises the unpatched-reload
// retarget path (LHLD reads from the patched site's imm bytes).
unsigned int hl_two_reloads(unsigned int x) {
    unsigned int a = op1(x);
    unsigned int b1 = op2(a);  // clobbers HL → spill `a`
    unsigned int b2 = op2(a);  // reload `a` again
    return b1 + b2;
}

unsigned int g1, g2;

int main(void) {
    g1 = hl_one_spill(0x1234, 0x5678);
    g2 = hl_two_reloads(0xabcd);
    return 0;
}
