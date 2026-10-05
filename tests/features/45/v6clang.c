// Test case for O68 Phase 2 — `rotl i16 x, 1` via DAD H + ACI 0.
//
// Today the V6CLANG backend lowers `(x<<1)|(x>>15)` (the canonical
// `ISD::ROTL i16, 1` form) through the default Expand path: a
// 6-instruction shift-left chain plus a 7-step shift-right
// chain plus an OR-of-halves — ~17 B / ~100 cc per rotate.
//
// Phase 2 adds a Custom lowering that picks off rotl-by-1 and
// emits a 4-instruction sequence:
//
//     DAD  H            ; HL = HL+HL, CY = old MSB
//     MOV  A, L         ; A = new low byte (b0=0)
//     ACI  0            ; b0 |= CY  (carry-fold of MSB into LSB)
//     MOV  L, A         ; HL = rotated value
//
// 5 B / 36 cc / clobbers A. Saves ~12 B / ~64 cc per occurrence.
// The savings compound inside CRC-style inner loops.
//
// Compile baseline / new:
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\45\v6clang.c -o tests\features\45\v6clang_old.asm
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\45\v6clang.c -o tests\features\45\v6clang_new01.asm

typedef unsigned short u16;
typedef unsigned char  u8;

// ---- 1. Scalar rotl by 1 (the headline case). ----
u16 rotl_u16_1(u16 x) { return (u16)((x << 1) | (x >> 15)); }

// ---- 2. CRC-16-CCITT inner loop (8 rotates per byte). ----
u16 crc16_step(u16 crc, u8 byte) {
    crc ^= ((u16)byte) << 8;
    for (int i = 0; i < 8; ++i) {
        u16 hi = crc & 0x8000;
        crc = (u16)(crc << 1);
        if (hi) crc ^= 0x1021;
    }
    return crc;
}

// ---- 3. ROTL by 2 — sanity: must fall back to default Expand. ----
u16 rotl_u16_2(u16 x) { return (u16)((x << 2) | (x >> 14)); }

// ---- 4. Funnel-shift intrinsic (LLVM canonical form). ----
// __builtin_rotateleft16 is a clang builtin; no prototype needed.
u16 fshl_u16_1(u16 x) { return __builtin_rotateleft16(x, (u16)1); }

volatile u16 g_in  = 0x1234;
volatile u8  g_byte = 0x5A;
volatile u16 g_out;

int main(void) {
    g_out = rotl_u16_1(g_in);
    g_out = crc16_step(g_in, g_byte);
    g_out = rotl_u16_2(g_in);
    g_out = fshl_u16_1(g_in);
    return 0;
}
