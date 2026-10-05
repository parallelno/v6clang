	.text
	.text
	.globl	ret42                           ; -- Begin function ret42
ret42:                                  ; @ret42
; %bb.0:
	MVI	A, 0x2a
	RET
                                        ; -- End function
	.globl	identity                        ; -- Begin function identity
identity:                               ; @identity
; %bb.0:
	RET
                                        ; -- End function
