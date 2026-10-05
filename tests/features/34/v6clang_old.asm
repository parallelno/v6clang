	.text
	.globl	hl_to_de                        ; -- Begin function hl_to_de
hl_to_de:                               ; @hl_to_de
; %bb.0:
	PUSH	HL
	XCHG
	CALL	op_hl
	SHLD	__v6clang_ss.hl_to_de
	XCHG
	POP	HL
	XCHG
	CALL	use_de
	LHLD	__v6clang_ss.hl_to_de
	SHLD	g_after
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0x5678
	CALL	op_hl
	PUSH	HL
	LXI	DE, 0x1234
	CALL	use_de
	POP	HL
	SHLD	g_after
	LXI	HL, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_after                         ; @g_after
g_after:
	DW	0                               ; 0x0

	.local	__v6clang_ss.hl_to_de               ; @__v6clang_ss.hl_to_de
	.comm	__v6clang_ss.hl_to_de,4,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,2,1
	.addrsig
