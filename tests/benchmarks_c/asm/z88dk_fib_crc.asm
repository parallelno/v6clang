;* * * * *  Small-C/Plus z88dk * * * * *
;  Version: 23854-4d530b6eb7-20251002
;
;	Reconstructed for z80 Module Assembler
;
;	Module compile time: Tue Jun 02 18:56:56 2026


	C_LINE	0,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\fib_crc.c"

	MODULE	C__Work_Programming_v6clang_tests_benchmarks_c_src_fib_crc_c


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


	C_LINE	4,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\fib_crc.c::bench_finish::0::1"
	C_LINE	8,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\fib_crc.c::bench_finish::0::1"

; Function crc_byte flags 0x00000200 __smallc
; unsigned int u16crc_byte(unsigned int crc, unsigned char b)
; parameter 'unsigned char b' at sp+2 size(1)
; parameter 'unsigned int crc' at sp+4 size(2)
	C_LINE	8,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\fib_crc.c::crc_byte::0::1"
._crc_byte
	push	bc
	ld	hl,6	;const
	add	hl,sp
	push	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,6	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	call	l_xor
	call	l_pint_pop
	ld	hl,0	;const
	pop	bc
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
	sub	8
	ld	a,h
	rla
	ccf
	rra
	sbc	128
	jp	nc,i_3	;
	call	l_gint6sp	;
	ld	a,l
	and	1
	jp	z,i_5	;
	ld	hl,6	;const
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
	ld	de,40961
	call	l_xor
	call	l_pint_pop
	jp	i_6	;EOS
.i_5
	ld	hl,6	;const
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
	jp	i_2	;EOS
.i_3
	call	l_gint6sp	;
	pop	bc
	ret


	C_LINE	18,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\fib_crc.c::crc_byte::0::3"

; Function main flags 0x00000000 __stdc
; int main(int argc, char * * argv)
; parameter 'int argc' at 2 size(2)
; parameter 'char * * argv' at 4 size(2)
	C_LINE	18,"C:\Work\Programming\v6clang\tests\benchmarks_c\src\fib_crc.c::main::0::4"
._main
	pop	bc
	pop	hl
	push	hl
	push	bc
	call	l_gint4sp	;
	ld	hl,1
	push	hl
	ld	l,h
	ld	h,0
	push	hl
	ld	hl,2	;const
	add	hl,sp
	ld	l,(hl)
	ld	h,0
	push	hl
	ld	hl,65535	;const
	push	hl
	ld	hl,0	;const
	push	hl
	jp	i_9	;EOS
.i_7
	pop	hl
	inc	hl
	push	hl
.i_9
	pop	hl
	push	hl
	ld	a,l
	sub	24
	ld	a,h
	rla
	ccf
	rra
	sbc	128
	jp	nc,i_8	;
	ld	hl,6	;const
	call	l_gintspsp	;
	call	l_gint6sp	;
	pop	de
	add	hl,de
	push	hl
	ld	hl,4	;const
	add	hl,sp
	push	hl
	ld	hl,6	;const
	call	l_gintspsp	;
	call	l_gint4sp	;
	ld	h,0
	push	hl
	call	_crc_byte
	pop	bc
	pop	bc
	call	l_pint_pop
	ld	hl,4	;const
	add	hl,sp
	push	hl
	ld	hl,6	;const
	call	l_gintspsp	;
	call	l_gint4sp	;
	ld	l,h
	ld	h,0
	push	hl
	call	_crc_byte
	pop	bc
	pop	bc
	call	l_pint_pop
	ld	hl,8	;const
	add	hl,sp
	push	hl
	dec	hl
	dec	hl
	call	l_gint	;
	call	l_pint_pop
	ld	hl,6	;const
	add	hl,sp
	pop	de
	push	de
	ld	(hl),e
	inc	hl
	ld	(hl),d
	ex	de,hl
	pop	bc
	jp	i_7	;EOS
.i_8
	pop	bc
	pop	hl
	push	hl
	push	bc
	ld	h,0
	push	hl
	call	_bench_finish
	pop	bc
	ld	hl,0	;const
	pop	bc
	pop	bc
	pop	bc
	pop	bc
	pop	bc
	ret


	SECTION	bss_compiler
	SECTION	code_compiler
; --- Start of Optimiser additions ---
	defc	i_6 = i_2


; --- Start of Static Variables ---

	SECTION	bss_compiler
	SECTION	code_compiler


; --- Start of Scope Defns ---

	GLOBAL	_bench_finish
	GLOBAL	_main


; --- End of Scope Defns ---


; --- End of Compilation ---
