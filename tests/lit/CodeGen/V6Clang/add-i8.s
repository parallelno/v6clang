	.text
	.text
	.globl	add_reg                         ; -- Begin function add_reg
add_reg:                                ; @add_reg
; %bb.0:
	ADD	E
	RET
                                        ; -- End function
	.globl	add_imm                         ; -- Begin function add_imm
add_imm:                                ; @add_imm
; %bb.0:
	ADI	5
	RET
                                        ; -- End function
