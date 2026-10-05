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
	SHLD	__v6clang_ss.sieve_count
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
	SHLD	__v6clang_ss.sieve_count+8
	XCHG
	LXI	D, 5
	XCHG
	SHLD	__v6clang_ss.sieve_count+12
	XCHG
	LXI	D, flags+4
	XCHG
	SHLD	__v6clang_ss.sieve_count+10
	XCHG
	SHLD	__v6clang_ss.sieve_count+6
.LBB15_5:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB15_7 Depth 2
	MOV	L, C
	MOV	H, B
	SHLD	__v6clang_ss.sieve_count+2
	LXI	H, flags
	DAD	B
	MOV	A, M
	ORA	A
	LHLD	__v6clang_ss.sieve_count
	SHLD	__v6clang_ss.sieve_count
	JNZ	.LBB15_10
; %bb.6:                                ; %.preheader
                                        ;   in Loop: Header=BB15_5 Depth=1
	LHLD	__v6clang_ss.sieve_count+10
	XCHG
	LHLD	__v6clang_ss.sieve_count+8
	SHLD	__v6clang_ss.sieve_count+4
	XCHG
.LBB15_7:                               ;   Parent Loop BB15_5 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	PUSH	H
	LXI	H, __v6clang_ss.sieve_count
	MOV	C, M
	INX	H
	MOV	B, M
	POP	H
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
	MOV	A, C
	SUB	E
	MOV	C, A
	MOV	A, B
	SBB	D
	MOV	B, A
	PUSH	H
	LXI	H, __v6clang_ss.sieve_count
	MOV	M, C
	INX	H
	MOV	M, B
	POP	H
	MVI	M, 1
	PUSH	H
	LXI	H, __v6clang_ss.sieve_count+2
	MOV	C, M
	INX	H
	MOV	B, M
	POP	H
	DAD	B
	XCHG
	LHLD	__v6clang_ss.sieve_count+4
	DAD	B
	SHLD	__v6clang_ss.sieve_count+4
	XCHG
	PUSH	H
	LXI	H, __v6clang_ss.sieve_count+6
	MOV	C, M
	INX	H
	MOV	B, M
	POP	H
	MOV	A, E
	SUB	C
	MOV	A, D
	SBB	B
	JC	.LBB15_7
.LBB15_10:                              ;   in Loop: Header=BB15_5 Depth=1
	LHLD	__v6clang_ss.sieve_count
	SHLD	__v6clang_ss.sieve_count
	LHLD	__v6clang_ss.sieve_count+2
	MOV	C, L
	MOV	B, H
	MOV	H, B
	MOV	L, C
	DAD	B
	XCHG
	LHLD	__v6clang_ss.sieve_count+8
	DAD	D
	PUSH	H
	LHLD	__v6clang_ss.sieve_count+12
	XCHG
	LHLD	__v6clang_ss.sieve_count+10
	DAD	D
	SHLD	__v6clang_ss.sieve_count+10
	XCHG
	INX	H
	INX	H
	SHLD	__v6clang_ss.sieve_count+12
	INX	B
	POP	H
	XCHG
	INX	D
	LHLD	__v6clang_ss.sieve_count+6
	XCHG
	SHLD	__v6clang_ss.sieve_count+8
	XCHG
	MOV	A, E
	SUB	L
	MOV	A, D
	SBB	H
	JC	.LBB15_5
.LBB15_12:
	LHLD	__v6clang_ss.sieve_count
	RET
.LBB15_11:
	LXI	H, 0xfffe
	PUSH	H
	POP	H
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
	LXI	H, 2
	LXI	D, 0xc6
	XCHG
	SHLD	__v6clang_ss.main
	XCHG
	LXI	D, 4
	XCHG
	SHLD	__v6clang_ss.main+6
	XCHG
	LXI	B, 5
	LXI	D, flags+4
	XCHG
	SHLD	__v6clang_ss.main+8
	XCHG
.LBB16_3:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB16_5 Depth 2
	SHLD	__v6clang_ss.main+4
	PUSH	H
	LXI	H, __v6clang_ss.main+10
	MOV	M, C
	INX	H
	MOV	M, B
	POP	H
	LXI	D, flags
	DAD	D
	XCHG
	LDAX	D
	ORA	A
	JNZ	.LBB16_8
; %bb.4:                                ; %.preheader
                                        ;   in Loop: Header=BB16_3 Depth=1
	LHLD	__v6clang_ss.main+8
	MOV	C, L
	MOV	B, H
	LHLD	__v6clang_ss.main+6
.LBB16_5:                               ;   Parent Loop BB16_3 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	SHLD	__v6clang_ss.main+2
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
	XCHG
	LHLD	__v6clang_ss.main
	XCHG
	MOV	A, E
	SUB	L
	MOV	E, A
	MOV	A, D
	SBB	H
	MOV	D, A
	XCHG
	SHLD	__v6clang_ss.main
	MVI	A, 1
	STAX	B
	LHLD	__v6clang_ss.main+4
	PUSH	H
	DAD	B
	MOV	B, H
	MOV	C, L
	POP	H
	XCHG
	LHLD	__v6clang_ss.main+2
	DAD	D
	MVI	A, 0xc7
	SUB	L
	MVI	A, 0
	SBB	H
	JNC	.LBB16_5
.LBB16_8:                               ;   in Loop: Header=BB16_3 Depth=1
	LHLD	__v6clang_ss.main+4
	DAD	H
	XCHG
	LHLD	__v6clang_ss.main+6
	DAD	D
	PUSH	H
	LHLD	__v6clang_ss.main+4
	PUSH	H
	LXI	H, __v6clang_ss.main+10
	MOV	C, M
	INX	H
	MOV	B, M
	POP	H
	XCHG
	LHLD	__v6clang_ss.main+8
	DAD	B
	SHLD	__v6clang_ss.main+8
	INX	B
	INX	B
	POP	H
	XCHG
	INX	D
	XCHG
	SHLD	__v6clang_ss.main+6
	XCHG
	INX	H
	MVI	A, 0xf
	CMP	L
	JNZ	.LBB16_3
; %bb.11:                               ;   in Loop: Header=BB16_3 Depth=1
	XRA	A
	CMP	H
	JNZ	.LBB16_3
; %bb.9:
	LXI	H, 0xff
	XCHG
	LHLD	__v6clang_ss.main
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
	.local	__v6clang_ss.sieve_count            ; @__v6clang_ss.sieve_count
	.comm	__v6clang_ss.sieve_count,14,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,12,1
