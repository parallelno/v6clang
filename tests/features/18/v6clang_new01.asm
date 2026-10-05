	.text
	.globl	test_ne_same_bytes              ; -- Begin function test_ne_same_bytes
test_ne_same_bytes:                     ; @test_ne_same_bytes
; %bb.0:
	MOV	D, H
	MOV	E, L
	LXI	HL, 0xfffe
	DAD	SP
	SPHL
	MOV	H, D
	MOV	L, E
	PUSH	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	XCHG
	POP	DE
	MVI	A, 0x42
	CMP	L
	JNZ	.LBB0_1
; %bb.3:
	CMP	H
	JZ	.LBB0_2
.LBB0_1:
	CALL	action_a
.LBB0_2:
	CALL	action_b
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.globl	test_eq_same_bytes              ; -- Begin function test_eq_same_bytes
test_eq_same_bytes:                     ; @test_eq_same_bytes
; %bb.0:
	MOV	D, H
	MOV	E, L
	LXI	HL, 0xfffe
	DAD	SP
	SPHL
	MOV	H, D
	MOV	L, E
	PUSH	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	XCHG
	POP	DE
	MVI	A, 0x42
	CMP	L
	JNZ	.LBB1_2
; %bb.3:
	CMP	H
	JNZ	.LBB1_2
; %bb.1:
	CALL	action_a
.LBB1_2:
	CALL	action_b
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.globl	test_ne_diff_bytes              ; -- Begin function test_ne_diff_bytes
test_ne_diff_bytes:                     ; @test_ne_diff_bytes
; %bb.0:
	MOV	D, H
	MOV	E, L
	LXI	HL, 0xfffe
	DAD	SP
	SPHL
	MOV	H, D
	MOV	L, E
	PUSH	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	XCHG
	POP	DE
	MVI	A, 0x34
	CMP	L
	JNZ	.LBB2_1
; %bb.3:
	MVI	A, 0x12
	CMP	H
	JZ	.LBB2_2
.LBB2_1:
	CALL	action_a
.LBB2_2:
	CALL	action_b
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.globl	test_ne_0101                    ; -- Begin function test_ne_0101
test_ne_0101:                           ; @test_ne_0101
; %bb.0:
	MOV	D, H
	MOV	E, L
	LXI	HL, 0xfffe
	DAD	SP
	SPHL
	MOV	H, D
	MOV	L, E
	PUSH	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	XCHG
	POP	DE
	MVI	A, 1
	CMP	L
	JNZ	.LBB3_1
; %bb.3:
	CMP	H
	JZ	.LBB3_2
.LBB3_1:
	CALL	action_a
.LBB3_2:
	CALL	action_b
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0xfffc
	DAD	SP
	SPHL
	CALL	action_a
	CALL	action_b
	LXI	HL, 2
	DAD	SP
	PUSH	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	XCHG
	POP	DE
	LXI	DE, 0
	MOV	M, E
	INX	HL
	MOV	M, D
	CALL	action_b
	LXI	DE, 0x4242
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	MOV	M, E
	INX	HL
	MOV	M, D
	CALL	action_a
	CALL	action_b
	LXI	DE, 0x1234
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	MOV	M, E
	INX	HL
	MOV	M, D
	CALL	action_b
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	LXI	DE, 0
	MOV	M, E
	INX	HL
	MOV	M, D
	CALL	action_a
	CALL	action_b
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	LXI	DE, 0x4242
	MOV	M, E
	INX	HL
	MOV	M, D
	CALL	action_a
	CALL	action_b
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	LXI	DE, 0
	MOV	M, E
	INX	HL
	MOV	M, D
	CALL	action_b
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	LXI	DE, 0x1234
	MOV	M, E
	INX	HL
	MOV	M, D
	CALL	action_a
	CALL	action_b
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	LXI	DE, 0
	MOV	M, E
	INX	HL
	MOV	M, D
	CALL	action_b
	LXI	HL, 0x101
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
	XCHG
	LXI	HL, 4
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.addrsig
