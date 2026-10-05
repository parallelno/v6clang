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
; 18 int main(int argc, char **argv) {
	ld (__a_2_main), hl
; 19     (void)argc; (void)argv;
; 20     /* Volatile seeds prevent the whole computation from collapsing to a
; 21      * constant under aggressive optimization (otherwise v6clang -O2
; 22      * folds the program to a single OUT). */
; 23     volatile u8 seed_a = 0;
	xor a
	ld (main_seed_a), a
; 24     volatile u8 seed_b = 1;
	ld a, 1
	ld (main_seed_b), a
; 25     u16 a = seed_a;
	ld hl, (main_seed_a)
	ld h, 0
	ld (main_a), hl
; 26     u16 b = seed_b;
	ld hl, (main_seed_b)
	ld h, 0
	ld (main_b), hl
; 27     u16 crc = 0xFFFF;
	ld hl, 65535
	ld (main_crc), hl
; 28     int i;
; 29
; 30     for (i = 0; i < 24; i++) {
	ld hl, 0
	ld (main_i), hl
l_0:
	ld de, 24
	call __o_sub_16
	jp p, l_2
; 31         u16 c = (u16)(a + b);
	ld hl, (main_a)
	ex hl, de
	ld hl, (main_b)
	add hl, de
	ld (main_c), hl
; 32         crc = crc_byte(crc, (u8)(c & 0xFF));
	ld hl, (main_crc)
	ld (__a_1_crc_byte), hl
	ld a, (main_c)
	and 255
	call crc_byte
	ld (main_crc), hl
; 33         crc = crc_byte(crc, (u8)((c >> 8) & 0xFF));
	ld (__a_1_crc_byte), hl
	ld hl, (main_c)
	ld a, h
	and 255
	call crc_byte
	ld (main_crc), hl
; 34         a = b;
	ld hl, (main_b)
	ld (main_a), hl
; 35         b = c;
	ld hl, (main_c)
	ld (main_b), hl
	ld hl, (main_i)
	inc hl
	ld (main_i), hl
	jp l_0
l_2:
; 36     }
; 37
; 38     bench_finish((u8)(crc & 0xFF));
	ld a, (main_crc)
	and 255
	call bench_finish
; 39     return 0;
	ld hl, 0
	ret
__o_sub_16:
; 265 void __o_sub_16() {
; 266     asm {

        ld   a, l
        sub  e
        ld   l, a
        ld   a, h
        sbc  d
        ld   h, a

	ret
crc_byte:
; 8 static u16 crc_byte(u16 crc, u8 b) {
	ld (__a_2_crc_byte), a
; 9     int k;
; 10     crc ^= (u16)b;
	ld hl, (__a_1_crc_byte)
	ex hl, de
	ld hl, (__a_2_crc_byte)
	ld h, 0
	call __o_xor_16
	ld (__a_1_crc_byte), hl
; 11     for (k = 0; k < 8; k++) {
	ld hl, 0
	ld (crc_byte_k), hl
l_3:
	ld de, 8
	call __o_sub_16
	jp p, l_5
; 12         if (crc & 1) crc = (u16)((crc >> 1) ^ CRC_POLY);
	ld hl, (__a_1_crc_byte)
	ld de, 1
	call __o_and_16
	ld a, h
	or l
	jp z, l_6
	ld hl, (__a_1_crc_byte)
	ld de, 1
	call __o_shr_u16
	ld de, 0
	push de
	push hl
	ld hl, 40961
	call __o_xor_32
	ld (__a_1_crc_byte), hl
	jp l_7
l_6:
; 13         else         crc = (u16)(crc >> 1);
	ld hl, (__a_1_crc_byte)
	ld de, 1
	call __o_shr_u16
	ld (__a_1_crc_byte), hl
l_7:
	ld hl, (crc_byte_k)
	inc hl
	ld (crc_byte_k), hl
	jp l_3
l_5:
; 14     }
; 15     return crc;
	ld hl, (__a_1_crc_byte)
	ret
bench_finish:
; 42 void __global bench_finish(unsigned char checksum) {
	ld (__a_1_bench_finish), a
; 43     asm {

        out  (0xED), a
        halt

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
__o_and_16:
; 280 void __o_and_16() {
; 281     asm {

        ld   a, h
        and  d
        ld   h, a
        ld   a, l
        and  e
        ld   l, a

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
__bss:
__static_stack:
	ds 21
__end:
__s___init equ __static_stack + 21
__s_main equ __static_stack + 5
__a_1_main equ __s_main + 12
__a_2_main equ __s_main + 14
main_seed_a equ __s_main + 0
main_seed_b equ __s_main + 1
main_a equ __s_main + 2
main_b equ __s_main + 4
main_crc equ __s_main + 6
main_i equ __s_main + 8
main_c equ __s_main + 10
__s_crc_byte equ __static_stack + 0
__a_1_crc_byte equ __s_crc_byte + 2
__a_2_crc_byte equ __s_crc_byte + 4
__s_bench_finish equ __static_stack + 0
__a_1_bench_finish equ __s_bench_finish + 0
__s___o_sub_16 equ __static_stack + 0
crc_byte_k equ __s_crc_byte + 0
__s___o_xor_16 equ __static_stack + 0
__s___o_and_16 equ __static_stack + 0
__s___o_shr_u16 equ __static_stack + 0
__s___o_xor_32 equ __static_stack + 0
    savebin "C:\Work\Programming\v6clang\tests\benchmarks_c\build\c8080_fib_crc.com", __begin, __bss - __begin
