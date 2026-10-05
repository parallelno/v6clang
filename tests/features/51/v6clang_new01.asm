	.text
	.section	.text.sum_array,"ax",@progbits
	.globl	sum_array                       ; -- Begin function sum_array
sum_array:                              ; @sum_array
; %bb.0:
	ORA	A
	JZ	.LBB0_3
; %bb.1:
	LXI	D, 0
.LBB0_2:                                ; =>This Inner Loop Header: Depth=1
	XCHG
	SHLD	.LLo61_1+1
	XCHG
	SHLD	.LLo61_0+1
	STA	.LLo61_2+1
.LLo61_0:
	LXI	H, 0
	MOV	A, M
	INX	H
	MOV	H, M
	MOV	L, A
	LXI	D, 3
	CALL	__mulhi3
.LLo61_1:
	LXI	D, 0
	DAD	D
	LXI	D, 7
	DAD	D
	XCHG
	LHLD	.LLo61_0+1
.LLo61_2:
	MVI	A, 0
	INX	H
	INX	H
	DCR	A
	JNZ	.LBB0_2
; %bb.4:
	XCHG
	RET
.LBB0_3:
	LXI	D, 0
	XCHG
	RET
                                        ; -- End function
	.section	.text.poly,"ax",@progbits
	.globl	poly                            ; -- Begin function poly
poly:                                   ; @poly
; %bb.0:
	ORA	A
	JZ	.LBB1_3
; %bb.1:
	LXI	D, 0
.LBB1_2:                                ; =>This Inner Loop Header: Depth=1
	XCHG
	SHLD	.LLo61_3+1
	XCHG
	SHLD	.LLo61_4+1
	STA	.LLo61_6+1
	MOV	A, M
	INX	H
	MOV	H, M
	MOV	L, A
	SHLD	.LLo61_5+1
	LXI	D, 5
	CALL	__mulhi3
.LLo61_5:
	LXI	D, 0
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
.LLo61_3:
	LXI	B, 0
	XCHG
	DAD	B
	XCHG
	INX	D
	INX	D
	INX	D
	DAD	D
	XCHG
.LLo61_4:
	LXI	H, 0
.LLo61_6:
	MVI	A, 0
	INX	H
	INX	H
	DCR	A
	JNZ	.LBB1_2
; %bb.4:
	XCHG
	RET
.LBB1_3:
	LXI	D, 0
	XCHG
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
