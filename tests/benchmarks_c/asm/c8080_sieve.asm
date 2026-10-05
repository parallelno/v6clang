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
; 21 int main(int argc, char **argv) {
	ld (__a_2_main), hl
; 22     (void)argc; (void)argv;
; 23     u16 i, i_sq, k, count;
; 24
; 25     /* some compilers do not initialize properly */
; 26     {
; 27         u16 n;
; 28         for (n = 0; n < SIZE; n++) flags[n] = 0;
	ld hl, 0
	ld (main_n), hl
l_0:
	ld de, 57536
	add hl, de
	jp c, l_2
	ld de, flags
	ld hl, (main_n)
	add hl, de
	xor a
	ld (hl), a
	ld hl, (main_n)
	inc hl
	ld (main_n), hl
	jp l_0
l_2:
; 29     }
; 30
; 31     count = SIZE - 2;
	ld hl, 7998
	ld (main_count), hl
; 32
; 33     i_sq = 4;
	ld hl, 4
	ld (main_i_sq), hl
; 34     for (i = 2; i_sq < SIZE; ++i) {
	ld hl, 2
	ld (main_i), hl
l_3:
	ld hl, (main_i_sq)
	ld de, 57536
	add hl, de
	jp c, l_5
; 35         if (!flags[i]) {
	ld de, flags
	ld hl, (main_i)
	add hl, de
	ld a, (hl)
	or a
	jp nz, l_6
; 36             for (k = i_sq; k < SIZE; k = (u16)(k + i)) {
	ld hl, (main_i_sq)
	ld (main_k), hl
l_8:
	ld de, 57536
	add hl, de
	jp c, l_10
; 37                 if (!flags[k]) count = (u16)(count - 1);
	ld de, flags
	ld hl, (main_k)
	add hl, de
	ld a, (hl)
	or a
	jp nz, l_11
	ld hl, (main_count)
	dec hl
	ld (main_count), hl
l_11:
; 38                 flags[k] = 1;
	ld hl, (main_k)
	add hl, de
	ld (hl), 1
	ld hl, (main_k)
	ex hl, de
	ld hl, (main_i)
	add hl, de
	ld (main_k), hl
	jp l_8
l_10:
l_6:
; 39             }
; 40         }
; 41         i_sq = (u16)(i_sq + i + i + 1);  /* (n+1)^2 = n^2 + 2n + 1 */
	ld hl, (main_i_sq)
	ex hl, de
	ld hl, (main_i)
	add hl, de
	ex hl, de
	ld hl, (main_i)
	add hl, de
	inc hl
	ld (main_i_sq), hl
	ld hl, (main_i)
	inc hl
	ld (main_i), hl
	jp l_3
l_5:
; 42     }
; 43
; 44     bench_finish((u8)((u8)count ^ (u8)(count >> 8)));
	ld a, (main_count)
	ld hl, (main_count)
	ld d, h
	xor d
	call bench_finish
; 45     return 0;
	ld hl, 0
	ret
bench_finish:
; 42 void __global bench_finish(unsigned char checksum) {
	ld (__a_1_bench_finish), a
; 43     asm {

        out  (0xED), a
        halt

	ret
__bss:
flags:
	ds 8000
__static_stack:
	ds 15
__end:
__s___init equ __static_stack + 15
__s_main equ __static_stack + 1
__a_1_main equ __s_main + 10
__a_2_main equ __s_main + 12
main_n equ __s_main + 8
main_count equ __s_main + 6
main_i_sq equ __s_main + 2
main_i equ __s_main + 0
main_k equ __s_main + 4
__s_bench_finish equ __static_stack + 0
__a_1_bench_finish equ __s_bench_finish + 0
    savebin "C:\Work\Programming\v6clang\tests\benchmarks_c\build\c8080_sieve.com", __begin, __bss - __begin
