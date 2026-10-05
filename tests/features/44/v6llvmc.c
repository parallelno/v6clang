// Test case for O67 — i8 Rotate ISel via RLC/RRC.
//
// Constant-amount i8 rotates currently lower via the Expand path:
// (x<<n) | (x>>(8-n)) -> i8 SHL chain (good) ORed with i8 SRL via i16
// promotion (very bad: 7 insns per shift step). Result: ~50+ insns
// for a single `rotl(x, 1)`. With O67 each constant rotate becomes a
// chain of `RLC` / `RRC` (1 byte / 4 cycles each).
//
// Compile baseline / new:
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\44\v6clang.c -o tests\features\44\v6clang_old.asm
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\44\v6clang.c -o tests\features\44\v6clang_new01.asm

typedef unsigned char u8;

// Rotate by 1 — worst-case savings (~14× on size & speed).
u8 rotl1(u8 x) { return (u8)((x << 1) | (x >> 7)); }
u8 rotr1(u8 x) { return (u8)((x >> 1) | (x << 7)); }

// Rotate by 3 — multi-step chain of RLC/RRC.
u8 rotl3(u8 x) { return (u8)((x << 3) | (x >> 5)); }
u8 rotr3(u8 x) { return (u8)((x >> 3) | (x << 5)); }

// Rotate by 7 — exercises direction canonicalisation (7 left == 1 right).
u8 rotl7(u8 x) { return (u8)((x << 7) | (x >> 1)); }

// Rotate by 4 — symmetric tie (4 left == 4 right).
u8 rotl4(u8 x) { return (u8)((x << 4) | (x >> 4)); }

// Driver — c8080 needs a main() that calls every function so the
// compiled asm is comparable. Globals so the optimiser can't fold.
volatile u8 g_in = 0x5A;
volatile u8 g_out;

int main(void) {
    g_out = rotl1(g_in);
    g_out = rotr1(g_in);
    g_out = rotl3(g_in);
    g_out = rotr3(g_in);
    g_out = rotl7(g_in);
    g_out = rotl4(g_in);
    return 0;
}
