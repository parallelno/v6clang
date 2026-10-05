	.text
	.globl	test_pattern_a                  ; -- Begin function test_pattern_a
test_pattern_a:                         ; @test_pattern_a
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
	CALL	bar
.LBB0_2:
	RET
                                        ; -- End function
	.globl	test_pattern_b                  ; -- Begin function test_pattern_b
test_pattern_b:                         ; @test_pattern_b
; %bb.0:
	MOV	D, H
	MOV	E, L
	LXI	HL, 0
	MOV	A, H
	CMP	E
	JNZ	.LBB1_2
; %bb.3:
	MVI	A, 0
	CMP	D
	JNZ	.LBB1_2
; %bb.1:
	CALL	bar
.LBB1_2:
	RET
                                        ; -- End function
	.globl	test_pattern_c                  ; -- Begin function test_pattern_c
test_pattern_c:                         ; @test_pattern_c
; %bb.0:
	MVI	A, 0
	CMP	L
	JNZ	.LBB2_1
; %bb.4:
	MVI	A, 0
	CMP	H
	JNZ	.LBB2_1
; %bb.2:
	LXI	HL, 0
	JMP	baz
.LBB2_1:
	JMP	bar
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0xfffe
	DAD	SP
	SPHL
	LXI	HL, 1
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
	LXI	HL, 0
	CALL	bar
	PUSH	HL
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	POP	HL
	DAD	DE
	PUSH	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
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
	DAD	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.addrsig
