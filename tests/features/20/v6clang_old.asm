	.text
	.globl	interleaved_add                 ; -- Begin function interleaved_add
interleaved_add:                        ; @interleaved_add
; %bb.0:
	PUSH	HL
	PUSH	DE
	LXI	HL, 0xfff7
	DAD	SP
	SPHL
	LXI	HL, 9
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	INX	HL
	MOV	A, M
	INX	HL
	MOV	H, M
	MOV	L, A
	PUSH	HL
	LXI	HL, 0xb
	DAD	SP
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	PUSH	HL
	LXI	HL, 0xd
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	POP	HL
	XCHG
	LXI	HL, 4
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	XCHG
	LXI	HL, 0xd
	DAD	SP
	MOV	A, M
	ORA	A
	JZ	.LBB0_3
; %bb.1:
	MVI	L, 0
	MOV	B, L
	MOV	C, A
	LXI	HL, 4
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
.LBB0_2:                                ; =>This Inner Loop Header: Depth=1
	LXI	HL, 7
	DAD	SP
	MOV	M, C
	INX	HL
	MOV	M, B
	PUSH	DE
	LXI	HL, 0xd
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	PUSH	DE
	XCHG
	LXI	HL, 0xd
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	XCHG
	POP	DE
	MOV	A, M
	PUSH	HL
	LXI	HL, 8
	DAD	SP
	MOV	M, A
	POP	HL
	PUSH	HL
	LXI	HL, 0xb
	DAD	SP
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	LDAX	BC
	PUSH	DE
	MOV	D, H
	LXI	HL, 8
	DAD	SP
	MOV	L, M
	MOV	H, D
	POP	DE
	ADD	L
	STAX	DE
	PUSH	DE
	LXI	HL, 0xd
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	INX	HL
	PUSH	DE
	XCHG
	LXI	HL, 0xd
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	POP	DE
	PUSH	DE
	LXI	HL, 0xd
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	INX	BC
	LXI	HL, 9
	DAD	SP
	MOV	M, C
	INX	HL
	MOV	M, B
	LXI	HL, 7
	DAD	SP
	MOV	C, M
	INX	HL
	MOV	B, M
	INX	DE
	DCX	BC
	MOV	A, B
	ORA	C
	JNZ	.LBB0_2
.LBB0_3:
	LXI	HL, 4
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	MOV	A, M
	CALL	use8
	LXI	HL, 0xd
	DAD	SP
	SPHL
	RET
                                        ; -- End function
	.globl	multi_live                      ; -- Begin function multi_live
multi_live:                             ; @multi_live
; %bb.0:
	LXI	HL, 0xfffe
	DAD	SP
	SPHL
	PUSH	HL
	LXI	HL, 3
	DAD	SP
	MOV	M, E
	POP	HL
	PUSH	HL
	LXI	HL, 2
	DAD	SP
	MOV	M, A
	POP	HL
	MOV	A, C
	CALL	use8
	PUSH	HL
	LXI	HL, 2
	DAD	SP
	MOV	A, M
	POP	HL
	MOV	D, H
	LXI	HL, 1
	DAD	SP
	MOV	L, M
	MOV	H, D
	ADD	L
	ADI	3
	LXI	HL, 2
	DAD	SP
	SPHL
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0xfffd
	DAD	SP
	SPHL
	MVI	A, 0xb
	CALL	use8
	LXI	HL, 2
	DAD	SP
	MOV	D, H
	MOV	E, L
	LXI	HL, 0
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	XCHG
	MVI	A, 0xb
	MOV	M, A
	MVI	A, 3
	CALL	use8
	MVI	A, 6
	LXI	HL, 0
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	MOV	M, A
	MOV	A, M
	MVI	L, 0
	MOV	H, L
	MOV	L, A
	XCHG
	LXI	HL, 3
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.addrsig
