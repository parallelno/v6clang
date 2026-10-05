	.text
	.globl	test_two_arg_tailcall           ; -- Begin function test_two_arg_tailcall
test_two_arg_tailcall:                  ; @test_two_arg_tailcall
; %bb.0:
	MOV	B, H
	MOV	C, L
	LXI	HL, 0
	MOV	A, B
	ORA	C
	JZ	.LBB0_1
; %bb.2:
	RET
.LBB0_1:
	XCHG
	JMP	bar
                                        ; -- End function
	.globl	test_cond_zero_tailcall         ; -- Begin function test_cond_zero_tailcall
test_cond_zero_tailcall:                ; @test_cond_zero_tailcall
; %bb.0:
	MOV	D, H
	MOV	E, L
	LXI	HL, 0
	MOV	A, D
	ORA	E
	JZ	.LBB1_1
; %bb.2:
	RET
.LBB1_1:
	JMP	bar
                                        ; -- End function
	.globl	test_early_return               ; -- Begin function test_early_return
test_early_return:                      ; @test_early_return
; %bb.0:
	MOV	A, H
	ORA	L
	JZ	.LBB2_2
; %bb.1:
	JMP	bar
.LBB2_2:
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
	LXI	HL, 3
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
