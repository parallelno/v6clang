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
; 23 int main(int argc, char **argv) {
	ld (__a_2_main), hl
; 24     (void)argc; (void)argv;
; 25
; 26     volatile u8 seed = N;
	ld a, 7
	ld (main_seed), a
; 27     u8 n = seed;
	ld (main_n), a
; 28     u8 i, k, r, flips, flips_max;
; 29     u8 perm0;
; 30
; 31     for (i = 0; i < n; i++) perm1[i] = i;
	xor a
	ld (main_i), a
l_0:
	ld hl, main_n
	cp (hl)
	jp nc, l_2
	ld de, perm1
	ld hl, (main_i)
	ld h, 0
	add hl, de
	ld (hl), a
	inc a
	ld (main_i), a
	jp l_0
l_2:
; 32     r = n;
	ld a, (main_n)
	ld (main_r), a
; 33     flips_max = 0;
	xor a
	ld (main_flips_max), a
; 34
; 35     for (;;) {
l_3:
; 36         while (r != 1) { count[r - 1] = r; r--; }
l_6:
	ld a, (main_r)
	cp 1
	jp z, l_7
	ld de, count
	ld hl, (main_r)
	ld h, 0
	dec hl
	add hl, de
	ld (hl), a
	dec a
	ld (main_r), a
	jp l_6
l_7:
; 37
; 38         for (i = 0; i < n; i++) perm[i] = perm1[i];
	xor a
	ld (main_i), a
l_8:
	ld hl, main_n
	cp (hl)
	jp nc, l_10
	ld de, perm1
	ld hl, (main_i)
	ld h, 0
	add hl, de
	ld a, (hl)
	ld de, perm
	ld hl, (main_i)
	ld h, 0
	add hl, de
	ld (hl), a
	ld a, (main_i)
	inc a
	ld (main_i), a
	jp l_8
l_10:
; 39         flips = 0;
	xor a
	ld (main_flips), a
; 40         while (perm[0] != 0) {
l_11:
	ld a, (perm)
	or a
	jp z, l_12
; 41             k = perm[0];
	ld (main_k), a
; 42             {
; 43                 u8 lo = 0;
	xor a
	ld (main_lo), a
; 44                 u8 hi = k;
	ld a, (main_k)
	ld (main_hi), a
; 45                 while (lo < hi) {
l_13:
	ld hl, main_hi
	ld a, (main_lo)
	cp (hl)
	jp nc, l_14
; 46                     u8 tmp = perm[lo];
	ld de, perm
	ld hl, (main_lo)
	ld h, 0
	add hl, de
	ld a, (hl)
	ld (main_tmp), a
; 47                     perm[lo] = perm[hi];
	ld hl, (main_hi)
	ld h, 0
	add hl, de
	ld a, (hl)
	ld hl, (main_lo)
	ld h, 0
	add hl, de
	ld (hl), a
; 48                     perm[hi] = tmp;
	ld hl, (main_hi)
	ld h, 0
	add hl, de
	ld a, (main_tmp)
	ld (hl), a
; 49                     lo++;
	ld a, (main_lo)
	inc a
	ld (main_lo), a
; 50                     hi--;
	ld a, (main_hi)
	dec a
	ld (main_hi), a
	jp l_13
l_14:
; 51                 }
; 52             }
; 53             flips++;
	ld a, (main_flips)
	inc a
	ld (main_flips), a
	jp l_11
l_12:
; 54         }
; 55         if (flips > flips_max) flips_max = flips;
	ld hl, main_flips
	ld a, (main_flips_max)
	cp (hl)
	jp nc, l_15
	ld a, (main_flips)
	ld (main_flips_max), a
l_15:
; 56
; 57         for (;;) {
l_17:
; 58             if (r == n) {
	ld hl, main_r
	ld a, (main_n)
	cp (hl)
	jp nz, l_20
; 59                 bench_finish(flips_max);
	ld a, (main_flips_max)
	call bench_finish
; 60                 return 0;
	ld hl, 0
	ret
l_20:
; 61             }
; 62             perm0 = perm1[0];
	ld a, (perm1)
	ld (main_perm0), a
; 63             for (i = 0; i < r; i++) perm1[i] = perm1[i + 1];
	xor a
	ld (main_i), a
l_22:
	ld hl, main_r
	cp (hl)
	jp nc, l_24
	ld de, perm1
	ld hl, (main_i)
	ld h, 0
	inc hl
	add hl, de
	ld a, (hl)
	ld hl, (main_i)
	ld h, 0
	add hl, de
	ld (hl), a
	ld a, (main_i)
	inc a
	ld (main_i), a
	jp l_22
l_24:
; 64             perm1[r] = perm0;
	ld de, perm1
	ld hl, (main_r)
	ld h, 0
	add hl, de
	ld a, (main_perm0)
	ld (hl), a
; 65             count[r] = (u8)(count[r] - 1);
	ld de, count
	ld hl, (main_r)
	ld h, 0
	add hl, de
	ld a, (hl)
	dec a
	ld hl, (main_r)
	ld h, 0
	add hl, de
	ld (hl), a
; 66             if (count[r] > 0) break;
	ld hl, (main_r)
	ld h, 0
	add hl, de
	ld a, (hl)
	or a
	jp nz, l_3
; 67             r++;
	ld a, (main_r)
	inc a
	ld (main_r), a
	jp l_17
bench_finish:
; 42 void __global bench_finish(unsigned char checksum) {
	ld (__a_1_bench_finish), a
; 43     asm {

        out  (0xED), a
        halt

	ret
__bss:
perm:
	ds 7
perm1:
	ds 7
count:
	ds 7
__static_stack:
	ds 16
__end:
__s___init equ __static_stack + 16
__s_main equ __static_stack + 1
__a_1_main equ __s_main + 11
__a_2_main equ __s_main + 13
main_seed equ __s_main + 0
main_n equ __s_main + 1
main_i equ __s_main + 2
main_r equ __s_main + 4
main_flips_max equ __s_main + 6
main_flips equ __s_main + 5
main_k equ __s_main + 3
main_lo equ __s_main + 8
main_hi equ __s_main + 9
main_tmp equ __s_main + 10
__s_bench_finish equ __static_stack + 0
__a_1_bench_finish equ __s_bench_finish + 0
main_perm0 equ __s_main + 7
    savebin "C:\Work\Programming\v6clang\tests\benchmarks_c\build\c8080_fannkuch.com", __begin, __bss - __begin
