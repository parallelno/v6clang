/* mul_bench.c - Measure cycle cost of i16 multiply.
 *
 * Loops over a fixed set of (a, b) pairs and accumulates an XOR
 * checksum of the low 16 bits of each product. The same workload
 * is built two ways (selected by -DUSE_INLINE_MUL=0|1):
 *
 *   USE_INLINE_MUL=1  -> include v6clang_arith.h, use __v6clang_mulhi3 (full inline)
 *   USE_INLINE_MUL=0  -> use the C `*` operator (clang emits CALL __mulhi3)
 *
 * Output: 2 bytes via OUT 0xED (checksum hi, checksum lo), then HLT.
 * v6emul prints cycle count on HALT.
 */

typedef unsigned short u16;
typedef unsigned char  u8;

#if USE_INLINE_MUL
#include "v6clang_arith.h"
#define MUL16(a, b) __v6clang_mulhi3((a), (b))
#else
#define MUL16(a, b) ((u16)((a) * (b)))
#endif

/* 16 (a,b) pairs covering: zero/one operands, low-bit-density, high-bit-
 * density, and worst-case (16 set bits in multiplier). */
static const u16 A_TAB[16] = {
    0x0000, 0x0001, 0x0002, 0x0003,
    0x000F, 0x0010, 0x00FF, 0x0100,
    0x1234, 0x4321, 0xAAAA, 0x5555,
    0x8000, 0xFFFF, 0x7FFF, 0xCAFE,
};
static const u16 B_TAB[16] = {
    0x0001, 0x0002, 0x1234, 0x00FF,
    0x0101, 0xFFFF, 0x0007, 0xABCD,
    0x5678, 0x1111, 0xFFFF, 0xFFFF,
    0x0002, 0xFFFF, 0xFFFF, 0xBABE,
};

static void out_port(u8 port, u8 v) {
    __builtin_v6clang_out(port, v);
}

int main(void) {
    u16 chk = 0;
    /* Outer loop: 64 iterations. Total = 64 * 16 = 1024 multiplies. */
    for (u8 i = 0; i < 64; ++i) {
        for (u8 j = 0; j < 16; ++j) {
            chk ^= MUL16(A_TAB[j], B_TAB[j]);
        }
        /* Vary inputs slightly each outer iter so optimizer can't const-fold. */
        chk += i;
    }
    out_port(0xED, (u8)(chk >> 8));
    out_port(0xED, (u8)(chk & 0xFF));
    __builtin_v6clang_hlt();
    __builtin_unreachable();
    return 0;
}
