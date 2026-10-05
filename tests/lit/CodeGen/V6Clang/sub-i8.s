	.text
	.text
	.globl	sub_reg                         ; -- Begin function sub_reg
sub_reg:                                ; @sub_reg
; %bb.0:
	SUB	E
	RET
                                        ; -- End function
	.globl	sub_imm                         ; -- Begin function sub_imm
sub_imm:                                ; @sub_imm
; %bb.0:
	ADI	0xfffffffffffffffd
	RET
                                        ; -- End function
