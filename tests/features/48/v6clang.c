/* O69: Direct frame-index load/store pseudos.
 *
 * Goal: exercise stack-relative i8/i16 loads and stores that previously
 * lowered through V6CLANG_LEA_FI + V6CLANG_LOAD*_P/V6CLANG_STORE*_P address temporaries.
 *
 * Compile for assembly verification:
 *   llvm-build\bin\clang -target i8080-unknown-v6clang -O3 -S \
 *       tests\features\48\v6clang.c -o tests\features\48\v6clang_new01.asm \
 *       -mllvm -mv6clang-annotate-pseudos \
 *       -mllvm -v6clang-disable-alloca-promote \
 *       -mllvm -v6clang-disable-static-stack-alloc
 */

typedef unsigned char u8;

volatile u8 g8;
volatile int g16;

__attribute__((noinline))
u8 load8_stack_arg(u8 a0, u8 a1, u8 a2, u8 a3,
                   u8 a4, u8 a5, u8 a6, u8 a7) {
    return a7;
}

__attribute__((noinline))
int load16_stack_arg(int a0, int a1, int a2, int a3) {
    return a0 + a1 + a2 + a3;
}

__attribute__((noinline))
u8 store8_local(u8 x) {
    volatile u8 slot;
    slot = x;
    return slot;
}

__attribute__((noinline))
int store16_local(int x) {
    volatile int slot;
    slot = x;
    return slot;
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    g8 = load8_stack_arg(1, 2, 3, 4, 5, 6, 7, 8);
    g16 = load16_stack_arg(1, 2, 3, 4);
    g8 = store8_local(g8);
    g16 = store16_local(g16);
    __builtin_v6clang_out(0xED, g8);
    __builtin_v6clang_out(0xED, (unsigned char)g16);
    __builtin_v6clang_hlt();
    return 0;
}
