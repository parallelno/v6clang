	.text
	.globl	multi_src_de                    ; -- Begin function multi_src_de
multi_src_de:                           ; @multi_src_de
; %bb.0:
	XCHG
	SHLD	__v6clang_ss.multi_src_de
	XCHG
	MOV	A, B
	ORA	C
	JZ	.LBB0_2
; %bb.1:
	CALL	op1
	JMP	.LBB0_3
.LBB0_2:
	CALL	op2
.LBB0_3:
	SHLD	.LLo61_0+1
	LHLD	__v6clang_ss.multi_src_de
	CALL	op2
.LLo61_0:
	LXI	DE, 0
	DAD	DE
	RET
                                        ; -- End function
	.globl	k2_two_reloads                  ; -- Begin function k2_two_reloads
k2_two_reloads:                         ; @k2_two_reloads
; %bb.0:
	PUSH	HL
	LXI	HL, __v6clang_ss.k2_two_reloads
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	XCHG
	SHLD	__v6clang_ss.k2_two_reloads+2
	XCHG
	CALL	op1
	SHLD	.LLo61_1+1
	LHLD	__v6clang_ss.k2_two_reloads+2
	CALL	op2
.LLo61_1:
	LXI	DE, 0
	MOV	A, E
	ADD	E
	MOV	E, A
	MOV	A, D
	ADC	D
	MOV	D, A
	DAD	DE
	SHLD	__v6clang_ss.k2_two_reloads+2
	LHLD	__v6clang_ss.k2_two_reloads
	CALL	op2
	XCHG
	LHLD	__v6clang_ss.k2_two_reloads+2
	DAD	DE
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0x1234
	CALL	op1
	SHLD	.LLo61_2+1
	LXI	HL, 0x5678
	CALL	op2
.LLo61_2:
	LXI	DE, 0
	DAD	DE
	SHLD	g1
	LXI	HL, 0xaaaa
	CALL	op1
	SHLD	.LLo61_2+1
	LXI	HL, 0xbbbb
	CALL	op2
	XCHG
	LHLD	.LLo61_2+1
	XCHG
	MOV	A, E
	ADD	E
	MOV	E, A
	MOV	A, D
	ADC	D
	MOV	D, A
	DAD	DE
	SHLD	.LLo61_2+1
	LXI	HL, 0xcccc
	CALL	op2
	XCHG
	LHLD	.LLo61_2+1
	DAD	DE
	SHLD	g2
	LXI	HL, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g1                              ; @g1
g1:
	DW	0                               ; 0x0

	.globl	g2                              ; @g2
g2:
	DW	0                               ; 0x0

	.local	__v6clang_ss.multi_src_de           ; @__v6clang_ss.multi_src_de
	.comm	__v6clang_ss.multi_src_de,4,1
	.local	__v6clang_ss.k2_two_reloads         ; @__v6clang_ss.k2_two_reloads
	.comm	__v6clang_ss.k2_two_reloads,6,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,2,1
	.addrsig
