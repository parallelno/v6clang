	.text
	.globl	three_i8                        ; -- Begin function three_i8
three_i8:                               ; @three_i8
; %bb.0:
	LXI	HL, __v6clang_ss.three_i8+2
	MOV	M, C
	LXI	HL, __v6clang_ss.three_i8+1
	MOV	M, E
	CALL	op1
	STA	__v6clang_ss.three_i8
	LDA	__v6clang_ss.three_i8+1
	CALL	op2
	STA	__v6clang_ss.three_i8+1
	LDA	__v6clang_ss.three_i8+2
	CALL	op1
	MOV	C, A
	LXI	HL, __v6clang_ss.three_i8+2
	MOV	M, C
	LDA	__v6clang_ss.three_i8
	LXI	HL, __v6clang_ss.three_i8+1
	MOV	E, M
	CALL	use3
	LXI	HL, __v6clang_ss.three_i8
	MOV	L, M
	LDA	__v6clang_ss.three_i8+1
	ADD	L
	LXI	HL, __v6clang_ss.three_i8+2
	MOV	L, M
	ADD	L
	RET
                                        ; -- End function
	.globl	four_i8                         ; -- Begin function four_i8
four_i8:                                ; @four_i8
; %bb.0:
	LXI	HL, 0xffff
	DAD	SP
	SPHL
	LXI	HL, __v6clang_ss.four_i8+2
	MOV	M, C
	LXI	HL, __v6clang_ss.four_i8+1
	MOV	M, E
	CALL	op1
	STA	__v6clang_ss.four_i8
	LDA	__v6clang_ss.four_i8+1
	CALL	op2
	STA	__v6clang_ss.four_i8+1
	LDA	__v6clang_ss.four_i8+2
	CALL	op1
	STA	__v6clang_ss.four_i8+2
	LXI	HL, 1
	DAD	SP
	XCHG
	LDAX	DE
	CALL	op2
	STA	__v6clang_ss.four_i8+3
	LXI	HL, 0
	DAD	SP
	MOV	M, A
	LDA	__v6clang_ss.four_i8
	LXI	HL, __v6clang_ss.four_i8+1
	MOV	E, M
	LXI	HL, __v6clang_ss.four_i8+2
	MOV	C, M
	CALL	use4
	LXI	HL, __v6clang_ss.four_i8
	MOV	L, M
	LDA	__v6clang_ss.four_i8+1
	ADD	L
	LXI	HL, __v6clang_ss.four_i8+2
	MOV	L, M
	ADD	L
	LXI	HL, __v6clang_ss.four_i8+3
	MOV	L, M
	ADD	L
	LXI	HL, 1
	DAD	SP
	SPHL
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0xffff
	DAD	SP
	SPHL
	MVI	A, 0x11
	CALL	op1
	STA	__v6clang_ss.main
	MVI	A, 0x22
	CALL	op2
	STA	__v6clang_ss.main+1
	MVI	A, 0x33
	CALL	op1
	MOV	C, A
	LXI	HL, __v6clang_ss.main+5
	MOV	M, C
	LDA	__v6clang_ss.main
	LXI	HL, __v6clang_ss.main+1
	MOV	E, M
	CALL	use3
	MVI	A, 0x44
	CALL	op1
	STA	__v6clang_ss.main+2
	MVI	A, 0x55
	CALL	op2
	STA	__v6clang_ss.main+3
	MVI	A, 0x66
	CALL	op1
	STA	__v6clang_ss.main+4
	MVI	A, 0x77
	CALL	op2
	STA	__v6clang_ss.main+6
	LXI	HL, 0
	DAD	SP
	MOV	M, A
	LDA	__v6clang_ss.main+2
	LXI	HL, __v6clang_ss.main+3
	MOV	E, M
	LXI	HL, __v6clang_ss.main+4
	MOV	C, M
	CALL	use4
	LDA	__v6clang_ss.main+1
	LXI	HL, __v6clang_ss.main
	MOV	L, M
	ADD	L
	LXI	HL, __v6clang_ss.main+5
	MOV	L, M
	ADD	L
	MOV	L, A
	LDA	__v6clang_ss.main+3
	MOV	B, A
	LDA	__v6clang_ss.main+2
	MOV	H, A
	MOV	A, B
	ADD	H
	MOV	B, A
	LDA	__v6clang_ss.main+4
	MOV	H, A
	MOV	A, B
	ADD	H
	MOV	B, A
	LDA	__v6clang_ss.main+6
	MOV	H, A
	MOV	A, B
	ADD	H
	MOV	E, A
	MOV	A, L
	CALL	use2
	LXI	HL, 0
	XCHG
	LXI	HL, 1
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.local	__v6clang_ss.three_i8               ; @__v6clang_ss.three_i8
	.comm	__v6clang_ss.three_i8,3,1
	.local	__v6clang_ss.four_i8                ; @__v6clang_ss.four_i8
	.comm	__v6clang_ss.four_i8,4,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,7,1
	.addrsig
