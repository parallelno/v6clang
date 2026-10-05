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
	LXI	HL, 1
	SHLD	B
	SHLD	A+2
	LXI	HL, 2
	SHLD	C
	SHLD	B+2
	SHLD	A+4
	LXI	HL, 3
	SHLD	C+2
	SHLD	B+4
	SHLD	A+6
	LXI	HL, 0
	SHLD	A
	SHLD	D1
	SHLD	D2
	SHLD	D1+2
	SHLD	D2+2
	LXI	HL, 4
	SHLD	C+4
	LXI	HL, 0
	SHLD	D1+4
	SHLD	D2+4
	LXI	HL, 4
	SHLD	B+6
	LXI	HL, 5
	SHLD	C+6
	LXI	HL, 0
	SHLD	D1+6
	SHLD	D2+6
	LXI	HL, 4
	SHLD	A+8
	LXI	HL, 5
	SHLD	B+8
	LXI	HL, 6
	SHLD	C+8
	LXI	HL, 0
	SHLD	D1+8
	SHLD	D2+8
	LXI	HL, 5
	SHLD	A+10
	LXI	HL, 6
	SHLD	B+10
	LXI	HL, 7
	SHLD	C+10
	LXI	HL, 0
	SHLD	D1+10
	SHLD	D2+10
	LXI	HL, 6
	SHLD	A+12
	LXI	HL, 7
	SHLD	B+12
	LXI	HL, 8
	SHLD	C+12
	LXI	HL, 0
	SHLD	D1+12
	SHLD	D2+12
	LXI	HL, 7
	SHLD	A+14
	LXI	HL, 8
	SHLD	B+14
	LXI	HL, 9
	SHLD	C+14
	LXI	HL, 0
	SHLD	D1+14
	SHLD	D2+14
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 1
	SHLD	B
	SHLD	A+2
	LXI	HL, 2
	SHLD	C
	SHLD	B+2
	SHLD	A+4
	LXI	HL, 4
	SHLD	C+4
	SHLD	B+6
	SHLD	A+8
	LXI	HL, 0
	SHLD	A
	SHLD	D2
	LXI	HL, 3
	SHLD	C+2
	LXI	HL, 0
	SHLD	D2+2
	LXI	HL, 3
	SHLD	B+4
	LXI	HL, 0
	SHLD	D2+4
	LXI	HL, 3
	SHLD	A+6
	LXI	HL, 5
	SHLD	C+6
	LXI	HL, 0
	SHLD	D2+6
	LXI	HL, 5
	SHLD	B+8
	LXI	HL, 6
	SHLD	C+8
	LXI	HL, 0
	SHLD	D2+8
	LXI	HL, 5
	SHLD	A+10
	LXI	HL, 6
	SHLD	B+10
	LXI	HL, 7
	SHLD	C+10
	LXI	HL, 0
	SHLD	D2+10
	LXI	HL, 6
	SHLD	A+12
	LXI	HL, 7
	SHLD	B+12
	LXI	HL, 8
	SHLD	C+12
	LXI	HL, 0
	SHLD	D2+12
	LXI	HL, 7
	SHLD	A+14
	LXI	HL, 8
	SHLD	B+14
	LXI	HL, 9
	SHLD	C+14
	LXI	HL, 0
	SHLD	D2+14
	LXI	HL, 0x18
	SHLD	OUT+14
	LXI	HL, 0x15
	SHLD	OUT+12
	LXI	HL, 0x12
	SHLD	OUT+10
	LXI	HL, 0xf
	SHLD	OUT+8
	LXI	HL, 0xc
	SHLD	OUT+6
	LXI	HL, 9
	SHLD	OUT+4
	LXI	HL, 6
	SHLD	OUT+2
	LXI	HL, 3
	SHLD	OUT
	LXI	HL, 0xa8
	SHLD	g_dot
	LXI	HL, 0
	SHLD	D1+14
	SHLD	D1+12
	SHLD	D1+10
	SHLD	D1+8
	SHLD	D1+6
	SHLD	D1+4
	SHLD	D1+2
	SHLD	D1
	LXI	HL, 0xab
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
	.addrsig
