;* * * * *  Small-C/Plus z88dk * * * * *
;  Version: 23854-4d530b6eb7-20251002
;
;	Reconstructed for z80 Module Assembler
;
;	Module compile time: Tue Jun 02 18:56:51 2026


	C_LINE	0,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\bsort.c"

	MODULE	C__Work_Programming_v6clang_tests_benchmarks_c_src_bsort_c


	INCLUDE "z80_crt0.hdr"


	EXTERN	saved_hl
	C_LINE	0,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\bench.h"
	C_LINE	26,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\bench.h"
	C_LINE	27,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\bench.h"
	C_LINE	55,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\bench.h"
	SECTION	code_compiler

; Function bench_finish flags 0x00000200 __smallc
; void bench_finish(unsigned char checksum)
; parameter 'unsigned char checksum' at sp+2 size(1)
	C_LINE	55,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\bench.h::bench_finish::0::0"
._bench_finish
    pop  bc          ; ret addr -> BC
    pop  hl          ; checksum lo in L
    ld   a, l
    out  (0xED), a
    halt
	ret


	C_LINE	2,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\bsort.c::bench_finish::0::1"
	C_LINE	6,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\bsort.c::bench_finish::0::1"

; Function main flags 0x00000000 __stdc
; int main(int argc, char * * argv)
; parameter 'int argc' at 2 size(2)
; parameter 'char * * argv' at 4 size(2)
	C_LINE	6,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\bsort.c::main::0::2"
._main
	pop	bc
	pop	hl
	push	hl
	push	bc
	call	l_gint4sp	;
	ld	hl,65278	;const
	add	hl,sp
	ld	sp,hl
	ld	hl,2	;const
	add	hl,sp
	ld	(hl),0
	jp	i_4	;EOS
.i_2
	ld	hl,2	;const
	add	hl,sp
	inc	(hl)
.i_4
	ld	hl,2	;const
	add	hl,sp
	ld	a,(hl)
	sub	255
	jp	nc,i_3	;
	ld	hl,3	;const
	add	hl,sp
	ex	de,hl
	ld	hl,2	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	add	hl,de
	push	hl
	ld	hl,4	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	ld	de,31
	call	l_mult
	ld	bc,7
	add	hl,bc
	pop	de
	ld	a,l
	ld	(de),a
	jp	i_2	;EOS
.i_3
	ld	hl,2	;const
	add	hl,sp
	ld	(hl),254
	jp	i_7	;EOS
.i_5
	ld	hl,2	;const
	add	hl,sp
	dec	(hl)
.i_7
	ld	hl,2	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	ld	a,l
	and	a
	jp	z,ASMPC+4
	scf
	jp	nc,i_6	;
	ld	hl,1	;const
	add	hl,sp
	ld	(hl),0
	jp	i_10	;EOS
.i_8
	ld	hl,1	;const
	add	hl,sp
	inc	(hl)
.i_10
	pop	hl
	push	hl
	ld	e,h
	ld	d,0
	ld	hl,2	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	ld	a,e
	sub	l
	ld	a,d
	sbc	h
	jp	nc,i_9	;
	ld	hl,3	;const
	add	hl,sp
	push	hl
	dec	hl
	dec	hl
	ld	l,(hl)
	ld	h,0
	pop	de
	add	hl,de
	ld	l,(hl)
	ld	h,0
	push	hl
	ld	hl,5	;const
	add	hl,sp
	push	hl
	dec	hl
	dec	hl
	ld	l,(hl)
	ld	h,0
	inc	hl
	pop	de
	add	hl,de
	ld	l,(hl)
	ld	h,0
	pop	de
	ld	a,l
	sub	e
	ld	a,h
	sbc	d
	jp	nc,i_11	;
	ld	hl,0	;const
	add	hl,sp
	push	hl
	ld	hl,5	;const
	add	hl,sp
	push	hl
	dec	hl
	dec	hl
	ld	l,(hl)
	ld	h,0
	pop	de
	add	hl,de
	ld	a,(hl)
	pop	de
	ld	(de),a
	ld	hl,3	;const
	add	hl,sp
	push	hl
	dec	hl
	dec	hl
	ld	l,(hl)
	ld	h,0
	pop	de
	add	hl,de
	push	hl
	ld	hl,5	;const
	add	hl,sp
	push	hl
	dec	hl
	dec	hl
	ld	l,(hl)
	ld	h,0
	inc	hl
	pop	de
	add	hl,de
	ld	a,(hl)
	pop	de
	ld	(de),a
	ld	hl,3	;const
	add	hl,sp
	push	hl
	dec	hl
	dec	hl
	ld	l,(hl)
	ld	h,0
	inc	hl
	pop	de
	add	hl,de
	ex	de,hl
	ld	hl,0	;const
	add	hl,sp
	ld	a,(hl)
	ld	(de),a
	jp	i_8	;EOS
.i_6
	dec	sp
	pop	hl
	ld	l,0
	push	hl
	ld	hl,3	;const
	add	hl,sp
	ld	(hl),0
	jp	i_14	;EOS
.i_12
	ld	hl,3	;const
	add	hl,sp
	inc	(hl)
.i_14
	ld	hl,3	;const
	add	hl,sp
	ld	a,(hl)
	sub	255
	jp	nc,i_13	;
	ld	hl,0	;const
	add	hl,sp
	push	hl
	ld	l,(hl)
	ld	h,0
	push	hl
	ld	hl,8	;const
	add	hl,sp
	ex	de,hl
	ld	hl,7	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	add	hl,de
	ld	l,(hl)
	ld	h,0
	pop	de
	add	hl,de
	pop	de
	ld	a,l
	ld	(de),a
	jp	i_12	;EOS
.i_13
	pop	hl
	push	hl
	ld	h,0
	push	hl
	call	_bench_finish
	pop	bc
	ld	de,0
	ld	hl,259	;const
	add	hl,sp
	ld	sp,hl
	ex	de,hl
	ret


	SECTION	bss_compiler
	SECTION	code_compiler
; --- Start of Optimiser additions ---
	defc	i_11 = i_8
	defc	i_9 = i_5


; --- Start of Static Variables ---

	SECTION	bss_compiler
	SECTION	code_compiler


; --- Start of Scope Defns ---

	GLOBAL	_bench_finish
	GLOBAL	_main


; --- End of Scope Defns ---


; --- End of Compilation ---
