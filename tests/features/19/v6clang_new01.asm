	.text
	.globl	action_a                        ; -- Begin function action_a
action_a:                               ; @action_a
; %bb.0:
	LXI	HL, 1
	SHLD	sink
	RET
                                        ; -- End function
	.globl	action_b                        ; -- Begin function action_b
action_b:                               ; @action_b
; %bb.0:
	LXI	HL, 2
	SHLD	sink
	RET
                                        ; -- End function
	.globl	test_ne_same_bytes              ; -- Begin function test_ne_same_bytes
test_ne_same_bytes:                     ; @test_ne_same_bytes
; %bb.0:
	MOV	D, H
	MOV	E, L
	MVI	A, 0x42
	CMP	E
	JNZ	.LBB2_1
; %bb.3:
	CMP	D
	JZ	.LBB2_2
.LBB2_1:
	CALL	action_a
.LBB2_2:
	CALL	action_b
	XCHG
	RET
                                        ; -- End function
	.globl	test_eq_same_bytes              ; -- Begin function test_eq_same_bytes
test_eq_same_bytes:                     ; @test_eq_same_bytes
; %bb.0:
	MOV	D, H
	MOV	E, L
	MVI	A, 0x42
	CMP	E
	JNZ	.LBB3_2
; %bb.3:
	CMP	D
	JNZ	.LBB3_2
; %bb.1:
	CALL	action_a
.LBB3_2:
	CALL	action_b
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
	LXI	DE, 2
	DAD	SP
	LXI	BC, 0
	MOV	H, D
	MOV	L, E
	MOV	M, C
	INX	HL
	MOV	M, B
	CALL	action_b
	LXI	HL, 0x4242
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	CALL	action_b
	MOV	H, D
	MOV	L, E
	MOV	M, C
	INX	HL
	MOV	M, B
	CALL	action_a
	CALL	action_b
	LXI	HL, 0x4242
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LHLD	sink
	PUSH	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	POP	DE
	XCHG
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
	XCHG
	LXI	HL, 4
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	sink                            ; @sink
sink:
	DW	0                               ; 0x0

	.addrsig
	.addrsig_sym sink
