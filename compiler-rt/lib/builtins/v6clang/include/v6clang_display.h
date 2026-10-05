/**
 * @file v6clang_display.h
 * @brief Display primitives for the V6CLANG architecture.
 *
 * This module provides low-level display-related routines targeting the V6CLANG
 * 8-bit CPU.
 *
 * Functions:
 * - v6clang_set_palette()
 *
 *
 */

#ifndef DISPLAY_H
#define DISPLAY_H

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <v6clang_rt_macros.h>
#include "v6clang_consts.h"


static uint8_t __palette[PALETTE_LEN];


V6CLANG_NOINLINE_ASM
/**
 * @brief Set the hardware palette from palette data.
 * @param palette_end Pointer to a last byte of a 16-color palette in memory.
 * @param wait_for_vsync Whether to wait for vertical sync before updating the palette.
 */
void v6clang_set_palette(uint8_t* palette_end, bool wait_for_vsync)
{
    register uint16_t pal_reg asm("HL") = (uint16_t)palette_end;

    if (wait_for_vsync){
        v6clang_hlt();
    }

    __asm__ volatile (
            "mvi a, %[port]  \n"
            "out 0           \n"
            "mvi b, %[len]   \n"
         "1: mov a, b        \n"
			"out 2           \n"
			"mov a, m        \n"
			"out 0x0C        \n"
			"push psw        \n"
			"pop psw         \n"
			"push psw        \n"
			"pop psw         \n"
			"dcx h           \n"
			"dcr b           \n"
			"out 0x0C        \n"
			"jp	1b           \n"
            : /* no outputs */
            : "r"(pal_reg), [port] "i"(PORT0_OUT_OUT), [len] "i"(PALETTE_LEN-1)
            : "A", "B", "FLAGS"
    );
}

#endif /* DISPLAY_H */
