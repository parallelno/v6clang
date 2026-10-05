	.text
	.globl	countdown                       ; -- Begin function countdown
countdown:                              ; @countdown
; %bb.0:
	ORA	A
	JZ	.LBB0_2
.LBB0_1:                                ; =>This Inner Loop Header: Depth=1
	STA	g_port
	DCR	A
	ORA	A
	JNZ	.LBB0_1
.LBB0_2:
	RET
                                        ; -- End function
	.globl	countup                         ; -- Begin function countup
countup:                                ; @countup
; %bb.0:
	LXI	HL, 0xffff
	DAD	SP
	SPHL
	PUSH	HL
	LXI	HL, 2
	DAD	SP
	MOV	M, A
	POP	HL
	ORA	A
	JZ	.LBB1_4
.LBB1_1:                                ; =>This Inner Loop Header: Depth=1
	PUSH	HL
	LXI	HL, 2
	DAD	SP
	MOV	A, M
	POP	HL
	STA	g_port
	INR	A
	LXI	DE, 0
	LXI	HL, 1
	PUSH	HL
	LXI	HL, 2
	DAD	SP
	MOV	M, A
	POP	HL
	ORA	A
	JNZ	.LBB1_3
; %bb.2:                                ;   in Loop: Header=BB1_1 Depth=1
	LXI	DE, 1
.LBB1_3:                                ;   in Loop: Header=BB1_1 Depth=1
	MOV	A, E
	ANA	L
	MOV	L, A
	MOV	A, D
	ANA	H
	MOV	H, A
	MVI	A, 0
	CMP	L
	JNZ	.LBB1_4
; %bb.5:                                ;   in Loop: Header=BB1_1 Depth=1
	MVI	A, 0
	CMP	H
	JZ	.LBB1_1
.LBB1_4:
	LXI	HL, 1
	DAD	SP
	SPHL
	RET
                                        ; -- End function
	.globl	xor_test                        ; -- Begin function xor_test
xor_test:                               ; @xor_test
; %bb.0:
	LXI	BC, 0
	MOV	A, L
	SUB	E
	MOV	A, H
	SBB	D
	JNZ	.LBB2_2
; %bb.1:
	LXI	BC, 1
.LBB2_2:
	LXI	HL, 1
	MOV	A, C
	ANA	L
	MOV	L, A
	MOV	A, B
	ANA	H
	MOV	H, A
	RET
                                        ; -- End function
	.globl	sub_test                        ; -- Begin function sub_test
sub_test:                               ; @sub_test
; %bb.0:
	LXI	BC, 0
	MOV	A, L
	SUB	E
	MOV	A, H
	SBB	D
	JNZ	.LBB3_2
; %bb.1:
	LXI	BC, 1
.LBB3_2:
	LXI	HL, 1
	MOV	A, C
	ANA	L
	MOV	L, A
	MOV	A, B
	ANA	H
	MOV	H, A
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	MVI	A, 5
	STA	g_port
	MVI	A, 4
	STA	g_port
	MVI	A, 3
	STA	g_port
	MVI	A, 2
	STA	g_port
	MVI	A, 1
	STA	g_port
	MVI	A, 0xfffa
	STA	g_port
	MVI	A, 0xfffb
	STA	g_port
	MVI	A, 0xfffc
	STA	g_port
	MVI	A, 0xfffd
	STA	g_port
	MVI	A, 0xfffe
	STA	g_port
	MVI	A, 0xffff
	STA	g_port
	LXI	HL, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_port                          ; @g_port
g_port:
	DB	0                               ; 0x0

	.addrsig
	.addrsig_sym g_port
