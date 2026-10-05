	.text
	.section	.text.worker,"ax",@progbits
	.globl	worker                          ; -- Begin function worker
worker:                                 ; @worker
; %bb.0:
	LXI	H, 0xfffb
	DAD	SP
	SPHL
	LXI	H, 4
	DAD	SP
	MOV	M, C
	LXI	H, 0
	DAD	SP
	MOV	M, B
	LXI	H, 3
	DAD	SP
	MOV	M, A
	CALL	ext_fn
	LXI	H, 1
	DAD	SP
	MOV	M, A
	LXI	H, 0
	DAD	SP
	MOV	A, M
	LXI	H, 4
	DAD	SP
	MOV	B, M
	CALL	ext_fn
	MVI	E, 0
	LXI	H, 1
	DAD	SP
	MOV	L, M
	MOV	H, E
	MOV	D, E
	MOV	E, A
	DAD	D
	XCHG
	LXI	H, 1
	DAD	SP
	MOV	M, E
	INX	H
	MOV	M, D
	LXI	H, 3
	DAD	SP
	MOV	A, M
	LXI	H, 4
	DAD	SP
	MOV	B, M
	CALL	ext_fn
	MVI	L, 0
	MOV	H, L
	MOV	L, A
	PUSH	H
	LXI	H, 3
	DAD	SP
	MOV	E, M
	INX	H
	MOV	D, M
	POP	H
	DAD	D
	XCHG
	LXI	H, 5
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	PUSH	PSW
	MVI	A, 1
	MVI	B, 2
	CALL	ext_fn
	LXI	H, 0
	DAD	SP
	MOV	M, A
	MVI	A, 2
	MVI	B, 3
	CALL	ext_fn
	MVI	E, 0
	LXI	H, 0
	DAD	SP
	MOV	L, M
	MOV	H, E
	MOV	D, E
	MOV	E, A
	DAD	D
	XCHG
	LXI	H, 0
	DAD	SP
	MOV	M, E
	INX	H
	MOV	M, D
	MVI	A, 1
	MVI	B, 3
	CALL	ext_fn
	MVI	L, 0
	MOV	H, L
	MOV	L, A
	PUSH	H
	LXI	H, 2
	DAD	SP
	MOV	E, M
	INX	H
	MOV	D, M
	POP	H
	DAD	D
	SHLD	g_sink
	LXI	H, 0
	XCHG
	POP	PSW
	XCHG
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_sink                          ; @g_sink
g_sink:
	DW	0                               ; 0x0

	.addrsig
	.addrsig_sym g_sink
