	.text
	.globl	test_two_cond_tailcall          ; -- Begin function test_two_cond_tailcall
test_two_cond_tailcall:                 ; @test_two_cond_tailcall
; %bb.0:
	ORA	A
	JZ	.LBB0_1
; %bb.3:
	JMP	bar
.LBB0_1:
	XRA	A
	CMP	E
	RZ
.LBB0_2:
	JMP	bar
                                        ; -- End function
	.globl	test_simple_zero_check          ; -- Begin function test_simple_zero_check
test_simple_zero_check:                 ; @test_simple_zero_check
; %bb.0:
	ORA	A
; %bb.1:
	LXI	HL, 1
	JMP	.LBB1_3
.LBB1_2:
	LXI	HL, 0
.LBB1_3:
	MOV	A, L
	ANI	1
	RET
                                        ; -- End function
	.globl	test_nz_branch                  ; -- Begin function test_nz_branch
test_nz_branch:                         ; @test_nz_branch
; %bb.0:
	ORA	A
	JNZ	.LBB2_2
; %bb.1:
	MOV	E, A
.LBB2_2:
	MOV	A, E
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0xfffd
	DAD	SP
	SPHL
	LXI	HL, 2
	DAD	SP
	PUSH	DE
	MOV	D, H
	MOV	E, L
	LXI	HL, 2
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	XCHG
	POP	DE
	MVI	A, 0
	MOV	M, A
	INR	A
	CALL	bar
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	MOV	M, A
	MVI	A, 0
	CALL	bar
	PUSH	HL
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	POP	HL
	STAX	DE
	MVI	A, 0
	STAX	DE
	MVI	L, 1
	MOV	H, D
	MOV	L, E
	MOV	M, L
	STAX	DE
	MVI	A, 0xa
	STAX	DE
	LXI	HL, 0
	XCHG
	LXI	HL, 3
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.addrsig
