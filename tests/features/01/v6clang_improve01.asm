	.text
	.globl	wrapper                         ; -- Begin function wrapper
wrapper:                                ; @wrapper
; %bb.0:
	JMP	helper
                                        ; -- End function
	.globl	void_wrapper                    ; -- Begin function void_wrapper
void_wrapper:                           ; @void_wrapper
; %bb.0:
	JMP	void_func
                                        ; -- End function
	.globl	not_tail                        ; -- Begin function not_tail
not_tail:                               ; @not_tail
; %bb.0:
	CALL	helper
	INX	HL
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0x2a
	CALL	helper
	CALL	void_func
	LXI	HL, 0xa
	CALL	helper
	LXI	HL, 0
	RET
                                        ; -- End function
	.addrsig
