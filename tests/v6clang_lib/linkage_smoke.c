/* O70 Step 3.13 — linkage smoke test.
 *
 * Exercises every operator the auto-included v6clang_arith.h replaces:
 *   - i8  *
 *   - i16 *  /  %  <<  >>  (logical and arithmetic)
 * Builds with default driver (auto-include + ld.lld --gc-sections).
 *
 * Build:
 *   llvm-build\bin\clang.exe --target=i8080-unknown-v6clang -O2 \
 *       linkage_smoke.c -o linkage_smoke.rom
 *
 * Expected: links cleanly (no undefined __mulqi3/__mulhi3/__udivhi3/...).
 *           Runtime XORs all results into one checksum byte.
 */

typedef unsigned char  u8;
typedef unsigned short u16;
typedef signed   short i16;

static void out_port(u8 port, u8 v) { __builtin_v6clang_out(port, v); }

int main(void) {
    /* volatile prevents constant folding so all libcalls survive. */
    volatile u8  va8 = 0x37, vb8 = 0x05;
    volatile u16 va  = 0x1234, vb = 0x0007;
    volatile i16 vsa = -0x0123, vsb = 0x0011;
    volatile u8  vn  = 4;

    u8  a8 = va8, b8 = vb8;
    u16 a  = va,  b  = vb;
    i16 sa = vsa, sb = vsb;
    u8  n  = vn;

    u8 r_mul8 = (u8)(a8 * b8);

    u16 r_mulu = (u16)(a * b);
    u16 r_divu = a / b;
    u16 r_modu = a % b;
    i16 r_divs = sa / sb;
    i16 r_mods = sa % sb;

    u16 r_shl = a << n;
    u16 r_lsr = a >> n;
    i16 r_asr = sa >> n;

    u8 chk = r_mul8;
    chk ^= (u8)(r_mulu);   chk ^= (u8)(r_mulu >> 8);
    chk ^= (u8)(r_divu);   chk ^= (u8)(r_divu >> 8);
    chk ^= (u8)(r_modu);   chk ^= (u8)(r_modu >> 8);
    chk ^= (u8)(r_divs);   chk ^= (u8)((u16)r_divs >> 8);
    chk ^= (u8)(r_mods);   chk ^= (u8)((u16)r_mods >> 8);
    chk ^= (u8)(r_shl);    chk ^= (u8)(r_shl >> 8);
    chk ^= (u8)(r_lsr);    chk ^= (u8)(r_lsr >> 8);
    chk ^= (u8)(r_asr);    chk ^= (u8)((u16)r_asr >> 8);

    out_port(0xED, chk);
    __builtin_v6clang_hlt();
    __builtin_unreachable();
    return 0;
}
