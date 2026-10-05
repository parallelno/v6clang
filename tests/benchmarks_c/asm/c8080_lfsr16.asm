    device zxspectrum48 ; There is no ZX Spectrum, it is needed for the sjasmplus assembler.
    org 100h
__begin:
__entry:
__init:
; 26 void __init() {
; 27     /* Zeroing uninitialized variables */
; 28     asm {

        ld   de, __bss
        xor  a
__init_loop:
        ld   (de), a
        inc  de
        ld   hl, 10000h - __end
        add  hl, de
        jp   nc, __init_loop

; 29         ld   de, __bss
; 30         xor  a
; 31 __init_loop:
; 32         ld   (de), a
; 33         inc  de
; 34         ld   hl, 10000h - __end
; 35         add  hl, de
; 36         jp   nc, __init_loop
; 37     }
; 38
; 39     /* Init stack */
; 40 #if __has_include(<c8080/initstack.inc>) && !defined(ARCH_CPM_CCP) && !defined(ARCH_CPM_BDOS) && !defined(ARCH_CPM_BIOS)
; 41 #include <c8080/initstack.inc>
; 42 #endif
; 43
; 44 #ifdef ARCH_CPM_CCP /* CCP remains in memory */
; 45     // clang-format off
; 46     asm {
; 47         pop  de
; 48         ld   a, (7)
; 49         sub  8
; 50         ld   h, a
; 51         ld   l, 0
; 52         ld   sp, hl
; 53         push de
; 54     }
; 55     // clang-format on
; 56 #endif
; 57
; 58 #ifdef ARCH_CPM_BDOS /* BDOS remains in memory */
; 59     asm {
; 60         ld   a, (7)
; 61         ld   h, a
; 62         ld   l, 0
; 63         ld   sp, hl
; 64         ld   hl, 0
; 65         push hl
; 66     }
; 67 #endif
; 68
; 69 #ifdef ARCH_CPM_BIOS /* BIOS remains in memory */
; 70 #error TODO
; 71 #endif
; 72
; 73     main(0, NULL);
	ld hl, 0
	ld (__a_1_main), hl
main:
; 20 int main(int argc, char **argv) {
	ld (__a_2_main), hl
; 21     (void)argc; (void)argv;
; 22
; 23     /* Volatile seed defeats constant-folding of the whole loop. */
; 24     volatile u16 init = 0xACE1;
	ld hl, 44257
	ld (main_init), hl
; 25     u16 lfsr = init;
	ld (main_lfsr), hl
; 26     u16 acc = 0;
	ld hl, 0
	ld (main_acc), hl
; 27     u16 i;
; 28
; 29     for (i = 0; i < ITERS; i++) {
	ld (main_i), hl
l_0:
	ld de, 61440
	add hl, de
	jp c, l_2
; 30         u8 lsb = (u8)(lfsr & 1);
	ld a, (main_lfsr)
	and 1
	ld (main_lsb), a
; 31         lfsr = (u16)(lfsr >> 1);
	ld hl, (main_lfsr)
	ld de, 1
	call __o_shr_u16
	ld (main_lfsr), hl
; 32         if (lsb) lfsr = (u16)(lfsr ^ 0xB400);
	ld a, (main_lsb)
	or a
	jp z, l_3
	ld de, 0
	push de
	push hl
	ld hl, 46080
	call __o_xor_32
	ld (main_lfsr), hl
l_3:
; 33         acc = (u16)(acc ^ lfsr);
	ld hl, (main_acc)
	ex hl, de
	ld hl, (main_lfsr)
	call __o_xor_16
	ld (main_acc), hl
	ld hl, (main_i)
	inc hl
	ld (main_i), hl
	jp l_0
l_2:
; 34     }
; 35
; 36     bench_finish((u8)((u8)acc ^ (u8)(acc >> 8)));
	ld a, (main_acc)
	ld hl, (main_acc)
	ld d, h
	xor d
	call bench_finish
; 37     return 0;
	ld hl, 0
	ret
__o_shr_u16:
; 521 void __o_shr_u16() {
; 522     asm {

        inc  e
__o_shr_u16__l1:
        dec  e
        ret  z
        ld   a, h
        or   a    ; cf = 0
        rra
        ld   h, a
        ld   a, l
        rra
        ld   l, a
        jp   __o_shr_u16__l1
1

	ret
__o_xor_32:
; 766 void __o_xor_32() {
; 767     asm {

        ld   bc, hl    ; bc = v1l
        pop  hl        ; hl = ret, stack = v2l
        ex   (sp), hl  ; hl = v2l, stack = ret
        ld   a, c
        xor  l
        ld   c, a
        ld   a, b
        xor  h
        ld   b, a      ; bc - result
        pop  hl        ; hl = ret, stack = v2h
        ex   (sp), hl  ; hl = v2h, stack = ret
        ld   a, e
        xor  l
        ld   e, a
        ld   a, d
        xor  h
        ld   d, a      ; de - result
        ld   hl, bc

	ret
__o_xor_16:
; 310 void __o_xor_16() {
; 311     asm {

        ld   a, h
        xor  d
        ld   h, a
        ld   a, l
        xor  e
        ld   l, a
        or   h         ; Flag Z used for compare

	ret
bench_finish:
; 42 void __global bench_finish(unsigned char checksum) {
	ld (__a_1_bench_finish), a
; 43     asm {

        out  (0xED), a
        halt

	ret
__bss:
__static_stack:
	ds 14
__end:
__s___init equ __static_stack + 14
__s_main equ __static_stack + 1
__a_1_main equ __s_main + 9
__a_2_main equ __s_main + 11
main_init equ __s_main + 0
main_lfsr equ __s_main + 2
main_acc equ __s_main + 4
main_i equ __s_main + 6
main_lsb equ __s_main + 8
__s_bench_finish equ __static_stack + 0
__a_1_bench_finish equ __s_bench_finish + 0
__s___o_shr_u16 equ __static_stack + 0
__s___o_xor_32 equ __static_stack + 0
__s___o_xor_16 equ __static_stack + 0
    savebin "C:\Work\Programming\v6clang\tests\benchmarks_c\build\c8080_lfsr16.com", __begin, __bss - __begin
