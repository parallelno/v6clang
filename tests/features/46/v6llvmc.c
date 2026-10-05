// Feature test 46 — O55 Pattern 2: `MVI A, 0` -> `XRA A` (when FLAGS dead).
//
// Goal: drive the post-RA peephole that downgrades `MVI A, 0` to the
// 1-byte / 4-cycle `XRA A` whenever no live FLAGS use follows. We also
// include a negative case where FLAGS are live across the constant
// load -- the peephole must NOT fire there.
//
// Compile baseline / new:
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\46\v6clang.c -o tests\features\46\v6clang_old.asm
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\46\v6clang.c -o tests\features\46\v6clang_new01.asm

typedef unsigned char  u8;
typedef signed char    i8;
typedef unsigned short u16;

// ---- 1. Headline: trailing constant zero -- FLAGS dead before RET. ----
//
// Expected lowering today:   MVI A, 0 ; RET
// Expected after O55:        XRA A    ; RET
i8 const_zero(void) { return 0; }

// ---- 2. Multiple safe sites in a row through a side-effect call. ----
//
// After the call, A is reloaded with 0 and FLAGS are dead before the
// store -- another safe rewrite site.
volatile u8 g_sink;

void clear_sink_twice(void) {
    g_sink = 0;
    g_sink = 0;
}

// ---- 3. Negative case: SUB sets CY; JNC reads it. The MVI A, 0 sits
//        between them, so FLAGS are LIVE after the constant load and
//        the peephole must leave it alone. ----
//
// Expected lowering both today AND after O55:
//   ... SUB ... MVI A, 0 ... JNC ...
i8 neg_or_seven(i8 a, i8 b) {
    return (a - b) < 0 ? (i8)0 : (i8)7;
}

// ---- 4. Aggregate driver so c8080.c and v6clang.c are comparable. ----

volatile i8  g_a = -3;
volatile i8  g_b =  4;
volatile i8  g_out;

int main(void) {
    g_out = const_zero();
    clear_sink_twice();
    g_out = neg_or_seven(g_a, g_b);
    return 0;
}
