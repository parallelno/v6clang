	.text
	.globl	interleaved_add                 ; -- Begin function interleaved_add
interleaved_add:                        ; @interleaved_add
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.interleaved_add+2
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	XCHG
	SHLD	__v6clang_ss.interleaved_add
	XCHG
	SHLD	__v6clang_ss.interleaved_add+7
	LXI	HL, 0
	DAD	SP
	MOV	A, M
	ORA	A
	JZ	.LBB0_3
; %bb.1:
	MVI	L, 0
	MOV	B, L
	MOV	C, A
	LHLD	__v6clang_ss.interleaved_add+7
	XCHG
.LBB0_2:                                ; =>This Inner Loop Header: Depth=1
	MOV	L, C
	MOV	H, B
	PUSH	HL
	LHLD	__v6clang_ss.interleaved_add
	PUSH	HL
	MOV	A, M
	STA	__v6clang_ss.interleaved_add+6
	PUSH	HL
	LXI	HL, __v6clang_ss.interleaved_add+2
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	LDAX	BC
	PUSH	DE
	MOV	D, H
	LXI	HL, __v6clang_ss.interleaved_add+6
	MOV	L, M
	MOV	H, D
	POP	DE
	ADD	L
	STAX	DE
	POP	HL
	INX	HL
	PUSH	HL
	POP	HL
	INX	BC
	MOV	L, C
	MOV	H, B
	SHLD	__v6clang_ss.interleaved_add+2
	POP	HL
	MOV	C, L
	MOV	B, H
	INX	DE
	DCX	BC
	MOV	A, B
	ORA	C
	JNZ	.LBB0_2
.LBB0_3:
	LHLD	__v6clang_ss.interleaved_add+7
	MOV	A, M
	JMP	use8
                                        ; -- End function
	.globl	multi_live                      ; -- Begin function multi_live
multi_live:                             ; @multi_live
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.multi_live
	MOV	M, E
	POP	HL
	STA	__v6clang_ss.multi_live+1
	MOV	A, C
	CALL	use8
	LDA	__v6clang_ss.multi_live+1
	MOV	D, H
	LXI	HL, __v6clang_ss.multi_live
	MOV	L, M
	MOV	H, D
	ADD	L
	ADI	3
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	MVI	A, 0xb
	CALL	use8
	LXI	HL, __v6clang_ss.main
	PUSH	HL
	MVI	A, 0xb
	MOV	M, A
	MVI	A, 3
	CALL	use8
	MVI	A, 6
	POP	HL
	MOV	M, A
	MOV	A, M
	MVI	L, 0
	MOV	H, L
	MOV	L, A
	RET
                                        ; -- End function
	.local	__v6clang_ss.interleaved_add        ; @__v6clang_ss.interleaved_add
	.comm	__v6clang_ss.interleaved_add,9,1
	.local	__v6clang_ss.multi_live             ; @__v6clang_ss.multi_live
	.comm	__v6clang_ss.multi_live,2,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,3,1
	.addrsig
