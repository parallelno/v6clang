	.text
	.globl	three_i8                        ; -- Begin function three_i8
three_i8:                               ; @three_i8
; %bb.0:
	LXI	HL, .LLo61_1+1
	MOV	M, C
	LXI	HL, .LLo61_2+1
	MOV	M, E
	CALL	op1
	STA	.LLo61_0+1
	LDA	.LLo61_2+1
	CALL	op2
	STA	.LLo61_2+1
	LDA	.LLo61_1+1
	CALL	op1
	MOV	C, A
	LXI	HL, .LLo61_1+1
	MOV	M, C
	LDA	.LLo61_0+1
.LLo61_2:
	MVI	E, 0
	CALL	use3
.LLo61_0:
	MVI	L, 0
	LDA	.LLo61_2+1
	ADD	L
.LLo61_1:
	MVI	L, 0
	ADD	L
	RET
                                        ; -- End function
	.globl	four_i8                         ; -- Begin function four_i8
four_i8:                                ; @four_i8
; %bb.0:
	LXI	HL, 0xffff
	DAD	SP
	SPHL
	LXI	HL, .LLo61_4+1
	MOV	M, C
	LXI	HL, .LLo61_5+1
	MOV	M, E
	CALL	op1
	STA	.LLo61_3+1
	LDA	.LLo61_5+1
	CALL	op2
	STA	.LLo61_5+1
	LDA	.LLo61_4+1
	CALL	op1
	STA	.LLo61_4+1
	LXI	HL, 1
	DAD	SP
	XCHG
	LDAX	DE
	CALL	op2
	STA	.LLo61_6+1
	LXI	HL, 0
	DAD	SP
	MOV	M, A
	LDA	.LLo61_3+1
.LLo61_5:
	MVI	E, 0
	LXI	HL, .LLo61_4+1
	MOV	C, M
	CALL	use4
.LLo61_3:
	MVI	L, 0
	LDA	.LLo61_5+1
	ADD	L
.LLo61_4:
	MVI	L, 0
	ADD	L
.LLo61_6:
	MVI	L, 0
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
	STA	.LLo61_7+1
	MVI	A, 0x22
	CALL	op2
	STA	.LLo61_12+1
	MVI	A, 0x33
	CALL	op1
	MOV	C, A
	LXI	HL, .LLo61_14+1
	MOV	M, C
	LDA	.LLo61_7+1
.LLo61_12:
	MVI	E, 0
	CALL	use3
	MVI	A, 0x44
	CALL	op1
	STA	.LLo61_8+1
	MVI	A, 0x55
	CALL	op2
	STA	.LLo61_13+1
	MVI	A, 0x66
	CALL	op1
	STA	.LLo61_9+1
	STA	.LLo61_10+1
	MVI	A, 0x77
	CALL	op2
	STA	.LLo61_11+1
	LXI	HL, 0
	DAD	SP
	MOV	M, A
	LDA	.LLo61_8+1
.LLo61_13:
	MVI	E, 0
.LLo61_10:
	MVI	C, 0
	CALL	use4
	LDA	.LLo61_12+1
.LLo61_7:
	MVI	L, 0
	ADD	L
.LLo61_14:
	MVI	L, 0
	ADD	L
	MOV	L, A
	LDA	.LLo61_13+1
.LLo61_8:
	MVI	H, 0
	ADD	H
.LLo61_9:
	MVI	H, 0
	ADD	H
.LLo61_11:
	MVI	H, 0
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
	.addrsig
