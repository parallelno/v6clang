;* * * * *  Small-C/Plus z88dk * * * * *
;  Version: 23854-4d530b6eb7-20251002
;
;	Reconstructed for z80 Module Assembler
;
;	Module compile time: Tue Jun 02 18:56:53 2026


	C_LINE	0,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\sieve.c"

	MODULE	C__Work_Programming_v6clang_tests_benchmarks_c_src_sieve_c


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


	C_LINE	13,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\sieve.c::bench_finish::0::1"
	C_LINE	19,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\sieve.c::bench_finish::0::1"
	C_LINE	21,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\sieve.c::bench_finish::0::1"

; Function main flags 0x00000000 __stdc
; int main(int argc, char * * argv)
; parameter 'int argc' at 2 size(2)
; parameter 'char * * argv' at 4 size(2)
	C_LINE	21,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\sieve.c::main::0::2"
._main
	pop	bc
	pop	hl
	push	hl
	push	bc
	call	l_gint4sp	;
	push	bc
	push	bc
	push	bc
	push	bc
	ld	hl,0	;const
	push	hl
	jp	i_4	;EOS
.i_2
	pop	hl
	inc	hl
	push	hl
.i_4
	pop	hl
	push	hl
	ld	a,l
	sub	64
	ld	a,h
	sbc	31
	jp	nc,i_3	;
	pop	hl
	push	hl
	ld	bc,_flags
	push	bc
	pop	de
	add	hl,de
	ld	(hl),0
	jp	i_2	;EOS
.i_3
	pop	bc
	ld	hl,7998	;const
	pop	bc
	push	hl
	ld	hl,4	;const
	add	hl,sp
	ld	(hl),4
	inc	hl
	ld	(hl),0
	ld	hl,6	;const
	add	hl,sp
	ld	(hl),2
	inc	hl
	ld	(hl),0
	jp	i_7	;EOS
.i_5
	ld	hl,6	;const
	add	hl,sp
	push	hl
	call	l_gint	;
	inc	hl
	call	l_pint_pop
.i_7
	call	l_gint4sp	;
	ld	a,l
	sub	64
	ld	a,h
	sbc	31
	jp	nc,i_6	;
	ld	hl,_flags
	ex	de,hl
	call	l_gint6sp
	add	hl,de
	ld	a,(hl)
	and	a
	jp	nz,i_8	;
	call	l_gint4sp	;
	pop	de
	pop	bc
	push	hl
	push	de
	jp	i_11	;EOS
.i_9
	ld	hl,2	;const
	call	l_gintspsp	;
	call	l_gint8sp	;
	pop	de
	add	hl,de
	pop	de
	pop	bc
	push	hl
	push	de
.i_11
	pop	bc
	pop	hl
	push	hl
	push	bc
	ld	a,l
	sub	64
	ld	a,h
	sbc	31
	jp	nc,i_10	;
	ld	hl,_flags
	ex	de,hl
	call	l_gint2sp
	add	hl,de
	ld	a,(hl)
	and	a
	jp	nz,i_12	;
	pop	hl
	push	hl
	dec	hl
	pop	bc
	push	hl
.i_12
	ld	hl,_flags
	ex	de,hl
	call	l_gint2sp
	add	hl,de
	ld	(hl),1
	jp	i_9	;EOS
.i_8
	ld	hl,4	;const
	add	hl,sp
	push	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	call	l_gint8sp	;
	add	hl,de
	ex	de,hl
	call	l_gint8sp	;
	add	hl,de
	inc	hl
	call	l_pint_pop
	jp	i_5	;EOS
.i_6
	pop	hl
	push	hl
	ld	h,0
	pop	de
	push	de
	push	hl
	ex	de,hl
	ld	l,h
	ld	h,0
	pop	de
	call	l_xor
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


	SECTION	bss_compiler
	SECTION	code_compiler
; --- Start of Optimiser additions ---
	defc	i_10 = i_8


; --- Start of Static Variables ---

	SECTION	bss_compiler
._flags	defs	8000
	SECTION	code_compiler


; --- Start of Scope Defns ---

	GLOBAL	_bench_finish
	GLOBAL	_main


; --- End of Scope Defns ---


; --- End of Compilation ---
