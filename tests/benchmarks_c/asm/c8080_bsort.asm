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
; 6 int main(int argc, char **argv) {
	ld (__a_2_main), hl
; 7     (void)argc; (void)argv;
; 8     u8 a[N];
; 9     u8 i, j, t;
; 10
; 11     /* Deterministic fill: 255 distinct bytes (gcd(31,256)=1). */
; 12     for (i = 0; i < N; i++) {
	xor a
	ld (main_i), a
l_0:
	cp 255
	jp nc, l_2
; 13         a[i] = (u8)(i * 31 + 7);
	ld de, main_a
	ld hl, (main_i)
	ld h, 0
	add hl, de
	ld d, a
	add a
	add d
	add a
	add d
	add a
	add d
	add a
	add d
	add 7
	ld (hl), a
	ld a, (main_i)
	inc a
	ld (main_i), a
	jp l_0
l_2:
; 14     }
; 15
; 16     for (i = (u8)(N - 1); i != 0; i--) {
	ld a, 254
	ld (main_i), a
l_3:
	or a
	jp z, l_5
; 17         for (j = 0; j < i; j++) {
	xor a
	ld (main_j), a
l_6:
	ld hl, main_i
	cp (hl)
	jp nc, l_8
; 18             if (a[j] > a[j + 1]) {
	ld de, main_a
	ld hl, (main_j)
	ld h, 0
	inc hl
	add hl, de
	ld a, (hl)
	ld hl, (main_j)
	ld h, 0
	add hl, de
	cp (hl)
	jp nc, l_9
; 19                 t = a[j];
	ld hl, (main_j)
	ld h, 0
	add hl, de
	ld a, (hl)
	ld (main_t), a
; 20                 a[j] = a[j + 1];
	ld hl, (main_j)
	ld h, 0
	inc hl
	add hl, de
	ld a, (hl)
	ld hl, (main_j)
	ld h, 0
	add hl, de
	ld (hl), a
; 21                 a[j + 1] = t;
	ld hl, (main_j)
	ld h, 0
	inc hl
	add hl, de
	ld a, (main_t)
	ld (hl), a
l_9:
	ld a, (main_j)
	inc a
	ld (main_j), a
	jp l_6
l_8:
	ld a, (main_i)
	dec a
	ld (hl), a
	jp l_3
l_5:
; 22             }
; 23         }
; 24     }
; 25
; 26     u8 sum = 0;
	xor a
	ld (main_sum), a
; 27     for (i = 0; i < N; i++) sum = (u8)(sum + a[i]);
	ld (main_i), a
l_11:
	cp 255
	jp nc, l_13
	ld de, main_a
	ld hl, (main_i)
	ld h, 0
	add hl, de
	ld a, (main_sum)
	add (hl)
	ld (main_sum), a
	ld a, (main_i)
	inc a
	ld (main_i), a
	jp l_11
l_13:
; 28
; 29     bench_finish(sum);
	ld a, (main_sum)
	call bench_finish
; 30     return 0;
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
__static_stack:
	ds 264
__end:
__s___init equ __static_stack + 264
__s_main equ __static_stack + 1
__a_1_main equ __s_main + 259
__a_2_main equ __s_main + 261
main_i equ __s_main + 255
main_a equ __s_main + 0
main_j equ __s_main + 256
main_t equ __s_main + 257
main_sum equ __s_main + 258
__s_bench_finish equ __static_stack + 0
__a_1_bench_finish equ __s_bench_finish + 0
    savebin "C:\Work\Programming\v6clang\tests\benchmarks_c\build\c8080_bsort.com", __begin, __bss - __begin
