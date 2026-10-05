	.text
	.text
	.globl	and_reg                         ; -- Begin function and_reg
and_reg:                                ; @and_reg
; %bb.0:
	ANA	E
	RET
                                        ; -- End function
	.globl	and_imm                         ; -- Begin function and_imm
and_imm:                                ; @and_imm
; %bb.0:
	ANI	0xfffffffffffffff0
	RET
                                        ; -- End function
