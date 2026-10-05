	.text
	.globl	many_i8                         ; -- Begin function many_i8
many_i8:                                ; @many_i8
; %bb.0:
	LXI	HL, 0xfffe
	DAD	SP
	SPHL
	LXI	HL, __v6clang_ss.many_i8+2
	MOV	M, C
	LXI	HL, __v6clang_ss.many_i8+1
	MOV	M, E
	CALL	op
	STA	__v6clang_ss.many_i8
	LDA	__v6clang_ss.many_i8+1
	CALL	op
	STA	__v6clang_ss.many_i8+1
	LDA	__v6clang_ss.many_i8+2
	CALL	op
	STA	__v6clang_ss.many_i8+2
	LXI	HL, 2
	DAD	SP
	XCHG
	LDAX	DE
	CALL	op
	STA	__v6clang_ss.many_i8+3
	LXI	HL, 2
	DAD	SP
	XCHG
	LDAX	DE
	CALL	op
	MOV	E, A
	LXI	HL, __v6clang_ss.many_i8+4
	MOV	M, E
	LXI	HL, 0
	DAD	SP
	LDA	__v6clang_ss.many_i8+3
	MOV	M, A
	INX	HL
	MOV	M, E
	LDA	__v6clang_ss.many_i8
	LXI	HL, __v6clang_ss.many_i8+1
	MOV	E, M
	LXI	HL, __v6clang_ss.many_i8+2
	MOV	C, M
	CALL	use5
	LDA	__v6clang_ss.many_i8+1
	LXI	HL, __v6clang_ss.many_i8
	MOV	L, M
	XRA	L
	LXI	HL, __v6clang_ss.many_i8+2
	MOV	L, M
	XRA	L
	LXI	HL, __v6clang_ss.many_i8+3
	MOV	L, M
	XRA	L
	LXI	HL, __v6clang_ss.many_i8+4
	MOV	L, M
	XRA	L
	LXI	HL, 2
	DAD	SP
	SPHL
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0xfffe
	DAD	SP
	SPHL
	MVI	A, 0x11
	CALL	op
	STA	__v6clang_ss.main
	MVI	A, 0x22
	CALL	op
	STA	__v6clang_ss.main+1
	MVI	A, 0x33
	CALL	op
	STA	__v6clang_ss.main+2
	MVI	A, 0x44
	CALL	op
	STA	__v6clang_ss.main+3
	MVI	A, 0x55
	CALL	op
	LXI	HL, 0
	DAD	SP
	MOV	B, A
	LDA	__v6clang_ss.main+3
	MOV	E, A
	MOV	A, B
	MOV	M, E
	INX	HL
	MOV	M, A
	LDA	__v6clang_ss.main
	LXI	HL, __v6clang_ss.main+1
	MOV	E, M
	LXI	HL, __v6clang_ss.main+2
	MOV	C, M
	CALL	use5
	LXI	HL, 0
	XCHG
	LXI	HL, 2
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.local	__v6clang_ss.many_i8                ; @__v6clang_ss.many_i8
	.comm	__v6clang_ss.many_i8,5,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,4,1
	.addrsig
