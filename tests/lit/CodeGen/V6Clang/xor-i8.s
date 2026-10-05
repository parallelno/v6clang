	.text
	.text
	.globl	xor_reg                         ; -- Begin function xor_reg
xor_reg:                                ; @xor_reg
; %bb.0:
	XRA	E
	RET
                                        ; -- End function
	.globl	xor_imm                         ; -- Begin function xor_imm
xor_imm:                                ; @xor_imm
; %bb.0:
	XRI	0x55
	RET
                                        ; -- End function
	.globl	not_a                           ; -- Begin function not_a
not_a:                                  ; @not_a
; %bb.0:
	CMA
	RET
                                        ; -- End function
