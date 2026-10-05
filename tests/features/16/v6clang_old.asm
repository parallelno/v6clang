	.text
	.globl	test_cond_zero_return_zero      ; -- Begin function test_cond_zero_return_zero
test_cond_zero_return_zero:             ; @test_cond_zero_return_zero
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
	.globl	test_both_call_zero             ; -- Begin function test_both_call_zero
test_both_call_zero:                    ; @test_both_call_zero
; %bb.0:
	LXI	HL, 0
	JMP	bar
                                        ; -- End function
	.globl	test_one_path_zero              ; -- Begin function test_one_path_zero
test_one_path_zero:                     ; @test_one_path_zero
; %bb.0:
	MOV	A, H
	ORA	L
	JZ	bar
; %bb.2:
	RET
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
	LXI	HL, 5
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
