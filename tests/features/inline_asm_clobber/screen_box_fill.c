#include <stdint.h>

// screen consts
#define SCR_ADDR         0x8000
#define SCR_WIDTH        256
#define SCR_HEIGHT       256
#define SCR_BYTES_H      SCR_HEIGHT
#define SCR_BYTES_W      (SCR_WIDTH >> 3)

#define V6CLANG_RT static __attribute__((noinline, used))

V6CLANG_RT void reset_int() {
    __asm__ volatile (
        "mvi a, 0xC9 \n\t"
        "sta 0x38    \n\t"
    );
}

V6CLANG_RT void palette_init(uint8_t* palette)
{
    // PORT0_OUT_OUT = 0x88
    // PALETTE_LEN = 16
    register uint16_t hl_in asm("HL") = (uint16_t)palette;

    __asm__ volatile (
            "hlt              \n"

            "mvi	a, 0x88   \n"
            "out	0         \n"
            "mvi	b, 15     \n"
"loop:	     mov	a, b      \n"
			"out	2        \n"
			"mov a, m        \n"
			"out 0x0C        \n"
			"push psw        \n"
			"pop psw         \n"
			"push psw        \n"
			"pop psw         \n"
			"dcx h           \n"
			"dcr b           \n"
			"out 0x0C        \n"
			"jp	loop        \n"
            "RET              \n\t"
            :: "r"(hl_in) : "FLAGS"
    );
    return;
}


__attribute__((noinline)) static
void fill_screen() {
    for (uint16_t y = 0; y < SCR_HEIGHT; ++y) {
        for (uint8_t x = 0; x < SCR_BYTES_W; ++x) {
            uint8_t* scr_pos = (uint8_t*)(SCR_ADDR + (y * SCR_BYTES_W ) + x);
            *scr_pos = 0xFF; // set all pixels in this byte to on
        }
    }
}

__attribute__((noinline)) static
void fill_rect(uint8_t addr_x, uint8_t pos_y, uint8_t b, uint8_t h) {
    for (uint16_t x = addr_x; x < addr_x + b; ++x) {
        for (uint16_t y = pos_y; y < pos_y + h; ++y) {
            uint8_t* scr_pos = (uint8_t*)(SCR_ADDR + (x * SCR_BYTES_H ) + y);
            *scr_pos = 0xFF;
        }
    }
}

// Draws a rasterized text with 8x8 font. Each byte in `text` is an ASCII char,
// and the caller is responsible for ensuring that the text fits on screen at the
// given (x,y) position.
// addr_x is the horizontal byte address (0-31) where the text starts. Each byte
// corresponds to 8 pixels.
#define FONT_FIRST_CHAR  'A'
#define FONT_NUM_GLYPHS  26
#define FONT_GLYPH_BYTES 8

// 8x8 font, glyphs for ASCII 'A'..'Z' (26 glyphs, 208 bytes total).
// Row 0 is the top scanline; bit 7 is the leftmost pixel.
uint8_t font[FONT_NUM_GLYPHS * FONT_GLYPH_BYTES] = {
/*A*/0x00, 0x18, 0x24, 0x42, 0x7E, 0x42, 0x42, 0x00,
/*B*/0x00, 0x7C, 0x42, 0x7C, 0x42, 0x42, 0x7C, 0x00,
/*C*/0x00, 0x3C, 0x42, 0x40, 0x40, 0x42, 0x3C, 0x00,
/*D*/0x00, 0x78, 0x44, 0x42, 0x42, 0x44, 0x78, 0x00,
/*E*/0x00, 0x7E, 0x40, 0x7C, 0x40, 0x40, 0x7E, 0x00,
/*F*/0x00, 0x7E, 0x40, 0x7C, 0x40, 0x40, 0x40, 0x00,
/*G*/0x00, 0x3C, 0x42, 0x40, 0x4E, 0x42, 0x3C, 0x00,
/*H*/0x00, 0x42, 0x42, 0x7E, 0x42, 0x42, 0x42, 0x00,
/*I*/0x00, 0x3E, 0x08, 0x08, 0x08, 0x08, 0x3E, 0x00,
/*J*/0x00, 0x02, 0x02, 0x02, 0x02, 0x42, 0x3C, 0x00,
/*K*/0x00, 0x42, 0x44, 0x78, 0x44, 0x42, 0x42, 0x00,
/*L*/0x00, 0x40, 0x40, 0x40, 0x40, 0x40, 0x7E, 0x00,
/*M*/0x00, 0x42, 0x66, 0x5A, 0x42, 0x42, 0x42, 0x00,
/*N*/0x00, 0x42, 0x62, 0x52, 0x4A, 0x46, 0x42, 0x00,
/*O*/0x00, 0x3C, 0x42, 0x42, 0x42, 0x42, 0x3C, 0x00,
/*P*/0x00, 0x7C, 0x42, 0x42, 0x7C, 0x40, 0x40, 0x00,
/*Q*/0x00, 0x3C, 0x42, 0x42, 0x4A, 0x44, 0x3A, 0x00,
/*R*/0x00, 0x7C, 0x42, 0x42, 0x7C, 0x44, 0x42, 0x00,
/*S*/0x00, 0x3C, 0x42, 0x30, 0x0C, 0x42, 0x3C, 0x00,
/*T*/0x00, 0x7F, 0x08, 0x08, 0x08, 0x08, 0x08, 0x00,
/*U*/0x00, 0x42, 0x42, 0x42, 0x42, 0x42, 0x3C, 0x00,
/*V*/0x00, 0x42, 0x42, 0x42, 0x42, 0x24, 0x18, 0x00,
/*W*/0x00, 0x42, 0x42, 0x42, 0x5A, 0x66, 0x42, 0x00,
/*X*/0x00, 0x42, 0x24, 0x18, 0x18, 0x24, 0x42, 0x00,
/*Y*/0x00, 0x41, 0x22, 0x14, 0x08, 0x08, 0x08, 0x00,
/*Z*/0x00, 0x7E, 0x04, 0x08, 0x10, 0x20, 0x7E, 0x00,
};

V6CLANG_RT void draw_char(char c, uint8_t* scr_addr) {
    uint8_t* char_data = font + (uint16_t)(c - 'A') * 8;
    for (uint8_t i = 0; i < FONT_GLYPH_BYTES; ++i) {
        *scr_addr = *char_data;
        char_data += 1;
        scr_addr -= 1;
    }
}

V6CLANG_RT void draw_text(const char* text, uint8_t addr_x, uint8_t y) {
    char c;
    uint8_t* scr_addr = (uint8_t*)(SCR_ADDR + ((uint16_t)addr_x << 8) + y);
    while ((c = *text++) != 0)
    {
        draw_char(c, scr_addr);
        scr_addr += SCR_BYTES_H;
    };
}

uint8_t palette[16] = {
    0x00, 0x11, 0x22, 0x33,
    0x44, 0x55, 0x66, 0x77,
    0x88, 0x99, 0xAA, 0xBB,
    0xCC, 0xDD, 0xEE, 0xFF
};

void main(){

    __builtin_v6clang_ei();
    reset_int();
    palette_init(palette);

    //fill_screen();
    fill_rect(8, 50, 16, 156);
    draw_text("HELLOWORLD", 11, 10);
    // uint8_t* scr_pos = (uint8_t*)(SCR_ADDR + ((uint16_t)10 << 8) + 10);
    // draw_char('A', scr_pos);

    __builtin_v6clang_di();
    __builtin_v6clang_hlt();
}