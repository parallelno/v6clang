	.text
	.globl	test_ne_zero                    ; -- Begin function test_ne_zero
test_ne_zero:                           ; @test_ne_zero
; %bb.0:
	MOV	A, H
	ORA	L
	RZ
.LBB0_1:
	JMP	bar
                                        ; -- End function
	.globl	test_eq_zero                    ; -- Begin function test_eq_zero
test_eq_zero:                           ; @test_eq_zero
; %bb.0:
	MOV	A, H
	ORA	L
	RZ
.LBB1_1:
	JMP	bar
                                        ; -- End function
	.globl	test_multi_cond                 ; -- Begin function test_multi_cond
test_multi_cond:                        ; @test_multi_cond
; %bb.0:
	MOV	D, H
	MOV	E, L
	LXI	HL, 0xa
	MVI	A, 1
	CMP	E
	JNZ	.LBB2_1
; %bb.5:
	MVI	A, 0
	CMP	D
	RZ
.LBB2_1:
	MVI	A, 2
	CMP	E
	JNZ	.LBB2_3
; %bb.6:
	MVI	A, 0
	CMP	D
	JZ	.LBB2_2
.LBB2_3:
	MOV	H, D
	MOV	L, E
	JMP	bar
.LBB2_2:
	LXI	HL, 0x14
	RET
                                        ; -- End function
	.globl	test_null_guard                 ; -- Begin function test_null_guard
test_null_guard:                        ; @test_null_guard
; %bb.0:
	LXI	DE, 0xffff
	MOV	A, H
	ORA	L
	JZ	.LBB3_2
; %bb.1:
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
	LXI	HL, 0xfffe
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
	LXI	HL, 3
	CALL	bar
	PUSH	HL
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	POP	HL
	DAD	DE
	LXI	DE, 0x48
	DAD	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.addrsig
