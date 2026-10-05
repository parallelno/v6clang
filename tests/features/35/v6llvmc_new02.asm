	.text
	.globl	de_one_reload                   ; -- Begin function de_one_reload
de_one_reload:                          ; @de_one_reload
; %bb.0:
	XCHG
	PUSH	HL
	XCHG
	CALL	op1
	SHLD	.LLo61_0+1
	POP	HL
	CALL	op2
.LLo61_0:
	LXI	DE, 0
	DAD	DE
	RET
                                        ; -- End function
	.globl	mixed_hl_de                     ; -- Begin function mixed_hl_de
mixed_hl_de:                            ; @mixed_hl_de
; %bb.0:
	XCHG
	PUSH	HL
	XCHG
	CALL	op1
	PUSH	HL
	CALL	op2
	XCHG
	POP	HL
	XCHG
	DAD	DE
	SHLD	__v6clang_ss.mixed_hl_de+2
	POP	HL
	CALL	op2
	XCHG
	LHLD	__v6clang_ss.mixed_hl_de+2
	DAD	DE
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0x1234
	CALL	op1
	PUSH	HL
	LXI	HL, 0x5678
	CALL	op2
	XCHG
	POP	HL
	XCHG
	DAD	DE
	SHLD	g1
	LXI	HL, 0xaaaa
	CALL	op1
	PUSH	HL
	CALL	op2
	XCHG
	POP	HL
	XCHG
	DAD	DE
	PUSH	HL
	LXI	HL, 0xbbbb
	CALL	op2
	XCHG
	POP	HL
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

	.local	__v6clang_ss.de_one_reload          ; @__v6clang_ss.de_one_reload
	.comm	__v6clang_ss.de_one_reload,4,1
	.local	__v6clang_ss.mixed_hl_de            ; @__v6clang_ss.mixed_hl_de
	.comm	__v6clang_ss.mixed_hl_de,4,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,2,1
	.addrsig
