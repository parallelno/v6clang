	.text
	.globl	de_bc_three                     ; -- Begin function de_bc_three
de_bc_three:                            ; @de_bc_three
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.de_bc_three+4
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	XCHG
	PUSH	HL
	XCHG
	CALL	op_u16
	SHLD	__v6clang_ss.de_bc_three
	POP	HL
	CALL	op2_u16
	SHLD	__v6clang_ss.de_bc_three+2
	LHLD	__v6clang_ss.de_bc_three+4
	CALL	op_u16
	PUSH	HL
	LHLD	__v6clang_ss.de_bc_three
	XCHG
	LHLD	__v6clang_ss.de_bc_three+2
	XCHG
	MOV	C, L
	MOV	B, H
	CALL	use3_u16
	LHLD	__v6clang_ss.de_bc_three
	XCHG
	LHLD	__v6clang_ss.de_bc_three+2
	XCHG
	DAD	DE
	XCHG
	POP	HL
	DAD	DE
	RET
                                        ; -- End function
	.globl	de_one_reload                   ; -- Begin function de_one_reload
de_one_reload:                          ; @de_one_reload
; %bb.0:
	XCHG
	PUSH	HL
	XCHG
	CALL	op_u16
	SHLD	__v6clang_ss.de_one_reload+2
	POP	HL
	CALL	op2_u16
	XCHG
	LHLD	__v6clang_ss.de_one_reload+2
	DAD	DE
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0x1111
	CALL	op_u16
	SHLD	__v6clang_ss.main+2
	LXI	HL, 0x2222
	CALL	op2_u16
	SHLD	__v6clang_ss.main+4
	LXI	HL, 0x3333
	CALL	op_u16
	PUSH	HL
	LHLD	__v6clang_ss.main+2
	XCHG
	LHLD	__v6clang_ss.main+4
	XCHG
	MOV	C, L
	MOV	B, H
	CALL	use3_u16
	LHLD	__v6clang_ss.main+2
	XCHG
	LHLD	__v6clang_ss.main+4
	XCHG
	DAD	DE
	SHLD	__v6clang_ss.main+2
	LXI	HL, 0x4444
	CALL	op_u16
	SHLD	__v6clang_ss.main+4
	LXI	HL, 0x5555
	CALL	op2_u16
	XCHG
	POP	HL
	XCHG
	PUSH	HL
	LXI	HL, __v6clang_ss.main+2
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	MOV	A, C
	ADD	E
	MOV	C, A
	MOV	A, B
	ADC	D
	MOV	B, A
	XCHG
	LHLD	__v6clang_ss.main+4
	XCHG
	DAD	DE
	XCHG
	MOV	H, B
	MOV	L, C
	CALL	use2_u16
	LXI	HL, 0
	RET
                                        ; -- End function
	.local	__v6clang_ss.de_bc_three            ; @__v6clang_ss.de_bc_three
	.comm	__v6clang_ss.de_bc_three,6,1
	.local	__v6clang_ss.de_one_reload          ; @__v6clang_ss.de_one_reload
	.comm	__v6clang_ss.de_one_reload,4,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,6,1
	.addrsig
