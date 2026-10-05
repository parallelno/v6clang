	.text
	.text
	.globl	const_zero                      ; -- Begin function const_zero
const_zero:                             ; @const_zero
; %bb.0:
	MVI	A, 0
	RET
                                        ; -- End function
	.globl	const_ff                        ; -- Begin function const_ff
const_ff:                               ; @const_ff
; %bb.0:
	MVI	A, 0xffffffffffffffff
	RET
                                        ; -- End function
	.globl	const_to_reg                    ; -- Begin function const_to_reg
const_to_reg:                           ; @const_to_reg
; %bb.0:
	ADI	0x2a
	RET
                                        ; -- End function
