	.text
	.globl	sieve_count                     ; -- Begin function sieve_count
sieve_count:                            ; @sieve_count
; %bb.0:
	MOV	A, H
	ORA	L
	JZ	.LBB15_11
; %bb.1:                                ; %.preheader3
	LXI	B, flags
	LXI	D, 0
.LBB15_2:                               ; =>This Inner Loop Header: Depth=1
	XRA	A
	STAX	B
	INX	B
	INX	D
	MOV	A, E
	SUB	L
	MOV	A, D
	SBB	H
	JC	.LBB15_2
; %bb.3:
	MOV	D, H
	MOV	E, L
	DCX	D
	DCX	D
	XCHG
	SHLD	.LLo61_1+1
	XCHG
	MVI	A, 4
	SUB	L
	MVI	A, 0
	SBB	H
	JNC	.LBB15_12
; %bb.4:                                ; %.preheader1
	LXI	B, 2
	LXI	D, 4
	XCHG
	SHLD	.LLo61_2+1
	XCHG
	LXI	D, 5
	XCHG
	SHLD	.LLo61_3+1
	XCHG
	LXI	D, flags+4
	XCHG
	SHLD	.LLo61_6+1
	XCHG
	SHLD	.LLo61_5+1
.LBB15_5:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB15_7 Depth 2
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_0+1
	LXI	H, flags
	DAD	B
	MOV	A, M
	ORA	A
	JNZ	.LBB15_10
; %bb.6:                                ; %.preheader
                                        ;   in Loop: Header=BB15_5 Depth=1
	LHLD	.LLo61_6+1
	XCHG
	LHLD	.LLo61_2+1
	SHLD	.LLo61_4+1
	XCHG
.LBB15_7:                               ;   Parent Loop BB15_5 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
.LLo61_0:
	LXI	D, 0
	MOV	A, M
	ORA	A
	MVI	E, 0
	MOV	A, E
	JNZ	.LBB15_9
; %bb.8:                                ;   in Loop: Header=BB15_7 Depth=2
	MVI	A, 1
.LBB15_9:                               ;   in Loop: Header=BB15_7 Depth=2
	MOV	D, E
	MOV	E, A
.LLo61_1:
	LXI	B, 0
	MOV	A, C
	SUB	E
	MOV	C, A
	MOV	A, B
	SBB	D
	PUSH	H
	MOV	L, C
	MOV	H, A
	SHLD	.LLo61_1+1
	POP	H
	MVI	M, 1
	XCHG
	LHLD	.LLo61_0+1
	XCHG
	DAD	D
.LLo61_4:
	LXI	B, 0
	MOV	A, C
	ADD	E
	MOV	C, A
	MOV	A, B
	ADC	D
	MOV	B, A
.LLo61_5:
	LXI	D, 0
	PUSH	H
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_4+1
	POP	H
	MOV	A, C
	SUB	E
	MOV	A, B
	SBB	D
	JC	.LBB15_7
.LBB15_10:                              ;   in Loop: Header=BB15_5 Depth=1
	LHLD	.LLo61_0+1
	DAD	H
.LLo61_2:
	LXI	B, 0
	DAD	B
	MOV	B, H
	MOV	C, L
.LLo61_3:
	LXI	H, 0
.LLo61_6:
	LXI	D, 0
	XCHG
	DAD	D
	SHLD	.LLo61_6+1
	XCHG
	INX	H
	INX	H
	SHLD	.LLo61_3+1
	LHLD	.LLo61_0+1
	INX	H
	SHLD	.LLo61_0+1
	MOV	D, B
	MOV	E, C
	INX	D
	LHLD	.LLo61_5+1
	XCHG
	SHLD	.LLo61_2+1
	XCHG
	PUSH	H
	LHLD	.LLo61_0+1
	MOV	C, L
	MOV	B, H
	POP	H
	MOV	A, E
	SUB	L
	MOV	A, D
	SBB	H
	JC	.LBB15_5
.LBB15_12:
	LHLD	.LLo61_1+1
	RET
.LBB15_11:
	LXI	H, 0xfffe
	SHLD	.LLo61_1+1
	LHLD	.LLo61_1+1
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	H, flags
.LBB16_1:                               ; =>This Inner Loop Header: Depth=1
	MVI	M, 0
	INX	H
	MVI	A, <(flags+200)
	CMP	L
	JNZ	.LBB16_1
; %bb.10:                               ;   in Loop: Header=BB16_1 Depth=1
	MVI	A, >(flags+200)
	CMP	H
	JNZ	.LBB16_1
; %bb.2:                                ; %.preheader1
	LXI	D, 2
	LXI	H, 0xc6
	SHLD	.LLo61_7+1
	LXI	H, 4
	SHLD	.LLo61_12+1
	INX	H
	LXI	B, flags+4
	PUSH	H
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_10+1
	POP	H
.LBB16_3:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB16_5 Depth 2
	SHLD	.LLo61_13+1
	XCHG
	SHLD	.LLo61_8+1
	SHLD	.LLo61_9+1
	LHLD	.LLo61_8+1
	LXI	D, flags
	DAD	D
	XCHG
	LDAX	D
.LLo61_9:
	LXI	D, 0
	ORA	A
	JNZ	.LBB16_8
; %bb.4:                                ; %.preheader
                                        ;   in Loop: Header=BB16_3 Depth=1
	LHLD	.LLo61_10+1
	MOV	C, L
	MOV	B, H
	LHLD	.LLo61_12+1
.LBB16_5:                               ;   Parent Loop BB16_3 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	SHLD	.LLo61_11+1
	LDAX	B
	ORA	A
	MVI	L, 0
	MOV	A, L
	JNZ	.LBB16_7
; %bb.6:                                ;   in Loop: Header=BB16_5 Depth=2
	MVI	A, 1
.LBB16_7:                               ;   in Loop: Header=BB16_5 Depth=2
	MOV	H, L
	MOV	L, A
.LLo61_7:
	LXI	D, 0
	MOV	A, E
	SUB	L
	MOV	E, A
	MOV	A, D
	SBB	H
	MOV	D, A
	XCHG
	SHLD	.LLo61_7+1
	MVI	A, 1
	STAX	B
.LLo61_8:
	LXI	D, 0
	MOV	A, C
	ADD	E
	MOV	C, A
	MOV	A, B
	ADC	D
	MOV	B, A
.LLo61_11:
	LXI	H, 0
	DAD	D
	MVI	A, 0xc7
	SUB	L
	MVI	A, 0
	SBB	H
	JNC	.LBB16_5
.LBB16_8:                               ;   in Loop: Header=BB16_3 Depth=1
	MOV	H, D
	MOV	L, E
	DAD	D
.LLo61_12:
	LXI	B, 0
	DAD	B
	MOV	B, H
	MOV	C, L
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_12+1
.LLo61_13:
	LXI	H, 0
.LLo61_10:
	LXI	B, 0
	PUSH	H
	DAD	B
	MOV	B, H
	MOV	C, L
	POP	H
	PUSH	H
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_10+1
	POP	H
	INX	H
	INX	H
	PUSH	H
	LHLD	.LLo61_12+1
	MOV	C, L
	MOV	B, H
	POP	H
	INX	B
	PUSH	H
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_12+1
	POP	H
	INX	D
	MVI	A, 0xf
	CMP	E
	JNZ	.LBB16_3
; %bb.11:                               ;   in Loop: Header=BB16_3 Depth=1
	XRA	A
	CMP	D
	JNZ	.LBB16_3
; %bb.9:
	LXI	H, 0xff
	XCHG
	LHLD	.LLo61_7+1
	XCHG
	MOV	A, E
	ANA	L
	MOV	L, A
	MOV	A, D
	ANA	H
	MOV	H, A
	MOV	E, D
	MVI	D, 0
	MOV	A, L
	XRA	E
	MOV	L, A
	MOV	A, H
	XRA	D
	MOV	H, A
	RET
                                        ; -- End function
	.local	flags                           ; @flags
	.comm	flags,200,1
