/* v6clang_math.h - V6CLANG 16-bit integer trigonometry.
 *
 * Provides sin8() and cos8(): degree in / signed 16-bit out
 * lookup-table approximations of sine and cosine.
 *
 * Angle convention
 * ----------------
 * The input angle is given in whole degrees.  Any signed value is
 * accepted and normalised modulo 360:
 *
 *     0° →   0   (sin = 0)
 *    90° →  90   (sin = +256, max)
 *   180° → 180   (sin = 0)
 *   270° → 270   (sin = -256, min)
 *
 * Return value
 * ------------
 * The result is the sine scaled by 256 (Q8 fixed point):
 *   sin8(deg) ≈ round(256.0 * sin(deg * π/180))   in [-256, +256]
 *   cos8(deg) ≈ round(256.0 * cos(deg * π/180))   in [-256, +256]
 *
 * cos8(deg) == sin8(deg + 90)   (90° phase shift)
 *
 * Implementation
 * --------------
 * A single 91-entry quarter-wave table (0°..90°) of 16-bit values
 * (0..256) is stored.  The full circle is reconstructed by folding
 * the normalised angle into the first quadrant and negating the
 * result in the lower half-plane.  The quarter-wave lookup itself is
 * done in i8080 assembly: the angle indexes a word table, so it is
 * doubled (DAD H) before being added to the table base.
 *
 * Linkage
 * -------
 * Both functions and the lookup table are static (per-TU). Unused
 * copies are pruned by the linker's --gc-sections pass.
 */

#ifndef V6CLANG_MATH_H
#define V6CLANG_MATH_H

#include <stdint.h>
#include <v6clang_rt_macros.h>

/* ------------------------------------------------------------------
 * Quarter-wave sine lookup table.
 *
 * sin_q_lut[d] = round(256.0 * sin(d * M_PI / 180.0))   for d = 0..90
 *
 * Values run from 0x0000 (sin 0°) to 0x0100 = 256 (sin 90°).  The
 * table is indexed by whole degrees; since each entry is a 16-bit
 * word, the degree index is doubled before being added to the base.
 * ------------------------------------------------------------------ */
static const uint16_t sin_q_lut[91] = {
    /*  0 ..  8 */ 0x0000, 0x0004, 0x0009, 0x000D, 0x0012, 0x0016, 0x001B, 0x001F, 0x0024,
    /*  9 .. 17 */ 0x0028, 0x002C, 0x0031, 0x0035, 0x003A, 0x003E, 0x0042, 0x0047, 0x004B,
    /* 18 .. 26 */ 0x004F, 0x0053, 0x0058, 0x005C, 0x0060, 0x0064, 0x0068, 0x006C, 0x0070,
    /* 27 .. 35 */ 0x0074, 0x0078, 0x007C, 0x0080, 0x0084, 0x0088, 0x008B, 0x008F, 0x0093,
    /* 36 .. 44 */ 0x0096, 0x009A, 0x009E, 0x00A1, 0x00A5, 0x00A8, 0x00AB, 0x00AF, 0x00B2,
    /* 45 .. 53 */ 0x00B5, 0x00B8, 0x00BB, 0x00BE, 0x00C1, 0x00C4, 0x00C7, 0x00CA, 0x00CC,
    /* 54 .. 62 */ 0x00CF, 0x00D2, 0x00D4, 0x00D7, 0x00D9, 0x00DB, 0x00DE, 0x00E0, 0x00E2,
    /* 63 .. 71 */ 0x00E4, 0x00E6, 0x00E8, 0x00EA, 0x00EC, 0x00ED, 0x00EF, 0x00F1, 0x00F2,
    /* 72 .. 80 */ 0x00F3, 0x00F5, 0x00F6, 0x00F7, 0x00F8, 0x00F9, 0x00FA, 0x00FB, 0x00FC,
    /* 81 .. 89 */ 0x00FD, 0x00FE, 0x00FE, 0x00FF, 0x00FF, 0x00FF, 0x0100, 0x0100, 0x0100,
    /* 90       */ 0x0100,
};

/* ------------------------------------------------------------------
 * sin_quarter — first-quadrant lookup (i8080 port of the Z80 core).
 *
 * Input:  deg in 0..90.  Output: sin_q_lut[deg] in [0, 256].
 *
 * Z80 original (word table, returns HL):
 *   LD H,0 / LD L,A / LD DE,table / ADD HL,DE
 *   LD A,(HL) / INC HL / LD H,(HL) / LD L,A / RET
 *
 * i8080 port: HL already holds the degree on entry (H = 0 because the
 * input is 0..90), so the byte offset is formed with DAD H (×2).
 * ------------------------------------------------------------------ */
V6CLANG_INLINE
uint16_t sin_quarter(uint8_t deg)
{
    register uint16_t _hl asm("HL") = deg;   /* H = 0, L = deg            */
    asm (
        "DAD  H         \n"   /* HL = deg * 2  (word offset)              */
        "LXI  D, %[tbl] \n"   /* DE = table base                          */
        "DAD  D         \n"   /* HL = &sin_q_lut[deg]                     */
        "MOV  A, M      \n"   /* A  = low byte                            */
        "INX  H         \n"
        "MOV  H, M      \n"   /* H  = high byte                           */
        "MOV  L, A      \n"   /* HL = sin_q_lut[deg]                      */
        : "+r" (_hl)
        : [tbl] "i" (sin_q_lut)
        : "A", "DE", "FLAGS"
    );
    return _hl;
}

/* ------------------------------------------------------------------
 * sin8 — integer sine approximation (Q8, scaled by 256).
 *
 * Input:  angle  — angle in whole degrees (any signed value).
 * Output: int16_t in [-256, 256] ≈ round(256 * sin(angle * π/180)).
 *
 * The angle is normalised to 0..359 and folded into the first
 * quadrant; the result is negated for angles in [180, 360).
 * ------------------------------------------------------------------ */
V6CLANG_NOINLINE
int16_t sin8(int16_t angle)
{
    int16_t r = (int16_t)(angle % 360);
    if (r < 0)
        r += 360;
    uint16_t a = (uint16_t)r;            /* a in 0..359                  */

    uint8_t  idx;
    uint8_t  neg;
    if (a < 90)        { idx = (uint8_t)a;          neg = 0; }
    else if (a < 180)  { idx = (uint8_t)(180 - a);  neg = 0; }
    else if (a < 270)  { idx = (uint8_t)(a - 180);  neg = 1; }
    else               { idx = (uint8_t)(360 - a);  neg = 1; }

    int16_t v = (int16_t)sin_quarter(idx);
    return neg ? (int16_t)(-v) : v;
}

/* ------------------------------------------------------------------
 * cos8 — integer cosine approximation (Q8, scaled by 256).
 *
 * Input:  angle  — angle in whole degrees (same as sin8).
 * Output: int16_t in [-256, 256] ≈ round(256 * cos(angle * π/180)).
 *
 * Implemented as sin8(angle + 90), since cos(x) = sin(x + 90°).
 * ------------------------------------------------------------------ */
V6CLANG_INLINE
int16_t cos8(int16_t angle)
{
    return sin8((int16_t)(angle + 90));
}

#undef V6CLANG_NOINLINE_ASM

#endif /* V6CLANG_MATH_H */
