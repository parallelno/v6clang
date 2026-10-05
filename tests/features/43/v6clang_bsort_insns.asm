	.text
	.globl	bsort                           ; -- Begin function bsort
bsort:                                  ; @bsort
; %bb.0:
	SHLD	__v6clang_ss.bsort+12
	MVI	A, 1
	SUB	E
	MVI	A, 0
	SBB	D
	RP
.LBB0_1:
	DCX	DE
	LXI	HL, 0
	XCHG
	SHLD	__v6clang_ss.bsort+6
	SHLD	__v6clang_ss.bsort+10
	XCHG
.LBB0_2:                                ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB0_6 Depth 2
	SHLD	__v6clang_ss.bsort+8
	MOV	A, L
	SUB	E
	MOV	A, H
	SBB	D
	JP	.LBB0_4
; %bb.5:                                ;   in Loop: Header=BB0_2 Depth=1
	LHLD	__v6clang_ss.bsort+12
	MOV	C, L
	MOV	B, H
	PUSH	HL
	MOV	H, B
	MOV	L, C
	MOV	A, M
	INX	HL
	MOV	H, M
	MOV	L, A
	POP	HL
	SHLD	__v6clang_ss.bsort
	LHLD	__v6clang_ss.bsort+6
	XCHG
	MOV	L, C
	MOV	H, B
	SHLD	__v6clang_ss.bsort+4
	JMP	.LBB0_6
.LBB0_8:                                ;   in Loop: Header=BB0_6 Depth=2
	DCX	DE
	PUSH	HL
	LXI	HL, __v6clang_ss.bsort+2
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	PUSH	HL
	LXI	HL, __v6clang_ss.bsort+4
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	SHLD	__v6clang_ss.bsort
	MOV	A, D
	ORA	E
	JZ	.LBB0_4
.LBB0_6:                                ;   Parent Loop BB0_2 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	INX	BC
	INX	BC
	MOV	L, C
	MOV	H, B
	SHLD	__v6clang_ss.bsort+2
	PUSH	HL
	MOV	H, B
	MOV	L, C
	MOV	A, M
	INX	HL
	MOV	H, M
	MOV	L, A
	POP	HL
	PUSH	HL
	LXI	HL, __v6clang_ss.bsort
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	MOV	A, L
	SUB	C
	MOV	A, H
	SBB	B
	JP	.LBB0_8
; %bb.7:                                ;   in Loop: Header=BB0_6 Depth=2
	PUSH	HL
	LXI	HL, __v6clang_ss.bsort+4
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	PUSH	BC
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	BC
	INX	BC
	INX	BC
	LHLD	__v6clang_ss.bsort
	PUSH	HL
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	HL
	JMP	.LBB0_8
.LBB0_4:                                ;   in Loop: Header=BB0_2 Depth=1
	LHLD	__v6clang_ss.bsort+6
	DCX	HL
	SHLD	__v6clang_ss.bsort+6
	LHLD	__v6clang_ss.bsort+8
	INX	HL
	XCHG
	LHLD	__v6clang_ss.bsort+10
	XCHG
	MOV	A, L
	CMP	E
	JNZ	.LBB0_2
; %bb.9:                                ;   in Loop: Header=BB0_2 Depth=1
	MOV	A, H
	CMP	D
	JNZ	.LBB0_2
; %bb.3:
	RET
                                        ; -- End function
	.globl	bsort_two                       ; -- Begin function bsort_two
bsort_two:                              ; @bsort_two
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.bsort_two+18
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	XCHG
	SHLD	__v6clang_ss.bsort_two+20
	XCHG
	SHLD	__v6clang_ss.bsort_two+22
	LXI	HL, 0
	DAD	SP
	MOV	A, M
	INX	HL
	MOV	H, M
	MOV	L, A
	XCHG
	MVI	A, 1
	SUB	L
	MVI	A, 0
	SBB	H
	RP
.LBB1_1:
	DCX	HL
	LXI	DE, 0
	SHLD	__v6clang_ss.bsort_two+12
	SHLD	__v6clang_ss.bsort_two+16
.LBB1_2:                                ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB1_6 Depth 2
	XCHG
	SHLD	__v6clang_ss.bsort_two+14
	XCHG
	MOV	A, E
	SUB	L
	MOV	A, D
	SBB	H
	JP	.LBB1_4
; %bb.5:                                ;   in Loop: Header=BB1_2 Depth=1
	LHLD	__v6clang_ss.bsort_two+12
	XCHG
	LHLD	__v6clang_ss.bsort_two+22
	SHLD	__v6clang_ss.bsort_two
	SHLD	__v6clang_ss.bsort_two+2
	LHLD	__v6clang_ss.bsort_two+20
	XCHG
	PUSH	HL
	LXI	HL, __v6clang_ss.bsort_two+18
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	JMP	.LBB1_6
.LBB1_10:                               ;   in Loop: Header=BB1_6 Depth=2
	LHLD	__v6clang_ss.bsort_two
	MOV	B, D
	MOV	C, E
	MOV	M, C
	INX	HL
	MOV	M, B
	LHLD	__v6clang_ss.bsort_two+2
	XCHG
	LHLD	__v6clang_ss.bsort_two+10
	XCHG
	MOV	M, E
	INX	HL
	MOV	M, D
	LHLD	__v6clang_ss.bsort_two+8
	XCHG
	MOV	H, D
	MOV	L, E
	MOV	M, C
	INX	HL
	MOV	M, B
	LHLD	__v6clang_ss.bsort_two+6
	MOV	C, L
	MOV	B, H
	MOV	L, E
	MOV	H, D
	PUSH	BC
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	BC
	INX	BC
	INX	BC
	INX	DE
	INX	DE
	LHLD	__v6clang_ss.bsort_two
	INX	HL
	INX	HL
	SHLD	__v6clang_ss.bsort_two
	LHLD	__v6clang_ss.bsort_two+4
	DCX	HL
	MOV	A, H
	ORA	L
	JZ	.LBB1_4
.LBB1_6:                                ;   Parent Loop BB1_2 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	XCHG
	SHLD	__v6clang_ss.bsort_two+8
	XCHG
	PUSH	HL
	LXI	HL, __v6clang_ss.bsort_two+6
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	SHLD	__v6clang_ss.bsort_two+4
	LHLD	__v6clang_ss.bsort_two+2
	INX	HL
	INX	HL
	PUSH	HL
	LXI	HL, __v6clang_ss.bsort_two
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	PUSH	HL
	MOV	H, B
	MOV	L, C
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	SHLD	__v6clang_ss.bsort_two+2
	MOV	A, M
	INX	HL
	MOV	H, M
	MOV	L, A
	MOV	A, L
	SUB	C
	MOV	A, H
	SBB	B
	MOV	D, H
	MOV	E, L
	JP	.LBB1_8
; %bb.7:                                ;   in Loop: Header=BB1_6 Depth=2
	MOV	D, B
	MOV	E, C
.LBB1_8:                                ;   in Loop: Header=BB1_6 Depth=2
	XCHG
	SHLD	__v6clang_ss.bsort_two+10
	XCHG
	MOV	A, C
	SUB	L
	MOV	A, B
	SBB	H
	XCHG
	LHLD	__v6clang_ss.bsort_two+4
	LHLD	__v6clang_ss.bsort_two+8
	LHLD	__v6clang_ss.bsort_two+6
	JP	.LBB1_10
; %bb.9:                                ;   in Loop: Header=BB1_6 Depth=2
	MOV	D, B
	MOV	E, C
	JMP	.LBB1_10
.LBB1_4:                                ;   in Loop: Header=BB1_2 Depth=1
	LHLD	__v6clang_ss.bsort_two+12
	DCX	HL
	SHLD	__v6clang_ss.bsort_two+12
	LHLD	__v6clang_ss.bsort_two+14
	XCHG
	INX	DE
	LHLD	__v6clang_ss.bsort_two+16
	MOV	A, E
	CMP	L
	JNZ	.LBB1_2
; %bb.11:                               ;   in Loop: Header=BB1_2 Depth=1
	MOV	A, D
	CMP	H
	JNZ	.LBB1_2
; %bb.3:
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0
	LXI	BC, 0xf
.LBB2_1:                                ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB2_2 Depth 2
	SHLD	__v6clang_ss.main+6
	LXI	HL, ARR
	SHLD	__v6clang_ss.main
	LHLD	ARR
	SHLD	__v6clang_ss.main+2
	MOV	L, C
	MOV	H, B
	SHLD	__v6clang_ss.main+8
	LXI	HL, ARR
	JMP	.LBB2_2
.LBB2_5:                                ;   in Loop: Header=BB2_2 Depth=2
	DCX	BC
	LHLD	__v6clang_ss.main+4
	SHLD	__v6clang_ss.main
	XCHG
	SHLD	__v6clang_ss.main+2
	XCHG
	MOV	A, B
	ORA	C
	JZ	.LBB2_3
.LBB2_2:                                ;   Parent Loop BB2_1 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	INX	HL
	INX	HL
	SHLD	__v6clang_ss.main+4
	MOV	E, M
	INX	HL
	MOV	D, M
	LHLD	__v6clang_ss.main+2
	MOV	A, E
	SUB	L
	MOV	A, D
	SBB	H
	JP	.LBB2_5
; %bb.4:                                ;   in Loop: Header=BB2_2 Depth=2
	LHLD	__v6clang_ss.main
	PUSH	HL
	MOV	M, E
	INX	HL
	MOV	M, D
	POP	HL
	INX	HL
	INX	HL
	XCHG
	LHLD	__v6clang_ss.main+2
	XCHG
	MOV	M, E
	INX	HL
	MOV	M, D
	JMP	.LBB2_5
.LBB2_3:                                ;   in Loop: Header=BB2_1 Depth=1
	LHLD	__v6clang_ss.main+8
	MOV	C, L
	MOV	B, H
	DCX	BC
	LHLD	__v6clang_ss.main+6
	INX	HL
	MVI	A, 0xf
	CMP	L
	JNZ	.LBB2_1
; %bb.15:                               ;   in Loop: Header=BB2_1 Depth=1
	MVI	A, 0
	CMP	H
	JNZ	.LBB2_1
; %bb.6:
	LXI	HL, 0
	LXI	DE, 0x1e
	XCHG
	SHLD	__v6clang_ss.main+14
	XCHG
.LBB2_7:                                ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB2_8 Depth 2
	SHLD	__v6clang_ss.main+16
	LXI	HL, OUT_HI
	SHLD	__v6clang_ss.main+6
	LXI	HL, OUT_LO
	SHLD	__v6clang_ss.main+2
	LXI	BC, ARR
	LHLD	ARR
	SHLD	__v6clang_ss.main+10
	LXI	HL, 0
	LXI	DE, ARR
	XCHG
	SHLD	__v6clang_ss.main+4
	XCHG
.LBB2_8:                                ;   Parent Loop BB2_7 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	SHLD	__v6clang_ss.main+8
	MOV	L, C
	MOV	H, B
	SHLD	__v6clang_ss.main+12
	LHLD	__v6clang_ss.main+2
	SHLD	__v6clang_ss.main+2
	PUSH	HL
	LXI	HL, __v6clang_ss.main+6
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	XCHG
	LHLD	__v6clang_ss.main+4
	XCHG
	INX	DE
	INX	DE
	XCHG
	SHLD	__v6clang_ss.main+4
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	LHLD	__v6clang_ss.main+10
	MOV	A, E
	SUB	L
	MOV	A, D
	SBB	H
	XCHG
	SHLD	__v6clang_ss.main
	XCHG
	JP	.LBB2_10
; %bb.9:                                ;   in Loop: Header=BB2_8 Depth=2
	SHLD	__v6clang_ss.main
.LBB2_10:                               ;   in Loop: Header=BB2_8 Depth=2
	MOV	A, L
	SUB	E
	MOV	A, H
	SBB	D
	MOV	L, C
	MOV	H, B
	SHLD	__v6clang_ss.main+6
	LHLD	__v6clang_ss.main+2
	LHLD	__v6clang_ss.main+12
	MOV	C, L
	MOV	B, H
	LHLD	__v6clang_ss.main+8
	JP	.LBB2_12
; %bb.11:                               ;   in Loop: Header=BB2_8 Depth=2
	LHLD	__v6clang_ss.main+10
	XCHG
.LBB2_12:                               ;   in Loop: Header=BB2_8 Depth=2
	XCHG
	SHLD	__v6clang_ss.main+10
	XCHG
	MOV	H, B
	MOV	L, C
	MOV	M, E
	INX	HL
	MOV	M, D
	LHLD	__v6clang_ss.main+4
	LHLD	__v6clang_ss.main
	SHLD	__v6clang_ss.main
	MOV	E, L
	MOV	D, H
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LHLD	__v6clang_ss.main+2
	XCHG
	MOV	L, E
	MOV	H, D
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LHLD	__v6clang_ss.main+6
	XCHG
	LHLD	__v6clang_ss.main
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	INX	DE
	INX	DE
	XCHG
	SHLD	__v6clang_ss.main+6
	LHLD	__v6clang_ss.main+2
	INX	HL
	INX	HL
	SHLD	__v6clang_ss.main+2
	INX	BC
	INX	BC
	LHLD	__v6clang_ss.main+8
	INX	HL
	INX	HL
	XCHG
	LHLD	__v6clang_ss.main
	SHLD	__v6clang_ss.main+10
	LHLD	__v6clang_ss.main+14
	XCHG
	MOV	A, E
	CMP	L
	JNZ	.LBB2_8
; %bb.16:                               ;   in Loop: Header=BB2_8 Depth=2
	MOV	A, D
	CMP	H
	JNZ	.LBB2_8
; %bb.14:                               ;   in Loop: Header=BB2_7 Depth=1
	LHLD	__v6clang_ss.main+14
	DCX	HL
	DCX	HL
	SHLD	__v6clang_ss.main+14
	LHLD	__v6clang_ss.main+16
	INX	HL
	MVI	A, 0xf
	CMP	L
	JNZ	.LBB2_7
; %bb.17:                               ;   in Loop: Header=BB2_7 Depth=1
	MVI	A, 0
	CMP	H
	JNZ	.LBB2_7
; %bb.13:
	LHLD	ARR
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	ARR                             ; @ARR
ARR:

	.globl	OUT_LO                          ; @OUT_LO
OUT_LO:

	.globl	OUT_HI                          ; @OUT_HI
OUT_HI:

	.local	__v6clang_ss.bsort                  ; @__v6clang_ss.bsort
	.comm	__v6clang_ss.bsort,14,1
	.local	__v6clang_ss.bsort_two              ; @__v6clang_ss.bsort_two
	.comm	__v6clang_ss.bsort_two,24,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,18,1
	.addrsig
