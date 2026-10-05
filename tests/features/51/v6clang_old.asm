	.text
	.section	.text.sum_array,"ax",@progbits
	.globl	sum_array                       ; -- Begin function sum_array
sum_array:                              ; @sum_array
; %bb.0:
	XCHG
	ORA	A
	JZ	.LBB0_3
; %bb.1:
	MVI	L, 0
	MOV	B, L
	MOV	C, A
	LXI	H, 0
.LBB0_2:                                ; =>This Inner Loop Header: Depth=1
	SHLD	.LLo61_2+1
	PUSH	H
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_3+1
	POP	H
	XCHG
	SHLD	.LLo61_0+1
	SHLD	.LLo61_1+1
	MOV	A, M
	INX	H
	MOV	H, M
	MOV	L, A
	XCHG
	LXI	D, 3
	CALL	__mulhi3
.LLo61_3:
	LXI	B, 0
.LLo61_0:
	LXI	D, 0
.LLo61_2:
	LXI	D, 0
	DAD	D
	LXI	D, 7
	DAD	D
.LLo61_1:
	LXI	D, 0
	INX	D
	INX	D
	DCX	B
	MOV	A, B
	ORA	C
	JNZ	.LBB0_2
; %bb.4:
	RET
.LBB0_3:
	LXI	H, 0
	RET
                                        ; -- End function
	.section	.text.poly,"ax",@progbits
	.globl	poly                            ; -- Begin function poly
poly:                                   ; @poly
; %bb.0:
	ORA	A
	JZ	.LBB1_3
; %bb.1:
	MVI	E, 0
	MOV	D, E
	MOV	E, A
	LXI	B, 0
.LBB1_2:                                ; =>This Inner Loop Header: Depth=1
	PUSH	H
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_5+1
	POP	H
	XCHG
	SHLD	.LLo61_6+1
	XCHG
	SHLD	.LLo61_4+1
	MOV	A, M
	INX	H
	MOV	H, M
	MOV	L, A
	SHLD	.LLo61_7+1
	LXI	D, 5
	CALL	__mulhi3
.LLo61_7:
	LXI	D, 0
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
.LLo61_5:
	LXI	B, 0
	XCHG
	DAD	B
	XCHG
	INX	D
	INX	D
	INX	D
	DAD	D
	MOV	B, H
	MOV	C, L
.LLo61_6:
	LXI	D, 0
.LLo61_4:
	LXI	H, 0
	INX	H
	INX	H
	DCX	D
	MOV	A, D
	ORA	E
	JNZ	.LBB1_2
	JMP	.LBB1_4
.LBB1_3:
	LXI	B, 0
.LBB1_4:
	MOV	H, B
	MOV	L, C
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	H, 8
	SHLD	g_arr+14
	DCX	H
	SHLD	g_arr+12
	DCX	H
	SHLD	g_arr+10
	DCX	H
	SHLD	g_arr+8
	DCX	H
	SHLD	g_arr+6
	DCX	H
	SHLD	g_arr+4
	DCX	H
	SHLD	g_arr+2
	DCX	H
	SHLD	g_arr
	LXI	H, 0x180
	JMP	ext_sink16
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_arr                           ; @g_arr
	.p2align	1, 0x0
g_arr:

	.addrsig
