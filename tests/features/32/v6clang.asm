	.text
	.globl	u16_shl8                        ; -- Begin function u16_shl8
u16_shl8:                               ; @u16_shl8
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.u16_shl8
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	MOV	B, H
	MOV	C, L
	MOV	H, D
	MOV	L, E
	MOV	M, C
	INX	HL
	MOV	M, B
	MVI	A, 0
	MOV	H, C
	MOV	L, A
	XCHG
	LHLD	__v6clang_ss.u16_shl8
	XCHG
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	RET
                                        ; -- End function
	.globl	u16_shl10                       ; -- Begin function u16_shl10
u16_shl10:                              ; @u16_shl10
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.u16_shl10
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	MOV	B, H
	MOV	C, L
	MOV	H, D
	MOV	L, E
	MOV	M, C
	INX	HL
	MOV	M, B
	MOV	A, C
	ADD	A
	ADD	A
	MVI	L, 0
	MOV	H, A
	XCHG
	LHLD	__v6clang_ss.u16_shl10
	XCHG
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	RET
                                        ; -- End function
	.globl	u16_srl8                        ; -- Begin function u16_srl8
u16_srl8:                               ; @u16_srl8
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.u16_srl8
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	MOV	B, H
	MOV	C, L
	MOV	H, D
	MOV	L, E
	MOV	M, C
	INX	HL
	MOV	M, B
	MOV	L, B
	MVI	H, 0
	XCHG
	LHLD	__v6clang_ss.u16_srl8
	XCHG
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	RET
                                        ; -- End function
	.globl	u16_srl10                       ; -- Begin function u16_srl10
u16_srl10:                              ; @u16_srl10
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.u16_srl10
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	MOV	B, H
	MOV	C, L
	MOV	H, D
	MOV	L, E
	MOV	M, C
	INX	HL
	MOV	M, B
	MOV	L, B
	MVI	H, 0
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	XCHG
	LHLD	__v6clang_ss.u16_srl10
	XCHG
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	RET
                                        ; -- End function
	.globl	i16_shl8                        ; -- Begin function i16_shl8
i16_shl8:                               ; @i16_shl8
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.i16_shl8
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	MOV	B, H
	MOV	C, L
	MOV	H, D
	MOV	L, E
	MOV	M, C
	INX	HL
	MOV	M, B
	MVI	A, 0
	MOV	H, C
	MOV	L, A
	XCHG
	LHLD	__v6clang_ss.i16_shl8
	XCHG
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	RET
                                        ; -- End function
	.globl	i16_shl10                       ; -- Begin function i16_shl10
i16_shl10:                              ; @i16_shl10
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.i16_shl10
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	MOV	B, H
	MOV	C, L
	MOV	H, D
	MOV	L, E
	MOV	M, C
	INX	HL
	MOV	M, B
	MOV	A, C
	ADD	A
	ADD	A
	MVI	L, 0
	MOV	H, A
	XCHG
	LHLD	__v6clang_ss.i16_shl10
	XCHG
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	RET
                                        ; -- End function
	.globl	i16_sra8                        ; -- Begin function i16_sra8
i16_sra8:                               ; @i16_sra8
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.i16_sra8
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	MOV	B, H
	MOV	C, L
	MOV	H, D
	MOV	L, E
	MOV	M, C
	INX	HL
	MOV	M, B
	MOV	A, B
	MOV	L, B
	RLC
	SBB	A
	MOV	H, A
	XCHG
	LHLD	__v6clang_ss.i16_sra8
	XCHG
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	RET
                                        ; -- End function
	.globl	i16_sra10                       ; -- Begin function i16_sra10
i16_sra10:                              ; @i16_sra10
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.i16_sra10
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	MOV	B, H
	MOV	C, L
	MOV	H, D
	MOV	L, E
	MOV	M, C
	INX	HL
	MOV	M, B
	MOV	A, B
	MOV	L, B
	RLC
	SBB	A
	MOV	H, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	XCHG
	LHLD	__v6clang_ss.i16_sra10
	XCHG
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	RET
                                        ; -- End function
	.globl	u8_shl3                         ; -- Begin function u8_shl3
u8_shl3:                                ; @u8_shl3
; %bb.0:
	STAX	DE
	ADD	A
	ADD	A
	ADD	A
	STAX	BC
	RET
                                        ; -- End function
	.globl	i8_shl3                         ; -- Begin function i8_shl3
i8_shl3:                                ; @i8_shl3
; %bb.0:
	STAX	DE
	ADD	A
	ADD	A
	ADD	A
	STAX	BC
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 4
	SHLD	u16_q
	LXI	HL, 0x1234
	SHLD	u16_p
	LXI	HL, 0xfb2e
	SHLD	i16_p
	LXI	HL, 0xfffe
	SHLD	i16_q
	MVI	A, 0x12
	STA	u8_p
	STA	i8_p
	MVI	A, 0x90
	STA	u8_q
	STA	i8_q
	LXI	HL, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	u16_p                           ; @u16_p
u16_p:
	DW	0                               ; 0x0

	.globl	u16_q                           ; @u16_q
u16_q:
	DW	0                               ; 0x0

	.globl	i16_p                           ; @i16_p
i16_p:
	DW	0                               ; 0x0

	.globl	i16_q                           ; @i16_q
i16_q:
	DW	0                               ; 0x0

	.globl	u8_p                            ; @u8_p
u8_p:
	DB	0                               ; 0x0

	.globl	u8_q                            ; @u8_q
u8_q:
	DB	0                               ; 0x0

	.globl	i8_p                            ; @i8_p
i8_p:
	DB	0                               ; 0x0

	.globl	i8_q                            ; @i8_q
i8_q:
	DB	0                               ; 0x0

	.local	__v6clang_ss.u16_shl8               ; @__v6clang_ss.u16_shl8
	.comm	__v6clang_ss.u16_shl8,2,1
	.local	__v6clang_ss.u16_shl10              ; @__v6clang_ss.u16_shl10
	.comm	__v6clang_ss.u16_shl10,2,1
	.local	__v6clang_ss.u16_srl8               ; @__v6clang_ss.u16_srl8
	.comm	__v6clang_ss.u16_srl8,2,1
	.local	__v6clang_ss.u16_srl10              ; @__v6clang_ss.u16_srl10
	.comm	__v6clang_ss.u16_srl10,2,1
	.local	__v6clang_ss.i16_shl8               ; @__v6clang_ss.i16_shl8
	.comm	__v6clang_ss.i16_shl8,2,1
	.local	__v6clang_ss.i16_shl10              ; @__v6clang_ss.i16_shl10
	.comm	__v6clang_ss.i16_shl10,2,1
	.local	__v6clang_ss.i16_sra8               ; @__v6clang_ss.i16_sra8
	.comm	__v6clang_ss.i16_sra8,2,1
	.local	__v6clang_ss.i16_sra10              ; @__v6clang_ss.i16_sra10
	.comm	__v6clang_ss.i16_sra10,2,1
	.addrsig
