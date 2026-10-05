/**
 * @file v6clang_draw.h
 * @brief Drawing primitives for the V6CLANG architecture.
 *
 * This module provides low-level pixel and shape drawing routines targeting
 * the V6CLANG 8-bit CPU. All routines operate directly on a memory-mapped screen
 * buffer organized as a 1-bit-per-pixel planar framebuffer. Coordinates are
 * byte-addressed using a high-byte screen address (scr_addr_hi/h) combined
 * with X/Y pixel positions. Inner loops are implemented in inline assembly
 * for performance and precise register control.
 *
 * Functions:
 * - v6clang_set_palette()
 * - draw_pixel()
 * - draw_line()
 * - draw_circle()
 * - fill_rect()
 * - set_font()
 * - draw_text()
 *
 *
 */

#ifndef DRAW_H
#define DRAW_H

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <v6clang_rt_macros.h>
#include "v6clang_consts.h"



// bit mask for each bit position in a byte
static const uint8_t BIT_MASK[8] = {
    0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01};

V6CLANG_NOINLINE_ASM
/**
 * @brief Set a single pixel in the framebuffer.
 * @param x X coordinate.
 * @param y Y coordinate.
 * @param scr_addr_hi High byte of the screen address.
 */
void draw_pixel(uint8_t x, uint8_t y, uint8_t scr_addr_hi)
{
    register uint8_t _x asm("A") = x;
    register uint8_t _y asm("L") = y;
    register uint8_t _scr_addr_hi asm("H") = scr_addr_hi;
    asm (
        "MOV C, A           \n"
        "RRC                \n"
        "RRC                \n"
        "RRC                \n"
        "ANI 0x1F           \n" // a is byte offset within the plane (0-31)
        "ADD H              \n" // TODO: make it adjustable for different scr_addr_hi, self-modified code
        "MOV H, A           \n"
        "MVI A, 0x07        \n"
        "ANA C              \n" // a is bit offset within the byte (0-7)
        "LXI B, %[B_MASK]   \n"
        "ADD C              \n"
        "MOV C, A           \n"
        "ADC B              \n"
        "SUB C              \n"
        "MOV B, A           \n"
        "LDAX B             \n"
        "ORA M              \n"
        "MOV M, A           \n"
        : /* no outputs */
        /* input constraints */
        : "r" (_x), "r" (_y), "r" (_scr_addr_hi),
            [B_MASK] "i" (BIT_MASK)
        /* clobbered registers */
        : "A", "BC", "HL", "FLAGS"
    );
}

V6CLANG_NOINLINE_ASM
/**
 * @brief Draw a line between two points.
 * @param scr_addr_h High byte of the screen address.
 * @param x0 Start X coordinate.
 * @param y0 Start Y coordinate.
 * @param x1 End X coordinate.
 * @param y1 End Y coordinate.
 */
void draw_line(uint8_t scr_addr_h, uint8_t x0, uint8_t y0, uint8_t x1, uint8_t y1)
{
    register uint8_t _scr_addr_h asm("A") = scr_addr_h;
    register uint8_t _x0 asm("B") = x0;
    register uint8_t _y0 asm("C") = y0;
    register uint8_t _x1 asm("D") = x1;
    register uint8_t _y1 asm("E") = y1;

    asm(
        // A = scr_addr_h
        // B = x0
        // C = y0
        // D = x1
        // E = y1
        "STA .ADDR_H+1          \n"

        // calc+check dx
        "MOV A, D               \n"
        "SUB B                  \n"
        "JC .SWAP_POINTS        \n" // if x0 >= x1, SWAP_POINTS
    ".SET_DX:"
        "MOV D, A               \n" // D = dx

        // calc+check dy
        "LXI H, .ADV_Y          \n"
        "MOV A, E               \n" // A = y1
        "SUB C                  \n" // compare y0 with y1
        "JC .ADV_Y_NEG          \n" // if y0 >= y1, jump to .ADV_Y_NEG

        // --- x0 < x1, and y0 < y1 ---
    ".ADV_Y_POS:"
        // set up Y advance instruction (INR L)
        "MVI M, %[inr_l]        \n"
        "JMP .CHECK_SLOP        \n"
        // --- x0 < x1, and y0 >= y1 ---
    ".ADV_Y_NEG:"
        "CMA                    \n" // dy = -dy
        "INR A                  \n" // dy++
        "MVI M, %[dcr_l]        \n"

    ".CHECK_SLOP:"
        // D = |dx|
        // A = |dy|
        // if dy > dx, call vertical line drawing routine
        "CMP D                  \n" // compare dy with dx
        "JNC .VERTICAL_DRAW     \n" // if dy > dx, jump to vertical draw routine

        // .DY+1 = dy
        "STA .DY+1              \n"

        // --- left-to-right horizontal line ---
        // B = x0
        // C = y0
        // D = dx

        "call .SET_LOOP_VARS    \n"

        // --- loop ---
    ".LOOP_H:"
        // HL = byte address of the current pixel
        // C = err
        // D = dx
        // B = loop counter
        // E = bit mask

        // set pixel
        "MOV A, M          \n"
        "ORA E             \n"
        "MOV M, A          \n"

        // shift bit mask right for the next pixel
        "ANA E              \n" // A = bit mask
        "RRC                \n" // shift bit mask right for the next pixel
        "MOV E, A           \n" // save updated bit mask
        // if bit mask didn't cross byte boundary, skip addr_x increment
        "ADC H              \n"
        "SUB E              \n"
        "MOV H, A           \n"

        // err -= dy
        "MOV A, C           \n" // A = err
    ".DY:"
        "SUI 0              \n" // A = err - dy, self-modified code
        // advance y if err < 0
        "JNC .NO_ADV_Y      \n"
        "ADD D              \n" // A = err + dx
    ".ADV_Y:"
        "INR L              \n" // y++, self-modified code

    ".NO_ADV_Y:"
        "MOV C, A           \n" // C = err
        "DCR B              \n" // loop counter--
        "JNZ .LOOP_H        \n" // if loop counter != 0, repeat
        "RET                \n"

    // swap (x0, y0) with (x1, y1)
    ".SWAP_POINTS:"
        // in:
        // A = -dx
        // B = x0
        // C = y0
        // D = x1
        // E = y1
        // out: A = dx, swapped (x0, y0) with (x1, y1)
        "CMA                    \n"
        "INR A                  \n" // dx = -dx
        // swap
        "XCHG               \n"
        "MOV D, B           \n"
        "MOV E, C           \n"
        "MOV B, H           \n"
        "MOV C, L           \n"
        "JMP .SET_DX        \n"

    ".VERTICAL_DRAW:"
        // D = |dx|
        // A = |dy|
        // B = x0
        // C = y0

        "LXI H, .DX2+1      \n"
        "MOV M, D           \n" // .DX2 = dx
        "MOV D, A           \n"
        // D = dy

        // set up Y advance instruction for vertical draw routine
        "LDA .ADV_Y         \n"
        "STA .ADV_Y2        \n"

        // --- left-to-right vertical line ---
        // B = x0
        // C = y0
        // D = dy
        "call .SET_LOOP_VARS \n"

        // --- loop ---
    ".LOOP_V:"
        // HL = byte address of the current pixel
        // C = err
        // D = dy
        // B = loop counter
        // E = bit mask

        // set pixel
        "MOV A, M           \n"
        "ORA E              \n"
        "MOV M, A           \n"

        // advance y
    ".ADV_Y2:"
        "INR L              \n" // y++, self-modified code

        // err -= dx
        "MOV A, C           \n" // A = err
    ".DX2:"
        "SUI 0              \n" // A = err - dx, self-modified code
        "MOV C, A           \n" // C = err
        // if err < 0, advance x
    "JNC .NO_ADV_X2         \n"
        "ADD D              \n" // A = err + dy
        "MOV C, A           \n" // C = err

        // shift bit mask right for the next pixel
        "MOV A, E           \n" // A = bit mask
        "RRC                \n" // shift bit mask right for the next pixel
        "MOV E, A           \n" // save updated bit mask
        // if bit mask didn't cross byte boundary, skip addr_x increment
        "ADC H              \n"
        "SUB E              \n"
        "MOV H, A           \n"

    ".NO_ADV_X2:"
        "DCR B              \n" // loop counter--
        "JNZ .LOOP_V        \n" // if loop counter != 0, repeat
        "RET                \n"

    ".SET_LOOP_VARS:"
        // in: B = x0, C = y0
        // out:
        // HL = byte address of the current pixel
        // C = err
        // D = dx
        // B = loop counter
        // E = bit mask
        // clobbers: A, B, C, E, H, L, FLAGS

        // calc the bit mask for the current pixel
        "LXI H, %[B_MASK]  \n"
        "MVI A, 0x07       \n"
        "ANA B             \n" // A = bit offset within the byte (0-7)
        "ADD L             \n"
        "MOV L, A          \n"
        "ADC H             \n"
        "SUB L             \n"
        "MOV H, A          \n"
        "MOV E, M          \n"
        // E = bit mask

        // calc the byte address for the current pixel
        "MVI A, 0xF8       \n"
        "ANA B             \n" // A = byte offset within the scr buff (0-31)
        "RRC               \n"
        "RRC               \n"
        "RRC               \n"
    ".ADDR_H:"
        "ADI 0x80          \n" // scr_addr_hi, self-modified code
        "MOV H, A          \n"
        "MOV L, C          \n" // L = y0
        // HL = byte address of the current pixel

        // set up: err, loop counter
        // D is dx or dy depending on the slope, set up by the caller
        "MOV B, D           \n"
        "INR B              \n" // B = dx_or_dy + 1 (loop counter)
        "XRA A              \n"
        "ORA D              \n" // A = dx_or_dy, set CY = 0
        "RAR                \n" // err = dx_or_dy/2
        "MOV C, A           \n" // C = err
        "RET                \n"

        : /* no outputs */
        /* input constraints */
        : "r" (_scr_addr_h), "r" (_x0), "r" (_y0), "r" (_x1), "r" (_y1),
          [inr_l] "i" (OPCODE_INR_L), [dcr_l] "i" (OPCODE_DCR_L),
          [B_MASK] "i" (BIT_MASK)
        /* clobbered regs */
        : "A", "BC", "DE", "HL", "FLAGS"
    );
}

static inline uint8_t draw_scale_x_4_3(uint8_t value)
{
    return (value >> 1) + (value >> 2) + ((value & 0x03u) != 0);
}

/*
 * Jesko's method for drawing circles with only integer arithmetic and no multiplication/division.
 * Reference: https://en.wikipedia.org/wiki/Midpoint_circle_algorithm#cite_note-4
 * The Vector-06C display uses 4:3 pixels, so X offsets are compressed to 3/4
 * to keep the circle visually round on screen.
 * Note: this method is not perfectly accurate, and may produce slightly distorted
 * circles, especially for smaller radii.
*/
V6CLANG_NOINLINE
/**
 * @brief Draw a circle using an integer midpoint-style algorithm.
 * @param cx Circle center X coordinate.
 * @param cy Circle center Y coordinate.
 * @param r Circle radius.
 * @param scr_addr_hi High byte of the screen address.
 */
void draw_circle(uint8_t cx, uint8_t cy, uint8_t r, uint8_t scr_addr_hi)
{
    uint8_t x = r;
    uint8_t y = 0;
    uint8_t t1 = r >> 4;   // small bias trick (Jesko-style tweak)

    while (x >= y)
    {
        uint8_t sx = draw_scale_x_4_3(x);
        uint8_t sy = draw_scale_x_4_3(y);

        // 8-way symmetry
        draw_pixel(cx + sx, cy + y, scr_addr_hi);
        draw_pixel(cx - sx, cy + y, scr_addr_hi);
        draw_pixel(cx + sx, cy - y, scr_addr_hi);
        draw_pixel(cx - sx, cy - y, scr_addr_hi);
        draw_pixel(cx + sy, cy + x, scr_addr_hi);
        draw_pixel(cx - sy, cy + x, scr_addr_hi);
        draw_pixel(cx + sy, cy - x, scr_addr_hi);
        draw_pixel(cx - sy, cy - x, scr_addr_hi);

        y++;
        t1 += y;

        int t2 = t1 - x;
        if (t2 >= 0)
        {
            t1 = t2;
            x--;
        }
    }
}

// bit mask for each bit position in a byte
static const uint8_t REQ_BIT_MASK_L[8] = {
    0xFF, 0x7F, 0x3F, 0x1F, 0x0F, 0x07, 0x03, 0x01};
static const uint8_t REQ_BIT_MASK_R[8] = {
    0x80, 0xC0, 0xE0, 0xF0, 0xF8, 0xFC, 0xFE, 0xFF};

// Draw filled rectangle with bottom-left corner at (x, y) and specified width and height.
V6CLANG_NOINLINE
/**
 * @brief Fill a rectangle.
 * @param x Bottom-left X coordinate.
 * @param y Bottom-left Y coordinate.
 * @param width Rectangle width.
 * @param height Rectangle height.
 * @param scr_addr_hi High byte of the screen address.
 */
void fill_rect(uint8_t x, uint8_t y, uint8_t width, uint8_t height, uint8_t scr_addr_hi)
{
    // byte address of the bottom-left corner
    uint16_t addr_base = (scr_addr_hi << 8) + ((uint16_t)(x >> 3u) * SCR_HEIGHT) + y;
    uint8_t fill_bits_l = REQ_BIT_MASK_L[x & 0x07u];
    uint8_t fill_bits_r = REQ_BIT_MASK_R[(x + width - 1) & 0x07u];
    // total byte columns spanned: accounts for unaligned x start
    uint8_t total_cols = ((x & 0x07u) + width + 7u) >> 3u;

    if (total_cols == 1) {
        // rect fits within a single byte column
        memset((void*)addr_base, fill_bits_l & fill_bits_r, height);
        return;
    }

    // the first column
    memset((void*)addr_base, fill_bits_l, height);
    // the middle columns (if any)
    for (uint8_t i = 1; i < (uint8_t)(total_cols - 1); i++) {
        memset((void*)(addr_base + (uint16_t)i * SCR_HEIGHT), 0xFF, height);
    }
    // the last column
    memset((void*)(addr_base + (uint16_t)(total_cols - 1) * SCR_HEIGHT), fill_bits_r, height);
}


static const uint8_t __font[][8] ={
/* ' ' */0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
/* ! */ 0x08,0x00,0x08,0x08,0x08,0x08,0x08,0x08,
/* " */ 0x00,0x00,0x00,0x00,0x00,0x24,0x24,0x24,
/* # */ 0x00,0x24,0x24,0x7E,0x24,0x7E,0x24,0x24,
/* $ */ 0x08,0x3E,0x48,0x3C,0x12,0x7C,0x08,0x00,
/* % */ 0x62,0x64,0x08,0x10,0x26,0x46,0x00,0x00,
/* & */ 0x34,0x4A,0x44,0x38,0x44,0x4A,0x34,0x00,
/* ' */ 0x00,0x00,0x00,0x00,0x00,0x08,0x08,0x08,
/* ( */ 0x04,0x08,0x10,0x10,0x10,0x08,0x04,0x00,
/* ) */ 0x10,0x08,0x04,0x04,0x04,0x08,0x10,0x00,
/* * */ 0x00,0x08,0x2A,0x1C,0x2A,0x08,0x00,0x00,
/* + */ 0x00,0x08,0x08,0x3E,0x08,0x08,0x00,0x00,
/* , */ 0x10,0x08,0x08,0x00,0x00,0x00,0x00,0x00,
/* - */ 0x00,0x00,0x00,0x3E,0x00,0x00,0x00,0x00,
/* . */ 0x08,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
/* / */ 0x02,0x04,0x08,0x10,0x20,0x40,0x00,0x00,
/* 0 */ 0x3C,0x42,0x46,0x4A,0x52,0x62,0x42,0x3C,
/* 1 */ 0x3E,0x08,0x08,0x08,0x08,0x18,0x08,0x08,
/* 2 */ 0x7E,0x40,0x20,0x10,0x08,0x04,0x42,0x3C,
/* 3 */ 0x3C,0x42,0x02,0x1C,0x02,0x02,0x42,0x3C,
/* 4 */ 0x04,0x04,0x7E,0x44,0x24,0x14,0x0C,0x0C,
/* 5 */ 0x3C,0x42,0x02,0x02,0x7C,0x40,0x40,0x7E,
/* 6 */ 0x3C,0x42,0x42,0x7C,0x40,0x40,0x42,0x3C,
/* 7 */ 0x20,0x20,0x10,0x08,0x04,0x02,0x02,0x7E,
/* 8 */ 0x3C,0x42,0x42,0x3C,0x42,0x42,0x42,0x3C,
/* 9 */ 0x3C,0x42,0x02,0x02,0x3E,0x42,0x42,0x3C,
/* : */ 0x00,0x00,0x18,0x18,0x00,0x18,0x18,0x00,
/* ; */ 0x10,0x08,0x18,0x18,0x00,0x18,0x18,0x00,
/* < */ 0x04,0x08,0x10,0x20,0x10,0x08,0x04,0x00,
/* = */ 0x00,0x00,0x7E,0x00,0x7E,0x00,0x00,0x00,
/* > */ 0x10,0x08,0x04,0x02,0x04,0x08,0x10,0x00,
/* ? */ 0x08,0x00,0x08,0x04,0x02,0x21,0x21,0x1E,
/* @ */ 0x3C,0x40,0x5E,0x52,0x5E,0x42,0x42,0x3C,
/* A */ 0x42,0x42,0x7E,0x42,0x42,0x24,0x24,0x18,
/* B */ 0x7C,0x42,0x42,0x7C,0x42,0x42,0x42,0x7C,
/* C */ 0x3C,0x42,0x40,0x40,0x40,0x40,0x42,0x3C,
/* D */ 0x78,0x44,0x42,0x42,0x42,0x42,0x44,0x78,
/* E */ 0x7E,0x40,0x40,0x7C,0x40,0x40,0x40,0x7E,
/* F */ 0x40,0x40,0x40,0x7C,0x40,0x40,0x40,0x7E,
/* G */ 0x3C,0x42,0x46,0x42,0x40,0x40,0x42,0x3C,
/* H */ 0x42,0x42,0x42,0x7E,0x42,0x42,0x42,0x42,
/* I */ 0x3C,0x08,0x08,0x08,0x08,0x08,0x08,0x3C,
/* J */ 0x30,0x48,0x08,0x08,0x08,0x08,0x08,0x1E,
/* K */ 0x42,0x44,0x48,0x70,0x48,0x44,0x42,0x42,
/* L */ 0x7E,0x40,0x40,0x40,0x40,0x40,0x40,0x40,
/* M */ 0x42,0x42,0x42,0x42,0x5A,0x66,0x42,0x42,
/* N */ 0x42,0x42,0x46,0x4A,0x52,0x62,0x42,0x42,
/* O */ 0x3C,0x42,0x42,0x42,0x42,0x42,0x42,0x3C,
/* P */ 0x40,0x40,0x40,0x7C,0x42,0x42,0x42,0x7C,
/* Q */ 0x3A,0x44,0x4A,0x42,0x42,0x42,0x42,0x3C,
/* R */ 0x42,0x44,0x48,0x7C,0x42,0x42,0x42,0x7C,
/* S */ 0x3C,0x42,0x02,0x3C,0x40,0x42,0x42,0x3C,
/* T */ 0x08,0x08,0x08,0x08,0x08,0x08,0x08,0x7E,
/* U */ 0x3C,0x42,0x42,0x42,0x42,0x42,0x42,0x42,
/* V */ 0x18,0x24,0x24,0x42,0x42,0x42,0x42,0x42,
/* W */ 0x42,0x42,0x66,0x5A,0x42,0x42,0x42,0x42,
/* X */ 0x42,0x42,0x24,0x18,0x18,0x24,0x42,0x42,
/* Y */ 0x08,0x08,0x08,0x18,0x24,0x42,0x42,0x42,
/* Z */ 0x7E,0x40,0x20,0x10,0x08,0x04,0x02,0x7E,
};

static uint8_t* __font_ptr = __font;

V6CLANG_INLINE
/**
 * @brief Set the active font pointer.
 * @param new_font Pointer to an 8-byte-per-glyph font table.
 */
void set_font(uint8_t* new_font) {
    __font_ptr = new_font;
}

V6CLANG_NOINLINE
/**
 * @brief Draw text using the active font.
 * @param text Null-terminated string to render.
 * @param x Starting X coordinate.
 * @param y Starting Y coordinate.
 * @param scr_addr_hi High byte of the screen address.
 */
void draw_text(const char* text, uint8_t x, uint8_t y, uint8_t scr_addr_hi) {
    char c;
    uint16_t addr_base = (scr_addr_hi << 8) + (x >> 3u) * SCR_HEIGHT + y;
    uint8_t* font = __font_ptr;


    while ((c = *text)) {
        uint8_t* char_data = font + ((c - ' ') * 8); // each char is 8 bytes
        memcpy((void*)(addr_base), char_data, 8);
        // move to the next row for the next byte of the char
        addr_base += SCR_HEIGHT;
        ++text;
    }
}

#endif /* DRAW_H */
