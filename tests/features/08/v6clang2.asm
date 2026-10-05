	.text
	.globl	test_ne_zero                    ; -- Begin function test_ne_zero
test_ne_zero:                           ; @test_ne_zero
; %bb.0:
	MOV	D, H
	MOV	E, L
	LXI	HL, 0
	MOV	A, D
	ORA	E
	JZ	.LBB0_2
; %bb.1:
	MOV	H, D
	MOV	L, E
	JMP	bar
.LBB0_2:
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 5
	JMP	bar
                                        ; -- End function
	.addrsig
