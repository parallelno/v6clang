	.text
	.globl	test_cond_zero_tailcall         ; -- Begin function test_cond_zero_tailcall
test_cond_zero_tailcall:                ; @test_cond_zero_tailcall
; %bb.0:
	MOV	D, H
	MOV	E, L
	LXI	HL, 0
	MOV	A, D
	ORA	E
	JZ	bar
; %bb.2:
	RET
                                        ; -- End function
	.globl	test_two_cond_tailcall          ; -- Begin function test_two_cond_tailcall
test_two_cond_tailcall:                 ; @test_two_cond_tailcall
; %bb.0:
	MOV	A, H
	ORA	L
	JNZ	.LBB1_2
; %bb.1:
	LXI	HL, 0
	MOV	A, D
	ORA	E
	JZ	.LBB1_3
.LBB1_2:
	CALL	bar
	XCHG
.LBB1_3:
	XCHG
	RET
                                        ; -- End function
	.globl	test_simple_tailcall            ; -- Begin function test_simple_tailcall
test_simple_tailcall:                   ; @test_simple_tailcall
; %bb.0:
	MOV	A, H
	ORA	L
	RZ
.LBB2_1:
	JMP	bar
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0xfffc
	DAD	SP
	SPHL
	LXI	HL, 0
	CALL	bar
	LXI	DE, 2
	DAD	SP
	PUSH	HL
	LXI	HL, 2
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	POP	HL
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LXI	HL, 0
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LXI	HL, 1
	CALL	bar
	PUSH	HL
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	POP	HL
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LXI	HL, 0
	CALL	bar
	PUSH	HL
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	POP	HL
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LXI	HL, 0
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LXI	HL, 5
	CALL	bar
	PUSH	HL
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	POP	HL
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LXI	HL, 0
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LXI	HL, 0
	XCHG
	LXI	HL, 4
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.addrsig
