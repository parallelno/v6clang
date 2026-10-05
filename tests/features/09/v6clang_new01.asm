	.text
	.globl	test_ne_zero                    ; -- Begin function test_ne_zero
test_ne_zero:                           ; @test_ne_zero
; %bb.0:
	MOV	A, H
	ORA	L
	JZ	.LBB0_2
; %bb.1:
	JMP	bar
.LBB0_2:
	RET
                                        ; -- End function
	.globl	test_eq_zero                    ; -- Begin function test_eq_zero
test_eq_zero:                           ; @test_eq_zero
; %bb.0:
	MOV	A, H
	ORA	L
	JZ	.LBB1_2
; %bb.1:
	JMP	bar
.LBB1_2:
	RET
                                        ; -- End function
	.globl	test_const_42                   ; -- Begin function test_const_42
test_const_42:                          ; @test_const_42
; %bb.0:
	MVI	A, 0x2a
	CMP	L
	JNZ	.LBB2_1
; %bb.3:
	MVI	A, 0
	CMP	H
	JZ	.LBB2_2
.LBB2_1:
	JMP	bar
.LBB2_2:
	RET
                                        ; -- End function
	.globl	test_different_const            ; -- Begin function test_different_const
test_different_const:                   ; @test_different_const
; %bb.0:
	MOV	D, H
	MOV	E, L
	LXI	HL, 0
	MVI	A, 1
	CMP	E
	JNZ	.LBB3_1
; %bb.3:
	MVI	A, 0
	CMP	D
	JZ	.LBB3_2
.LBB3_1:
	MOV	H, D
	MOV	L, E
	JMP	bar
.LBB3_2:
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 5
	CALL	bar
	LXI	DE, 0x2a
	DAD	DE
	RET
                                        ; -- End function
	.addrsig
