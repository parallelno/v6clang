// Test case for O65 — MOV r, M; OP r → OP M peephole fold (all 3 stages).
//
// Stage 1 — strict adjacency:
//   LXI   HL, <global byte>
//   MOV   L, M        ; load byte into L
//   XRA   L           ; A ^= L ; L dead          → XRA M
//
// Stage 2 — non-adjacent fold across independent MIs:
//   MOV   L, M        ; load byte into L
//   ...               ; independent MIs (no r / HL / A / FLAGS / store)
//   XRA   L                                       → ... ; XRA M
//
// Stage 3 — INR M / DCR M / MVI M, imm8:
//   MOV   A, M ; INR A ; MOV M, A                 → INR M
//   MOV   A, M ; DCR A ; MOV M, A                 → DCR M
//   MVI   A, imm ; MOV M, A                       → MVI M, imm
//
// Compile:
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\42\v6clang.c -o tests\features\42\v6clang_new01.asm

__attribute__((leaf)) extern unsigned char op(unsigned char x);
__attribute__((leaf)) extern void use1(unsigned char);
__attribute__((leaf)) extern void use2(unsigned char, unsigned char);

// Globals exercised by Stage 3 in-place updates.
unsigned char counter;
unsigned char flag;
unsigned char slot;

// ---- Stage 1 ---------------------------------------------------------------
// Drive the RA to place bytes in a static-stack / global slot, then
// read them back and fold them into A via XRA. Multiple sequential
// slot reads expose multiple MOV L, M; XRA L folds in one function.
unsigned char xor_bytes(unsigned char a, unsigned char b, unsigned char c,
                        unsigned char d, unsigned char e) {
    unsigned char x1 = op(a);
    unsigned char x2 = op(b);
    unsigned char x3 = op(c);
    unsigned char x4 = op(d);
    unsigned char x5 = op(e);
    use1(x1);
    return (unsigned char)(x1 ^ x2 ^ x3 ^ x4 ^ x5);
}

// AND / OR / ADD variants so all three non-XRA folds get exercised.
unsigned char and_bytes(unsigned char a, unsigned char b, unsigned char c) {
    unsigned char x1 = op(a);
    unsigned char x2 = op(b);
    unsigned char x3 = op(c);
    use1(x1);
    return (unsigned char)(x1 & x2 & x3);
}

unsigned char or_bytes(unsigned char a, unsigned char b, unsigned char c) {
    unsigned char x1 = op(a);
    unsigned char x2 = op(b);
    unsigned char x3 = op(c);
    use1(x1);
    return (unsigned char)(x1 | x2 | x3);
}

unsigned char add_bytes(unsigned char a, unsigned char b, unsigned char c) {
    unsigned char x1 = op(a);
    unsigned char x2 = op(b);
    unsigned char x3 = op(c);
    use1(x1);
    return (unsigned char)(x1 + x2 + x3);
}

// ---- Stage 2 ---------------------------------------------------------------
// Interleave an independent computation between the load of the spilled
// byte and its ALU consumer. Stage 1 cannot fold this (the MOV and OP
// are no longer adjacent), but Stage 2's scanBetweenSafe() walk should
// still prove the intervening MIs are independent of r / HL / A / FLAGS
// and collapse the pair.
unsigned char xor_with_passthrough(unsigned char a, unsigned char b,
                                   unsigned char c, unsigned char d) {
    unsigned char x1 = op(a);
    unsigned char x2 = op(b);
    unsigned char x3 = op(c);
    unsigned char x4 = op(d);
    // Forces (x1,x2) live across the next call; the subsequent reload of
    // x3/x4 then lands next to independent register-shuffling MIs.
    use2(x1, x2);
    return (unsigned char)((x1 ^ x2) ^ (x3 ^ x4));
}

// ---- Stage 3 ---------------------------------------------------------------
// Pointer-based access keeps HL live and forces clang to emit the
// MOV A, M; INR/DCR A; MOV M, A and MVI A, imm; MOV M, A triads that
// the Stage-3 peephole rewrites. Direct global access goes via LDA/STA
// or is already lowered to INR M by ISel, which would bypass the
// peephole entirely.
//
// Note: simple `(*p)++` shapes are already pattern-matched to INR M by
// ISel, so they verify the baseline path but do not exercise the
// peephole. The `volatile` and indexed shapes below are the ones that
// survive ISel as MOV/INR/MOV triads and depend on Stage 3.
void inc_via_ptr(unsigned char *p) { (*p)++; }
void dec_via_ptr(unsigned char *p) { (*p)--; }
void set_via_ptr(unsigned char *p) { *p = 0x42; }

// Volatile prevents the load+modify+store fusion at ISel time, so the
// MOV A, M; INR A; MOV M, A triad reaches post-RA intact. Stage 3 then
// recovers it as INR M / DCR M / MVI M.
void inc_volatile(volatile unsigned char *p) { (*p)++; }
void dec_volatile(volatile unsigned char *p) { (*p)--; }
void set_volatile(volatile unsigned char *p) { *p = 0x55; }

// Indexed in-place update: address is computed at runtime so ISel sees
// the load and store as separate operations.
void inc_indexed(unsigned char *p, unsigned char i) { p[i]++; }
void set_indexed(unsigned char *p, unsigned char i) { p[i] = 0x77; }

// Multiple Stage-3 folds in one function via the same pointer.
void init_buf(unsigned char *p) {
    p[0] = 0;
    p[1] = 1;
    p[2] = 0xFF;
}

// Negative-ish Stage 3 shape: A is consumed by the return after the
// store, so the `A dead after MOV M, A` guard suppresses the fold.
unsigned char inc_via_ptr_and_read(unsigned char *p) {
    (*p)++;
    return *p;
}

int main(int argc, char **argv) {
    xor_bytes(0x11, 0x22, 0x33, 0x44, 0x55);
    and_bytes(0xF0, 0x0F, 0xAA);
    or_bytes(0x01, 0x02, 0x04);
    add_bytes(0x10, 0x20, 0x30);
    xor_with_passthrough(0xA1, 0xB2, 0xC3, 0xD4);
    inc_via_ptr(&counter);
    dec_via_ptr(&counter);
    set_via_ptr(&flag);
    inc_volatile((volatile unsigned char *)&counter);
    dec_volatile((volatile unsigned char *)&counter);
    set_volatile((volatile unsigned char *)&flag);
    inc_indexed(&slot, 0);
    set_indexed(&slot, 1);
    init_buf(&slot);
    (void)inc_via_ptr_and_read(&counter);
    return 0;
}
