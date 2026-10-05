/* O88: MVI-through-MOV collapse
 * Tests the peephole that folds:
 *   MVI X, imm
 *   MOV Z, X        (sole consumer, X dead after)
 * into:
 *   MVI Z, imm
 *
 * The canonical trigger is zext i8 -> i16 when the hi-half zero is
 * materialised via an intermediate register before V6CLANG_BUILD_PAIR.
 */
typedef unsigned char u8;
typedef unsigned short u16;
typedef signed char s8;

extern const s8 sin_lut[256];

/* lookup_zext: angle is zero-extended to u16 before pointer arithmetic.
 * Before O88: MVI L,0 / MOV H,L / MOV L,A  (24cc, 4B)
 * After  O88: MVI H,0 / MOV L,A            (16cc, 3B)
 */
s8 lookup_zext(u8 angle) {
    return sin_lut[angle];
}

/* zext_add: (u16)a + b where a is a u8.
 * The (u16)a zero-extension also triggers BUILD_PAIR with a zero hi half.
 * After O88 the zero MVI goes directly to the hi destination register.
 */
u16 zext_add(u8 a, u16 b) {
    return (u16)a + b;
}

int main(void) {
    volatile s8  r1 = lookup_zext(42);
    volatile u16 r2 = zext_add(10, 100);
    (void)r1; (void)r2;
    return 0;
}
