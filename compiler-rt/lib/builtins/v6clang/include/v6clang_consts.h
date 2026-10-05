/*===---- v6clang_consts.h - V6CLANG target-specific hardware constants -----------===
 *
 * Hardware addresses, port numbers, and platform constants for the
 * V6CLANG bare-metal i8080 target.  All values are plain preprocessor
 * macros so they can be used in asm strings (via STR()), array
 * sizes, switch labels, and integer constant expressions.
 *
 *===----------------------------------------------------------------------===
 */

#ifndef __V6CLANG_V6CLANG_CONSTS_H
#define __V6CLANG_V6CLANG_CONSTS_H

#ifndef __V6CLANG__
#error "<v6clang_consts.h> is only valid for the V6CLANG target"
#endif

#include <stdint.h>

/* =======================================================
 * Ports
 * ======================================================= */
#define PORT0_OUT_OUT       0x88u
#define PORT0_OUT_IN        0x8Au

#define PORT_TIMER          0x08u
#define TIMER_INIT_CH0      0x36u
#define TIMER_INIT_CH1      0x76u
#define TIMER_INIT_CH2      0xB6u
#define TIMER_PORT_CH0      0x0Bu
#define TIMER_PORT_CH1      0x0Au
#define TIMER_PORT_CH2      0x09u

#define PORT_AY_REG         0x15u
#define PORT_AY_DATA        0x14u

/* =======================================================
 * Color
 * ======================================================= */
#define PALETTE_LEN             16u
#define PALETTE_UPD_REQ_NO      0u
#define PALETTE_UPD_REQ_YES     1u
#define BORDER_COLOR_IDX        1u

/* =======================================================
 * Screen Buffer
 * ======================================================= */
#define SCR_VERTICAL_OFFSET_DEFAULT 255u

#define SCR_BUFF0_ADDR_H    0x80u
#define SCR_BUFF1_ADDR_H    0xA0u
#define SCR_BUFF2_ADDR_H    0xC0u
#define SCR_BUFF3_ADDR_H    0xE0u
#define SCR_WIDTH           256u
#define SCR_HEIGHT          256u

#define SCR_ADDR            (SCR_BUFF0_ADDR_H << 8u)
#define SCR_ADDR_PTR        ((void*)(SCR_BUFF0_ADDR_H << 8u))
#define SCR_BUFF0_ADDR      SCR_ADDR
#define SCR_BUFF0_PTR       SCR_ADDR_PTR
#define SCR_BUFF1_ADDR      0xA000u
#define SCR_BUFF2_ADDR      0xC000u
#define SCR_BUFF3_ADDR      0xE000u
#define SCR_BUFF_LEN        0x2000u
#define SCR_BUFFS_LEN       (SCR_BUFF_LEN * 4u)
#define BACK_BUFF_ADDR      0xA000u
#define BACK_BUFF_LEN       (SCR_BUFF_LEN * 3u)
#define BACK_BUFF2_ADDR     0xA000u
#define BACK_BUFF2_LEN      (SCR_BUFF_LEN * 3u)
#define SCR_ADDR_MASK       0xE0u   /* %1110_0000 */


/* =======================================================
 * Sprite
 * ======================================================= */
#define SPRITE_X_SCR_ADDR           ((uint8_t)((SCR_BUFF1_ADDR) >> 8u))
#define SPRITE_SCR_BUFFS            3u
#define SPRITE_W16                  2u
#define SPRITE_W24                  3u
#define SPRITE_W8_PACKED            0u
#define SPRITE_W16_PACKED           1u
#define SPRITE_W24_PACKED           2u
#define SPRITE_W32_PACKED           3u

/* sprite preshift */
#define SPRITE_PRESHIFT_H_MAX       24u
#define SPRITES_PRESHIFTED_4        4u
#define SPRITES_PRESHIFTED_8        8u

/* sprite copy to scr */
#define SPRITE_COPY_TO_SCR_W_PACKED_MIN  SPRITE_W8_PACKED
#define SPRITE_COPY_TO_SCR_W_PACKED_MAX  SPRITE_W32_PACKED
#define SPRITE_COPY_TO_SCR_H_MIN         5u
#define SPRITE_COPY_TO_SCR_H_MAX         20u

/* sprite min */
#define SPRITE_W_PACKED_MIN         SPRITE_COPY_TO_SCR_W_PACKED_MIN
#define SPRITE_H_MIN                SPRITE_COPY_TO_SCR_H_MIN

/* =======================================================
 * RAM Disk
 * ======================================================= */
#define RAM_DISK0_PORT      0x10u
#define RAM_DISK1_PORT      0x11u
#define RAM_DISK2_PORT      0x20u
#define RAM_DISK3_PORT      0x21u
#define RAM_DISK4_PORT      0x40u
#define RAM_DISK5_PORT      0x41u
#define RAM_DISK6_PORT      0x80u
#define RAM_DISK7_PORT      0x81u

#define RAM_DISK_PORT       RAM_DISK1_PORT  /* working RAM Disk used by the game */

#define RAM_DISK_OFF_CMD    0u
#define RAM_DISK_S0         0x10u   /* %00010000 */
#define RAM_DISK_S1         0x14u   /* %00010100 */
#define RAM_DISK_S2         0x18u   /* %00011000 */
#define RAM_DISK_S3         0x1Cu   /* %00011100 */

#define RAM_DISK_M0         0x00u   /* %00000000 */
#define RAM_DISK_M1         0x01u   /* %00000001 */
#define RAM_DISK_M2         0x02u   /* %00000010 */
#define RAM_DISK_M3         0x03u   /* %00000011 */

#define RAM_DISK_M_89       0x40u   /* %01000000 */
#define RAM_DISK_M_AD       0x20u   /* %00100000 */
#define RAM_DISK_M_EF       0x80u   /* %10000000 */
#define RAM_DISK_M_8F       (RAM_DISK_M_89 | RAM_DISK_M_AD | RAM_DISK_M_EF)
#define RAM_DISK_M_AF       (RAM_DISK_M_AD | RAM_DISK_M_EF)

/* =======================================================
 * V6 Engine
 * ======================================================= */
#define RESTART_ADDR        0x0000u
#define INT_ADDR            0x0038u

#define MAIN_STACK_LEN      48u     /* used in the main program */
#define INT_STACK_LEN       30u     /* used in the interruption routine */
#define TMP_STACK_LEN       2u      /* temp 2-byte space in render routines (e.g. sprite_copy_to_scr_v) */

/* Defines available user space.
 * "-2" because erase funcs can let the interruption call corrupt 0x7FFE, 0x7FFF bytes. */
#define STACK_MAIN_PROGRAM_ADDR     (0x8000u - 2u)
/* Used by the interruption func. */
#define STACK_INTERRUPTION_ADDR     (STACK_MAIN_PROGRAM_ADDR - MAIN_STACK_LEN)
/* Temp 2-byte space used in render routines when mapping is enabled, SP points to data,
 * and BC is temporarily needed. */
#define STACK_TEMP_ADDR             (STACK_INTERRUPTION_ADDR - INT_STACK_LEN)
#define STACK_MIN_ADDR              (STACK_TEMP_ADDR - TMP_STACK_LEN)

#define BYTE_LEN            1u
#define WORD_LEN            2u
#define SAFE_WORD_LEN       2u      /* safety pair of bytes for reading by POP B */
#define ADDR_LEN            2u
#define JMP_4_LEN           4u

#define TEMP_BYTE           0u
#define TEMP_WORD           0u
#define TEMP_ADDR           0u
#define NULL_PTR            0u

#define INTS_PER_SEC        50u     /* interruptions per second */

/* settings */
#define SETTING_OFF         0u
#define SETTING_ON          0xFFu

/* temporal space before putting data into the RAM Disk */
#define LOADING_TEMP_ADDR   SCR_ADDR

/* text */
#define LINE_BREAK          0x6Au   /* '\n' */
#define PARAG_BREAK         0xFFu
#define EOD                 0u

/* =======================================================
 * V6 Debug
 * ======================================================= */
#define FPS_SCR_ADDR        (0xBDFBu - 16u)     /* FPS counter screen addr */

/* =======================================================
 * Op-codes
 * ======================================================= */
#define OPCODE_NOP          0x00u
#define OPCODE_XCHG         0xEBu
#define OPCODE_EI           0xFBu
#define OPCODE_RET          0xC9u
#define OPCODE_CALL         0xCDu
#define OPCODE_RC           0xD8u
#define OPCODE_RNC          0xD0u
#define OPCODE_JMP          0xC3u
#define OPCODE_JNZ          0xC2u
#define OPCODE_JC           0xDAu
#define OPCODE_JNC          0xD2u
#define OPCODE_MOV_E_M      0x5Eu
#define OPCODE_MOV_E_A      0x5Fu
#define OPCODE_MOV_D_B      0x50u
#define OPCODE_MOV_D_M      0x56u
#define OPCODE_MOV_D_A      0x57u
#define OPCODE_MOV_M_B      0x70u
#define OPCODE_MOV_M_A      0x77u
#define OPCODE_POP_B        0xC1u
#define OPCODE_STC          0x37u
#define OPCODE_INX_D        0x13u
#define OPCODE_LXI_B        0x01u
#define OPCODE_LXI_D        0x11u
#define OPCODE_LXI_H        0x21u
#define OPCODE_LXI_SP       0x31u
#define OPCODE_INR_L        0x2Cu
#define OPCODE_DCR_L        0x2Du

/* =======================================================
 * AY-3-8910 sound chip constants
 * ======================================================= */

/* registers */
#define AY_REG_TONE_FDIV_CHA_L  0u  /* LLLLLLLL — ch A tone freq divider low;  FDIV=HHHH*256+LLLLLLLL; frq=1.7734MHz/16/FDIV */
#define AY_REG_TONE_FDIV_CHA_H  1u  /* ----HHHH — ch A tone freq divider high */
#define AY_REG_TONE_FDIV_CHB_L  2u  /* LLLLLLLL — ch B tone freq divider low */
#define AY_REG_TONE_FDIV_CHB_H  3u  /* ----HHHH — ch B tone freq divider high */
#define AY_REG_TONE_FDIV_CHC_L  4u  /* LLLLLLLL — ch C tone freq divider low */
#define AY_REG_TONE_FDIV_CHC_H  5u  /* ----HHHH — ch C tone freq divider high */
#define AY_REG_NOISE_FDIV       6u  /* ---NNNNN — noise freq divider; frq=1.7734MHz/16/NNNNN */
#define AY_REG_MIXER            7u  /* --CBAcba — cba: mute tone channels; CBA: mute noise channels (1=muted) */
#define AY_REG_VOL_CHA          8u  /* ---EVVVV — E: envelope enable; VVVV: master volume */
#define AY_REG_VOL_CHB          9u  /* ---EVVVV */
#define AY_REG_VOL_CHC          10u /* ---EVVVV */
#define AY_REG_ENV_FDIV_L       11u /* LLLLLLLL — envelope period low */
#define AY_REG_ENV_FDIV_H       12u /* HHHHHHHH — envelope period high; FDIV=FDIV_H*256+FDIV_L */
#define AY_REG_ENV              13u /* ----EEEH — envelope type EEE, H=1 hold
                                     *   0: \_____________ single decay then off
                                     *   1: /|____________ single attack then off
                                     *   2: \|------------ single decay then hold
                                     *   3: /------------- single attack then hold
                                     *   4: \|\|\|\|\|\|\| repeated decay
                                     *   5: /|/|/|/|/|/|/| repeated attack
                                     *   6: /\/\/\/\/\/\/\ repeated attack-decay
                                     *   7: \/\/\/\/\/\/\/ repeated decay-attack */

/* mixer masks */
#define AY_REG_MIXER_T_MUTE_CHA 0x01u   /* mute tone  channel A */
#define AY_REG_MIXER_T_MUTE_CHB 0x02u   /* mute tone  channel B */
#define AY_REG_MIXER_T_MUTE_CHC 0x04u   /* mute tone  channel C */
#define AY_REG_MIXER_N_MUTE_CHA 0x08u   /* mute noise channel A */
#define AY_REG_MIXER_N_MUTE_CHB 0x10u   /* mute noise channel B */
#define AY_REG_MIXER_N_MUTE_CHC 0x20u   /* mute noise channel C */

/* master volume masks */
#define AY_REG_VOL_MASK         0x0Fu
#define AY_REG_VOL_ENV_MASK     0x10u

#endif /* __V6CLANG_V6CLANG_CONSTS_H */
