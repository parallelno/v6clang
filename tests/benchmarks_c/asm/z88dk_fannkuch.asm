;* * * * *  Small-C/Plus z88dk * * * * *
;  Version: 23854-4d530b6eb7-20251002
;
;	Reconstructed for z80 Module Assembler
;
;	Module compile time: Tue Jun 02 18:56:57 2026


	C_LINE	0,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\fannkuch.c"

	MODULE	C__Work_Programming_v6clang_tests_benchmarks_c_src_fannkuch_c


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


	C_LINE	13,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\fannkuch.c::bench_finish::0::1"
	C_LINE	19,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\fannkuch.c::bench_finish::0::1"
	C_LINE	20,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\fannkuch.c::bench_finish::0::1"
	C_LINE	21,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\fannkuch.c::bench_finish::0::1"
	C_LINE	23,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\fannkuch.c::bench_finish::0::1"

; Function main flags 0x00000000 __stdc
; int main(int argc, char * * argv)
; parameter 'int argc' at 2 size(2)
; parameter 'char * * argv' at 4 size(2)
	C_LINE	23,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\fannkuch.c::main::0::2"
._main
	pop	bc
	pop	hl
	push	hl
	push	bc
	call	l_gint4sp	;
	dec	sp
	pop	hl
	ld	l,7
	push	hl
	ld	h,0
	dec	sp
	ld	a,l
	pop	hl
	ld	l,a
	push	hl
	push	bc
	push	bc
	push	bc
	ld	hl,5	;const
	add	hl,sp
	ld	(hl),0
	jp	i_4	;EOS
.i_2
	ld	hl,5	;const
	add	hl,sp
	inc	(hl)
.i_4
	ld	hl,5	;const
	add	hl,sp
	ld	c,(hl)
	ld	b,0
	push	bc
	inc	hl
	ld	l,(hl)
	ld	h,0
	pop	de
	ld	a,e
	sub	l
	ld	a,d
	sbc	h
	jp	nc,i_3	;
	ld	hl,_perm1
	ex	de,hl
	ld	hl,5	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	add	hl,de
	ex	de,hl
	ld	hl,5	;const
	add	hl,sp
	ld	a,(hl)
	ld	(de),a
	jp	i_2	;EOS
.i_3
	ld	hl,3	;const
	add	hl,sp
	ex	de,hl
	ld	hl,6	;const
	add	hl,sp
	ld	a,(hl)
	ld	(de),a
	ld	hl,1	;const
	add	hl,sp
	ld	(hl),0
.i_8
	ld	hl,3	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	ld	a,l
	cp	1
	jp	z,ASMPC+4
	scf
	jp	nc,i_9	;
	ld	hl,_count
	push	hl
	ld	hl,5	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	dec	hl
	pop	de
	add	hl,de
	ex	de,hl
	ld	hl,3
	add	hl,sp
	ld	a,(hl)
	ld	(de),a
	dec	(hl)
	jp	i_8	;EOS
.i_9
	ld	hl,5	;const
	add	hl,sp
	ld	(hl),0
	jp	i_12	;EOS
.i_10
	ld	hl,5	;const
	add	hl,sp
	inc	(hl)
.i_12
	ld	hl,5	;const
	add	hl,sp
	ld	c,(hl)
	ld	b,0
	push	bc
	inc	hl
	ld	l,(hl)
	ld	h,0
	pop	de
	ld	a,e
	sub	l
	ld	a,d
	sbc	h
	jp	nc,i_11	;
	ld	hl,_perm
	ex	de,hl
	ld	hl,5	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	add	hl,de
	push	hl
	ld	hl,_perm1
	ex	de,hl
	ld	hl,7	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	add	hl,de
	ld	a,(hl)
	pop	de
	ld	(de),a
	jp	i_10	;EOS
.i_11
	ld	hl,2	;const
	add	hl,sp
	ld	(hl),0
.i_13
	ld	hl,(_perm)
	ld	h,0
	ld	a,l
	and	a
	jp	z,ASMPC+4
	scf
	jp	nc,i_14	;
	ld	hl,4	;const
	add	hl,sp
	ex	de,hl
	ld	a,(_perm)
	ld	(de),a
	dec	sp
	pop	hl
	ld	l,0
	push	hl
	ld	hl,5	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	dec	sp
	ld	a,l
	pop	hl
	ld	l,a
	push	hl
.i_15
	pop	hl
	push	hl
	ld	e,h
	ld	d,0
	pop	hl
	push	hl
	ld	h,0
	ld	a,e
	sub	l
	ld	a,d
	sbc	h
	jp	nc,i_16	;
	ld	hl,_perm
	ex	de,hl
	pop	hl
	push	hl
	ld	l,h
	ld	h,0
	add	hl,de
	ld	l,(hl)
	ld	h,0
	dec	sp
	ld	a,l
	pop	hl
	ld	l,a
	push	hl
	ld	hl,_perm
	ex	de,hl
	ld	hl,2	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	add	hl,de
	push	hl
	ld	hl,_perm
	ex	de,hl
	ld	hl,3	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	add	hl,de
	ld	a,(hl)
	pop	de
	ld	(de),a
	ld	hl,_perm
	ex	de,hl
	pop	hl
	push	hl
	ld	l,h
	ld	h,0
	add	hl,de
	ex	de,hl
	ld	hl,0	;const
	add	hl,sp
	ld	a,(hl)
	ld	(de),a
	ld	hl,2	;const
	add	hl,sp
	inc	(hl)
	ld	hl,1	;const
	add	hl,sp
	dec	(hl)
	ld	l,(hl)
	ld	h,0
	inc	l
	inc	sp
	jp	i_15	;EOS
.i_16
	pop	bc
	ld	hl,2	;const
	add	hl,sp
	inc	(hl)
	jp	i_13	;EOS
.i_14
	ld	hl,2	;const
	add	hl,sp
	ld	e,(hl)
	ld	d,0
	pop	hl
	push	hl
	ld	l,h
	ld	h,0
	ld	a,l
	sub	e
	ld	a,h
	sbc	d
	jp	nc,i_17	;
	ld	hl,1	;const
	add	hl,sp
	ex	de,hl
	ld	hl,2	;const
	add	hl,sp
	ld	a,(hl)
	ld	(de),a
.i_20
	ld	hl,3	;const
	add	hl,sp
	ld	a,(hl)
	ld	hl,6	;const
	add	hl,sp
	cp	(hl)
	jp	nz,i_21	;
	pop	hl
	push	hl
	ld	l,h
	ld	h,0
	push	hl
	call	_bench_finish
	pop	bc
	ld	hl,0	;const
	pop	bc
	pop	bc
	pop	bc
	pop	bc
	ret


.i_21
	ld	hl,0	;const
	add	hl,sp
	ex	de,hl
	ld	a,(_perm1)
	ld	(de),a
	ld	hl,5	;const
	add	hl,sp
	ld	(hl),0
	jp	i_24	;EOS
.i_22
	ld	hl,5	;const
	add	hl,sp
	inc	(hl)
.i_24
	ld	hl,5	;const
	add	hl,sp
	ld	e,(hl)
	ld	d,0
	ld	hl,3	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	ld	a,e
	sub	l
	ld	a,d
	sbc	h
	jp	nc,i_23	;
	ld	hl,_perm1
	ex	de,hl
	ld	hl,5	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	add	hl,de
	push	hl
	ld	hl,_perm1
	push	hl
	ld	hl,9	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	inc	hl
	pop	de
	add	hl,de
	ld	a,(hl)
	pop	de
	ld	(de),a
	jp	i_22	;EOS
.i_23
	ld	hl,_perm1
	ex	de,hl
	ld	hl,3	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	add	hl,de
	ex	de,hl
	ld	hl,0	;const
	add	hl,sp
	ld	a,(hl)
	ld	(de),a
	ld	hl,_count
	ex	de,hl
	ld	hl,3	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	add	hl,de
	push	hl
	ld	hl,_count
	ex	de,hl
	ld	hl,5	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	add	hl,de
	ld	l,(hl)
	ld	h,0
	dec	hl
	pop	de
	ld	a,l
	ld	(de),a
	ld	hl,_count
	ex	de,hl
	ld	hl,3	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	add	hl,de
	ld	l,(hl)
	ld	h,0
	xor	a
	sub	l
	jp	c,i_19	;EOS
.i_25
	ld	hl,3	;const
	add	hl,sp
	inc	(hl)
	jp	i_18	;EOS
.i_6
	pop	bc
	pop	bc
	pop	bc
	pop	bc
	ret


	SECTION	bss_compiler
	SECTION	code_compiler
; --- Start of Optimiser additions ---
	defc	i_5 = i_7
	defc	i_7 = i_8
	defc	i_18 = i_20
	defc	i_17 = i_20
	defc	i_19 = i_5


; --- Start of Static Variables ---

	SECTION	bss_compiler
._perm	defs	7
._perm1	defs	7
._count	defs	7
	SECTION	code_compiler


; --- Start of Scope Defns ---

	GLOBAL	_bench_finish
	GLOBAL	_main


; --- End of Scope Defns ---


; --- End of Compilation ---
