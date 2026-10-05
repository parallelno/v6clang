	.text
	.text
	.globl	or_reg                          ; -- Begin function or_reg
or_reg:                                 ; @or_reg
; %bb.0:
	ORA	E
	RET
                                        ; -- End function
	.globl	or_imm                          ; -- Begin function or_imm
or_imm:                                 ; @or_imm
; %bb.0:
	ORI	7
	RET
                                        ; -- End function
