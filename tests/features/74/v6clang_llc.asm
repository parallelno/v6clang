	.text
	.globl	p1_lo_byte_after_xor16          ; -- Begin function p1_lo_byte_after_xor16
p1_lo_byte_after_xor16:                 ; @p1_lo_byte_after_xor16
; %bb.0:
	LXI	D, 0xb4ff
	MOV	A, L
	XRA	E
	MOV	L, A
	MOV	A, H
	XRA	D
	MOV	H, A
	SHLD	g_sink16
	MOV	A, E
	RET
                                        ; -- End function
	.globl	p2_hi_byte_after_xor16          ; -- Begin function p2_hi_byte_after_xor16
p2_hi_byte_after_xor16:                 ; @p2_hi_byte_after_xor16
; %bb.0:
	LXI	D, 0xb4ff
	MOV	A, L
	XRA	E
	MOV	L, A
	MOV	A, H
	XRA	D
	MOV	H, A
	SHLD	g_sink16
	MOV	A, D
	RET
                                        ; -- End function
	.globl	p3_standalone_lo                ; -- Begin function p3_standalone_lo
p3_standalone_lo:                       ; @p3_standalone_lo
; %bb.0:
	MVI	A, 0x34
	RET
                                        ; -- End function
	.globl	p4_standalone_hi                ; -- Begin function p4_standalone_hi
p4_standalone_hi:                       ; @p4_standalone_hi
; %bb.0:
	MVI	A, 0x12
	RET
                                        ; -- End function
	.globl	p5_both_bytes_used              ; -- Begin function p5_both_bytes_used
p5_both_bytes_used:                     ; @p5_both_bytes_used
; %bb.0:
	LXI	D, 0xb4ff
	MOV	A, L
	XRA	E
	MOV	L, A
	MOV	A, H
	XRA	D
	MOV	H, A
	SHLD	g_sink16
	LXI	H, 0xb4ff
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	H, 0x1234
	CALL	p1_lo_byte_after_xor16
	MVI	A, 0xff
	STA	__v6clang_a.main
	LXI	H, 0x5678
	CALL	p2_hi_byte_after_xor16
	MVI	A, 0xb4
	STA	__v6clang_a.main+1
	MVI	A, 0x34
	STA	__v6clang_a.main+2
	MVI	A, 0x12
	STA	__v6clang_a.main+3
	LXI	H, 0xabcd
	CALL	p5_both_bytes_used
	LXI	H, 0xb4ff
	SHLD	__v6clang_a.main+4
	INR	L
	LDA	__v6clang_a.main
	MOV	D, L
	MOV	E, A
	LDA	__v6clang_a.main+1
	MOV	B, L
	MOV	C, A
	XCHG
	DAD	B
	XCHG
	LDA	__v6clang_a.main+2
	MOV	B, L
	MOV	C, A
	XCHG
	DAD	B
	XCHG
	LDA	__v6clang_a.main+3
	MOV	H, L
	MOV	L, A
	DAD	D
	LXI	D, 0xff
	LDA	__v6clang_a.main+4
	MOV	C, A
	LDA	__v6clang_a.main+5
	MOV	B, A
	MOV	A, C
	ANA	E
	MOV	E, A
	MOV	A, B
	ANA	D
	MOV	D, A
	DAD	D
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_sink16                        ; @g_sink16
	.p2align	1, 0x0
g_sink16:
	DW	0                               ; 0x0

	.globl	g_sink8                         ; @g_sink8
g_sink8:
	DB	0                               ; 0x0

	.local	__v6clang_a.main                    ; @__v6clang_a.main
	.comm	__v6clang_a.main,6,1
