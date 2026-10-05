	.text
	.globl	test_ne_zero                    ; -- Begin function test_ne_zero
test_ne_zero:                           ; @test_ne_zero
; %bb.0:
	MOV	D, H
	MOV	E, L
	LXI	HL, 0
	MOV	A, H
	CMP	E
	JNZ	.LBB0_1
; %bb.3:
	MVI	A, 0
	CMP	D
	JZ	.LBB0_2
.LBB0_1:
	MOV	H, D
	MOV	L, E
	JMP	bar
.LBB0_2:
	RET
                                        ; -- End function
	.globl	test_eq_zero                    ; -- Begin function test_eq_zero
test_eq_zero:                           ; @test_eq_zero
; %bb.0:
	MOV	D, H
	MOV	E, L
	LXI	HL, 0
	MOV	A, H
	CMP	E
	JNZ	.LBB1_1
; %bb.3:
	MVI	A, 0
	CMP	D
	JZ	.LBB1_2
.LBB1_1:
	MOV	H, D
	MOV	L, E
	JMP	bar
.LBB1_2:
	RET
                                        ; -- End function
	.globl	test_while_loop                 ; -- Begin function test_while_loop
test_while_loop:                        ; @test_while_loop
; %bb.0:
	MOV	D, H
	MOV	E, L
	LXI	HL, 0xfffc
	DAD	SP
	SPHL
	XCHG
	XCHG
	LXI	HL, 2
	DAD	SP
	LXI	BC, 0
	MOV	M, C
	INX	HL
	MOV	M, B
	MOV	A, B
	CMP	E
	JNZ	.LBB2_1
; %bb.3:
	MVI	A, 0
	CMP	D
	JZ	.LBB2_2
.LBB2_1:                                ; =>This Inner Loop Header: Depth=1
	LXI	HL, 2
	DAD	SP
	PUSH	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	POP	DE
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	MOV	C, M
	INX	HL
	MOV	B, M
	MOV	A, E
	ADD	C
	MOV	L, A
	MOV	A, D
	ADC	B
	MOV	H, A
	PUSH	HL
	LXI	HL, 2
	DAD	SP
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	PUSH	BC
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	BC
	DCX	DE
	MVI	A, 0
	CMP	E
	JNZ	.LBB2_1
; %bb.4:                                ;   in Loop: Header=BB2_1 Depth=1
	MVI	A, 0
	CMP	D
	JNZ	.LBB2_1
.LBB2_2:
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	XCHG
	LXI	HL, 4
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.globl	test_null_ptr                   ; -- Begin function test_null_ptr
test_null_ptr:                          ; @test_null_ptr
; %bb.0:
	LXI	DE, 0xffff
	MVI	A, 0
	CMP	L
	JNZ	.LBB3_1
; %bb.3:
	MVI	A, 0
	CMP	H
	JZ	.LBB3_2
.LBB3_1:
	MOV	E, M
	INX	HL
	MOV	D, M
.LBB3_2:
	MOV	H, D
	MOV	L, E
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0xfffc
	DAD	SP
	SPHL
	LXI	HL, 5
	CALL	bar
	PUSH	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	XCHG
	POP	DE
	LXI	BC, 2
	DAD	SP
	LXI	HL, 0
	PUSH	BC
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	BC
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	LXI	HL, 0xa
	DAD	DE
	PUSH	BC
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	BC
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	LXI	HL, 9
	DAD	DE
	PUSH	BC
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	BC
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	LXI	HL, 8
	DAD	DE
	PUSH	BC
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	BC
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	LXI	HL, 7
	DAD	DE
	PUSH	BC
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	BC
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	LXI	HL, 6
	DAD	DE
	PUSH	BC
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	BC
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	LXI	HL, 5
	DAD	DE
	PUSH	BC
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	BC
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	LXI	HL, 4
	DAD	DE
	PUSH	BC
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	BC
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	LXI	HL, 3
	DAD	DE
	PUSH	BC
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	BC
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	LXI	HL, 2
	DAD	DE
	PUSH	BC
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	BC
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	LXI	HL, 1
	DAD	DE
	PUSH	BC
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	BC
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	DAD	DE
	LXI	DE, 0x2a
	DAD	DE
	XCHG
	LXI	HL, 4
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.addrsig
