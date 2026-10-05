// O82 — MOV chain collapse and dead high-byte elimination.
//
// Pattern A: MVI r, imm is erased when r is provably dead after the
//   instruction.  Fires on the DstHi=0 store emitted by SRL16-by-8
//   whenever the high result byte is never consumed.
//
// Pattern B: MOV X, Y ; [safe instrs] ; MOV Z, X (X dead after)
//   → rewrite consumer to MOV Z, Y; erase producer if X then dead.
//   Fires when the SRL16-by-8 result register is immediately copied
//   into a call-argument register, creating a dead intermediate.
//
// Compile (baseline before implementing O82):
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\63\v6clang.c -o tests\features\63\v6clang_old.asm

__attribute__((leaf)) extern int  get_val(void);
__attribute__((leaf)) extern void use_byte(char b);
__attribute__((leaf)) extern void draw_stub(char x1, char y1);

// Pattern A isolated: only the high byte of a 16-bit lshr is consumed.
// SRL16-by-8 emits: MOV DstLo, SrcHi; MVI DstHi, 0.
// DstHi is never read again → Pattern A eliminates MVI DstHi, 0.
void test_dead_hi(void) {
    int r = get_val();
    use_byte((char)(r >> 8));
}

// Patterns A + B combined: SRL16-by-8 result fed via intermediate to a call.
//
// Before O82 the expansion produces:
//   MOV  E, H        ; SRL16 DstLo = SrcHi
//   MVI  D, 0        ; SRL16 DstHi = 0         ← DEAD  (Pattern A)
//   MOV  A, L        ; x1 argument
//   MOV  B, E        ; y1 argument  H→E→B chain ← Pattern B rewrites to MOV B, H
//   CALL draw_stub
//
// After O82:
//   MOV  A, L        ; x1 argument
//   MOV  B, H        ; y1 argument  (chain collapsed, producer E erased)
//   CALL draw_stub
//
// Net savings: 16cc, 3B.
void test_chain_and_dead_hi(void) {
    int r = get_val();
    draw_stub((char)r, (char)(r >> 8));
}

int main(void) {
    test_dead_hi();
    test_chain_and_dead_hi();
    return 0;
}
