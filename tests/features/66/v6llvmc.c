// O81 feature test — SELECT_CC i8 through accumulator.
// Used for:
//   Baseline:   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S tests\features\66\v6clang.c -o tests\features\66\v6clang_old.asm
//   Post-O81:   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S tests\features\66\v6clang.c -o tests\features\66\v6clang_new01.asm
//
// The critical pattern is fillscreen():
//   - Outer loop counter (i8, 0..25) forces A to be claimed at outer-latch level.
//   - Inner loop: LDAX D, ANI 4, conditional select between 0 and 0x4F,
//     MOV M, result (dest in HL).
// BEFORE O81: select materialised in C → MVI C, 0 / MOV M, C (8cc+8cc=16cc false path).
// AFTER  O81: routes through A → XRA A / MOV M, A (4cc+8cc=12cc false path).

#include <stdint.h>

// ---------------------------------------------------------------------------
// PRIMARY test: fillscreen — double loop, HL=dst, DE=src, B=inner counter.
// Outer counter y (i8) lives across the inner loop and will consume A
// at the outer latch via CPI, so the allocator cannot give A to the
// inner select without O81.
// ---------------------------------------------------------------------------
void fillscreen(void) {
    uint8_t *src = (uint8_t *)(uintptr_t)0xF800u;
    uint8_t *dst = (uint8_t *)(uintptr_t)0x7802u;
    for (uint8_t y = 0; y < 25; y++) {
        for (uint8_t x = 0; x < 64; x++) {
            uint8_t b = *src++;
            *dst++ = (b & 4) ? (uint8_t)0x4F : (uint8_t)0x00;
        }
        dst += 15;
    }
}

// ---------------------------------------------------------------------------
// SECONDARY test: non-zero arms — both arms non-zero (no XRA A),
// but O81 still routes the result through A, freeing C.
// ---------------------------------------------------------------------------
void fillscreen_nonzero(void) {
    uint8_t *src = (uint8_t *)(uintptr_t)0xF800u;
    uint8_t *dst = (uint8_t *)(uintptr_t)0x7802u;
    for (uint8_t y = 0; y < 25; y++) {
        for (uint8_t x = 0; x < 64; x++) {
            uint8_t b = *src++;
            *dst++ = (b & 4) ? (uint8_t)0xFE : (uint8_t)0x01;
        }
        dst += 15;
    }
}

int main(void) {
    fillscreen();
    fillscreen_nonzero();
    return 0;
}
