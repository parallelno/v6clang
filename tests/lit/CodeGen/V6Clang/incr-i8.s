	.text
	.text
	.globl	incr                            ; -- Begin function incr
incr:                                   ; @incr
; %bb.0:
	INR	A
	RET
                                        ; -- End function
	.globl	decr                            ; -- Begin function decr
decr:                                   ; @decr
; %bb.0:
	DCR	A
	RET
                                        ; -- End function
