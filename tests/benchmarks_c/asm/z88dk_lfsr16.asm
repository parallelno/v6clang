;* * * * *  Small-C/Plus z88dk * * * * *
;  Version: 23854-4d530b6eb7-20251002
;
;	Reconstructed for z80 Module Assembler
;
;	Module compile time: Tue Jun 02 18:57:02 2026


	C_LINE	0,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\lfsr16.c"

	MODULE	C__Work_Programming_v6clang_tests_benchmarks_c_src_lfsr16_c


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


	C_LINE	14,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\lfsr16.c::bench_finish::0::1"
	C_LINE	20,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\lfsr16.c::bench_finish::0::1"

; Function main flags 0x00000000 __stdc
; int main(int argc, char * * argv)
; parameter 'int argc' at 2 size(2)
; parameter 'char * * argv' at 4 size(2)
	C_LINE	20,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\lfsr16.c::main::0::2"
._main
	pop	bc
	pop	hl
	push	hl
	push	bc
	call	l_gint4sp	;
	ld	hl,44257	;const
	push	hl
	push	hl
	ld	hl,0	;const
	push	hl
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
	sub	0
	ld	a,h
	sbc	16
	jp	nc,i_3	;
	call	l_gint4sp	;
	ld	a,l
	and	1
	ld	l,a
	ld	h,0
	dec	sp
	ld	a,l
	pop	hl
	ld	l,a
	push	hl
	ld	hl,5	;const
	add	hl,sp
	push	hl
	call	l_gint	;
	xor	a
	ld	a,h
	rra
	ld	h,a
	ld	a,l
	rra
	ld	l,a
	call	l_pint_pop
	ld	hl,0	;const
	add	hl,sp
	ld	a,(hl)
	and	a
	jp	z,i_5	;
	ld	hl,5	;const
	add	hl,sp
	push	hl
	call	l_gint	;
	ld	a,h
	xor	180
	ld	h,a
	call	l_pint_pop
.i_5
	ld	hl,3	;const
	add	hl,sp
	push	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	call	l_gint7sp	;
	call	l_xor
	call	l_pint_pop
	inc	sp
	jp	i_2	;EOS
.i_3
	pop	bc
	pop	hl
	push	hl
	push	bc
	ld	h,0
	push	hl
	call	l_gint4sp	;
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


; --- Start of Static Variables ---

	SECTION	bss_compiler
	SECTION	code_compiler


; --- Start of Scope Defns ---

	GLOBAL	_bench_finish
	GLOBAL	_main


; --- End of Scope Defns ---


; --- End of Compilation ---
