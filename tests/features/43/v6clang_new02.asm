	.text
	.globl	axpy3                           ; -- Begin function axpy3
axpy3:                                  ; @axpy3
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.axpy3+4
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	XCHG
	SHLD	__v6clang_ss.axpy3+6
	XCHG
	SHLD	__v6clang_ss.axpy3+2
	LXI	HL, 0
	DAD	SP
	XCHG
	LXI	HL, 0
	DAD	SP
	MOV	B, H
	MOV	C, L
	LHLD	__v6clang_ss.axpy3+4
	PUSH	HL
	MOV	H, B
	MOV	L, C
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	MOV	A, B
	ORA	C
	RZ
.LBB0_1:
	XCHG
	MOV	E, M
	INX	HL
	MOV	D, M
	SHLD	__v6clang_ss.axpy3
	XCHG
.LBB0_2:                                ; =>This Inner Loop Header: Depth=1
	PUSH	HL
	LXI	HL, __v6clang_ss.axpy3+8
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	SHLD	__v6clang_ss.axpy3+4
	LHLD	__v6clang_ss.axpy3+6
	MOV	C, L
	MOV	B, H
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	LHLD	__v6clang_ss.axpy3+4
	MOV	A, M
	INX	HL
	MOV	H, M
	MOV	L, A
	DAD	DE
	XCHG
	LHLD	__v6clang_ss.axpy3
	MOV	A, M
	INX	HL
	MOV	H, M
	MOV	L, A
	DAD	DE
	XCHG
	LHLD	__v6clang_ss.axpy3+2
	XCHG
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LHLD	__v6clang_ss.axpy3+4
	INX	BC
	INX	BC
	PUSH	HL
	LXI	HL, __v6clang_ss.axpy3+6
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	PUSH	HL
	LXI	HL, __v6clang_ss.axpy3+8
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	INX	HL
	INX	HL
	XCHG
	LHLD	__v6clang_ss.axpy3
	XCHG
	INX	DE
	INX	DE
	XCHG
	SHLD	__v6clang_ss.axpy3
	LHLD	__v6clang_ss.axpy3+2
	XCHG
	INX	DE
	INX	DE
	XCHG
	SHLD	__v6clang_ss.axpy3+2
	XCHG
	DCX	BC
	MOV	A, B
	ORA	C
	JNZ	.LBB0_2
; %bb.3:
	RET
                                        ; -- End function
	.globl	dot                             ; -- Begin function dot
dot:                                    ; @dot
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.dot+2
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	MOV	A, B
	ORA	C
	JZ	.LBB1_3
; %bb.1:
	PUSH	HL
	LXI	HL, __v6clang_ss.dot+2
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	PUSH	HL
	LXI	HL, __v6clang_ss.dot
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	LXI	BC, 0
	PUSH	HL
	LXI	HL, __v6clang_ss.dot+2
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
.LBB1_2:                                ; =>This Inner Loop Header: Depth=1
	SHLD	__v6clang_ss.dot+4
	XCHG
	PUSH	HL
	XCHG
	LHLD	__v6clang_ss.dot+2
	SHLD	__v6clang_ss.dot+2
	XCHG
	MOV	A, M
	INX	HL
	MOV	H, M
	MOV	L, A
	LHLD	__v6clang_ss.dot+4
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	CALL	__mulhi3
	XCHG
	POP	HL
	XCHG
	PUSH	HL
	LXI	HL, __v6clang_ss.dot+2
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	DAD	BC
	MOV	B, H
	MOV	C, L
	MOV	L, C
	MOV	H, B
	SHLD	__v6clang_ss.dot+2
	LHLD	__v6clang_ss.dot+4
	INX	HL
	INX	HL
	INX	DE
	INX	DE
	PUSH	HL
	LXI	HL, __v6clang_ss.dot
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	PUSH	HL
	LXI	HL, __v6clang_ss.dot
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	DCX	BC
	PUSH	HL
	LXI	HL, __v6clang_ss.dot
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	MOV	A, B
	ORA	C
	JNZ	.LBB1_2
.LBB1_3:
	LHLD	__v6clang_ss.dot+2
	RET
                                        ; -- End function
	.globl	scale_copy                      ; -- Begin function scale_copy
scale_copy:                             ; @scale_copy
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.scale_copy
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	MOV	B, H
	MOV	C, L
	LHLD	__v6clang_ss.scale_copy
	MOV	A, H
	ORA	L
	RZ
.LBB2_1:                                ; =>This Inner Loop Header: Depth=1
	PUSH	HL
	XCHG
	MOV	A, M
	INX	HL
	MOV	H, M
	MOV	L, A
	XCHG
	DAD	HL
	PUSH	BC
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	BC
	POP	HL
	INX	DE
	INX	DE
	INX	BC
	INX	BC
	DCX	HL
	MOV	A, H
	ORA	L
	JNZ	.LBB2_1
; %bb.2:
	RET
                                        ; -- End function
	.globl	seed                            ; -- Begin function seed
seed:                                   ; @seed
; %bb.0:
	LXI	HL, D2
	SHLD	__v6clang_ss.seed+4
	LXI	HL, D1
	SHLD	__v6clang_ss.seed+6
	LXI	HL, C
	SHLD	__v6clang_ss.seed+2
	LXI	HL, B
	SHLD	__v6clang_ss.seed
	LXI	HL, A
	LXI	DE, 0
	LXI	BC, 0
.LBB3_1:                                ; =>This Inner Loop Header: Depth=1
	PUSH	HL
	MOV	M, E
	INX	HL
	MOV	M, D
	INX	BC
	LHLD	__v6clang_ss.seed
	SHLD	__v6clang_ss.seed
	MOV	M, C
	INX	HL
	MOV	M, B
	INX	DE
	INX	DE
	LHLD	__v6clang_ss.seed+2
	SHLD	__v6clang_ss.seed+2
	MOV	M, E
	INX	HL
	MOV	M, D
	LXI	DE, 0
	LHLD	__v6clang_ss.seed+6
	MOV	M, E
	INX	HL
	MOV	M, D
	LHLD	__v6clang_ss.seed+4
	MOV	M, E
	INX	HL
	MOV	M, D
	POP	HL
	INX	HL
	INX	HL
	XCHG
	LHLD	__v6clang_ss.seed
	XCHG
	INX	DE
	INX	DE
	XCHG
	SHLD	__v6clang_ss.seed
	LHLD	__v6clang_ss.seed+2
	XCHG
	INX	DE
	INX	DE
	XCHG
	SHLD	__v6clang_ss.seed+2
	LHLD	__v6clang_ss.seed+6
	XCHG
	INX	DE
	INX	DE
	XCHG
	SHLD	__v6clang_ss.seed+6
	LHLD	__v6clang_ss.seed+4
	XCHG
	INX	DE
	INX	DE
	XCHG
	SHLD	__v6clang_ss.seed+4
	XCHG
	MOV	D, B
	MOV	E, C
	MVI	A, 8
	CMP	C
	JNZ	.LBB3_1
; %bb.3:                                ;   in Loop: Header=BB3_1 Depth=1
	MVI	A, 0
	CMP	B
	JNZ	.LBB3_1
; %bb.2:
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, D2
	SHLD	__v6clang_ss.main+4
	LXI	HL, D1
	SHLD	__v6clang_ss.main+6
	LXI	HL, C
	SHLD	__v6clang_ss.main+2
	LXI	HL, B
	SHLD	__v6clang_ss.main
	LXI	HL, A
	LXI	DE, 0
	LXI	BC, 0
.LBB4_1:                                ; =>This Inner Loop Header: Depth=1
	PUSH	HL
	MOV	M, E
	INX	HL
	MOV	M, D
	INX	BC
	LHLD	__v6clang_ss.main
	SHLD	__v6clang_ss.main
	MOV	M, C
	INX	HL
	MOV	M, B
	INX	DE
	INX	DE
	LHLD	__v6clang_ss.main+2
	SHLD	__v6clang_ss.main+2
	MOV	M, E
	INX	HL
	MOV	M, D
	LXI	DE, 0
	LHLD	__v6clang_ss.main+6
	MOV	M, E
	INX	HL
	MOV	M, D
	LHLD	__v6clang_ss.main+4
	MOV	M, E
	INX	HL
	MOV	M, D
	POP	HL
	INX	HL
	INX	HL
	XCHG
	LHLD	__v6clang_ss.main
	XCHG
	INX	DE
	INX	DE
	XCHG
	SHLD	__v6clang_ss.main
	LHLD	__v6clang_ss.main+2
	XCHG
	INX	DE
	INX	DE
	XCHG
	SHLD	__v6clang_ss.main+2
	LHLD	__v6clang_ss.main+6
	XCHG
	INX	DE
	INX	DE
	XCHG
	SHLD	__v6clang_ss.main+6
	LHLD	__v6clang_ss.main+4
	XCHG
	INX	DE
	INX	DE
	XCHG
	SHLD	__v6clang_ss.main+4
	XCHG
	MOV	D, B
	MOV	E, C
	MVI	A, 8
	CMP	C
	JNZ	.LBB4_1
; %bb.9:                                ;   in Loop: Header=BB4_1 Depth=1
	MVI	A, 0
	CMP	B
	JNZ	.LBB4_1
; %bb.2:
	LXI	HL, OUT
	SHLD	__v6clang_ss.main+2
	LXI	DE, C
	LXI	HL, B
	LXI	BC, A
.LBB4_3:                                ; =>This Inner Loop Header: Depth=1
	PUSH	HL
	LXI	HL, __v6clang_ss.main+8
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	SHLD	__v6clang_ss.main
	XCHG
	PUSH	HL
	XCHG
	PUSH	HL
	MOV	H, B
	MOV	L, C
	MOV	A, M
	INX	HL
	MOV	H, M
	MOV	L, A
	POP	HL
	SHLD	__v6clang_ss.main+6
	LHLD	__v6clang_ss.main
	MOV	A, M
	INX	HL
	MOV	H, M
	MOV	L, A
	PUSH	HL
	LXI	HL, __v6clang_ss.main+6
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	DAD	BC
	PUSH	HL
	XCHG
	MOV	A, M
	INX	HL
	MOV	H, M
	MOV	L, A
	POP	HL
	XCHG
	DAD	DE
	XCHG
	LHLD	__v6clang_ss.main+2
	XCHG
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LHLD	__v6clang_ss.main
	INX	DE
	INX	DE
	XCHG
	SHLD	__v6clang_ss.main+2
	POP	HL
	XCHG
	INX	DE
	INX	DE
	INX	HL
	INX	HL
	INX	BC
	INX	BC
	MVI	A, <(A+32)
	CMP	C
	JNZ	.LBB4_3
; %bb.10:                               ;   in Loop: Header=BB4_3 Depth=1
	MVI	A, >(A+32)
	CMP	B
	JNZ	.LBB4_3
; %bb.4:
	LXI	DE, B
	LXI	BC, A
	LXI	HL, 0
.LBB4_5:                                ; =>This Inner Loop Header: Depth=1
	PUSH	HL
	LXI	HL, __v6clang_ss.main+4
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	XCHG
	PUSH	HL
	XCHG
	PUSH	HL
	XCHG
	MOV	A, M
	INX	HL
	MOV	H, M
	MOV	L, A
	XCHG
	PUSH	HL
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	POP	HL
	CALL	__mulhi3
	PUSH	HL
	LXI	HL, __v6clang_ss.main+4
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	XCHG
	POP	HL
	DAD	DE
	XCHG
	POP	HL
	XCHG
	SHLD	__v6clang_ss.main
	INX	DE
	INX	DE
	INX	BC
	INX	BC
	MVI	A, <(A+32)
	CMP	C
	JNZ	.LBB4_5
; %bb.11:                               ;   in Loop: Header=BB4_5 Depth=1
	MVI	A, >(A+32)
	CMP	B
	JNZ	.LBB4_5
; %bb.6:
	SHLD	g_dot
	LXI	DE, D1
	LXI	BC, D2
.LBB4_7:                                ; =>This Inner Loop Header: Depth=1
	PUSH	HL
	MOV	H, B
	MOV	L, C
	MOV	A, M
	INX	HL
	MOV	H, M
	MOV	L, A
	POP	HL
	DAD	HL
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	INX	DE
	INX	DE
	INX	BC
	INX	BC
	MVI	A, <(D2+32)
	CMP	C
	JNZ	.LBB4_7
; %bb.12:                               ;   in Loop: Header=BB4_7 Depth=1
	MVI	A, >(D2+32)
	CMP	B
	JNZ	.LBB4_7
; %bb.8:
	XCHG
	LHLD	OUT
	XCHG
	LHLD	__v6clang_ss.main
	DAD	DE
	XCHG
	LHLD	D1
	DAD	DE
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	A                               ; @A
A:

	.globl	B                               ; @B
B:

	.globl	C                               ; @C
C:

	.globl	D1                              ; @D1
D1:

	.globl	D2                              ; @D2
D2:

	.globl	OUT                             ; @OUT
OUT:

	.globl	g_dot                           ; @g_dot
g_dot:
	DW	0                               ; 0x0

	.local	__v6clang_ss.axpy3                  ; @__v6clang_ss.axpy3
	.comm	__v6clang_ss.axpy3,10,1
	.local	__v6clang_ss.dot                    ; @__v6clang_ss.dot
	.comm	__v6clang_ss.dot,8,1
	.local	__v6clang_ss.scale_copy             ; @__v6clang_ss.scale_copy
	.comm	__v6clang_ss.scale_copy,2,1
	.local	__v6clang_ss.seed                   ; @__v6clang_ss.seed
	.comm	__v6clang_ss.seed,10,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,10,1
	.addrsig
