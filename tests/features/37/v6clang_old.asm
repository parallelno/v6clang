	.text
	.globl	a_spill_r8_reload               ; -- Begin function a_spill_r8_reload
a_spill_r8_reload:                      ; @a_spill_r8_reload
; %bb.0:
	LXI	HL, __v6clang_ss.a_spill_r8_reload
	MOV	M, E
	CALL	op1
	STA	__v6clang_ss.a_spill_r8_reload+1
	LDA	__v6clang_ss.a_spill_r8_reload
	CALL	op2
	LXI	HL, __v6clang_ss.a_spill_r8_reload+1
	MOV	L, M
	ADD	L
	RET
                                        ; -- End function
	.globl	k2_i8                           ; -- Begin function k2_i8
k2_i8:                                  ; @k2_i8
; %bb.0:
	LXI	HL, __v6clang_ss.k2_i8
	MOV	M, C
	LXI	HL, __v6clang_ss.k2_i8+2
	MOV	M, E
	CALL	op1
	STA	__v6clang_ss.k2_i8+1
	LDA	__v6clang_ss.k2_i8+2
	CALL	op2
	MOV	H, A
	LDA	__v6clang_ss.k2_i8+1
	ADD	A
	MOV	L, A
	MOV	A, H
	ADD	L
	STA	__v6clang_ss.k2_i8+1
	LDA	__v6clang_ss.k2_i8
	CALL	op2
	MOV	L, A
	LDA	__v6clang_ss.k2_i8+1
	ADD	L
	RET
                                        ; -- End function
	.globl	multi_src_i8                    ; -- Begin function multi_src_i8
multi_src_i8:                           ; @multi_src_i8
; %bb.0:
	LXI	HL, __v6clang_ss.multi_src_i8
	MOV	M, E
	MOV	L, A
	XRA	A
	CMP	C
	JZ	.LBB2_2
; %bb.1:
	MOV	A, L
	CALL	op1
	JMP	.LBB2_3
.LBB2_2:
	MOV	A, L
	CALL	op2
.LBB2_3:
	STA	__v6clang_ss.multi_src_i8+1
	LDA	__v6clang_ss.multi_src_i8
	CALL	op2
	LXI	HL, __v6clang_ss.multi_src_i8+1
	MOV	L, M
	ADD	L
	RET
                                        ; -- End function
	.globl	mixed_widths                    ; -- Begin function mixed_widths
mixed_widths:                           ; @mixed_widths
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.mixed_widths
	MOV	M, E
	POP	HL
	SHLD	__v6clang_ss.mixed_widths+1
	MOV	A, L
	CALL	op1
	MVI	L, 0
	MOV	H, L
	MOV	L, A
	XCHG
	LHLD	__v6clang_ss.mixed_widths+1
	XCHG
	DAD	DE
	PUSH	HL
	LDA	__v6clang_ss.mixed_widths
	CALL	op2
	STA	__v6clang_ss.mixed_widths+3
	LHLD	__v6clang_ss.mixed_widths+1
	MOV	A, L
	CALL	op2
	MVI	L, 0
	MOV	H, L
	MOV	L, A
	XCHG
	POP	HL
	DAD	DE
	PUSH	HL
	LDA	__v6clang_ss.mixed_widths
	CALL	op1
	POP	HL
	SHLD	g_u16
	LXI	HL, __v6clang_ss.mixed_widths+3
	MOV	L, M
	ADD	L
	STA	g_u8
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	MVI	A, 0x11
	CALL	op1
	STA	__v6clang_ss.main+1
	MVI	A, 0x22
	CALL	op2
	STA	__v6clang_ss.main
	MVI	A, 0x33
	CALL	op1
	STA	__v6clang_ss.main+3
	MVI	A, 0x44
	CALL	op2
	MOV	H, A
	LDA	__v6clang_ss.main
	MOV	D, H
	LXI	HL, __v6clang_ss.main+1
	MOV	L, M
	MOV	H, D
	ADD	L
	STA	__v6clang_ss.main
	LDA	__v6clang_ss.main+3
	ADD	A
	MOV	L, A
	MOV	A, H
	ADD	L
	STA	__v6clang_ss.main+1
	MVI	A, 0x55
	CALL	op2
	MOV	L, A
	LDA	__v6clang_ss.main+1
	ADD	L
	MOV	E, A
	LDA	__v6clang_ss.main
	CALL	use2
	MVI	A, 0x66
	CALL	op1
	STA	__v6clang_ss.main
	MVI	A, 0x77
	CALL	op2
	LXI	HL, __v6clang_ss.main
	MOV	L, M
	ADD	L
	MVI	E, 0
	CALL	use2
	MVI	A, 0xcd
	CALL	op1
	MVI	L, 0
	MOV	H, L
	MOV	L, A
	PUSH	HL
	MVI	A, 0xef
	CALL	op2
	STA	__v6clang_ss.main
	MVI	A, 0xcd
	CALL	op2
	MVI	L, 0
	MOV	H, L
	MOV	L, A
	XCHG
	POP	HL
	DAD	DE
	LXI	DE, 0xabcd
	DAD	DE
	PUSH	HL
	MVI	A, 0xef
	CALL	op1
	POP	HL
	SHLD	g_u16
	LXI	HL, __v6clang_ss.main
	MOV	L, M
	ADD	L
	STA	g_u8
	LXI	HL, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_u16                           ; @g_u16
g_u16:
	DW	0                               ; 0x0

	.globl	g_u8                            ; @g_u8
g_u8:
	DB	0                               ; 0x0

	.local	__v6clang_ss.a_spill_r8_reload      ; @__v6clang_ss.a_spill_r8_reload
	.comm	__v6clang_ss.a_spill_r8_reload,2,1
	.local	__v6clang_ss.k2_i8                  ; @__v6clang_ss.k2_i8
	.comm	__v6clang_ss.k2_i8,3,1
	.local	__v6clang_ss.multi_src_i8           ; @__v6clang_ss.multi_src_i8
	.comm	__v6clang_ss.multi_src_i8,2,1
	.local	__v6clang_ss.mixed_widths           ; @__v6clang_ss.mixed_widths
	.comm	__v6clang_ss.mixed_widths,6,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,4,1
	.addrsig
