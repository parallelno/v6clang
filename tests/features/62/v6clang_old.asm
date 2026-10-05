	.text
	.section	.text.shape_a,"ax",@progbits
	.globl	shape_a                         ; -- Begin function shape_a
shape_a:                                ; @shape_a
; %bb.0:
	ORA	A
	JZ	.LBB15_2
; %bb.1:
	MVI	A, 1
	RET
.LBB15_2:
	XRA	A
	RET
                                        ; -- End function
	.section	.text.shape_a_dead,"ax",@progbits
	.globl	shape_a_dead                    ; -- Begin function shape_a_dead
shape_a_dead:                           ; @shape_a_dead
; %bb.0:
	MOV	L, A
	XRA	A
	CMP	B
	JNZ	.LBB16_2
; %bb.1:
	MOV	L, A
.LBB16_2:
	MOV	A, L
	RET
                                        ; -- End function
	.section	.text.shape_a_live,"ax",@progbits
	.globl	shape_a_live                    ; -- Begin function shape_a_live
shape_a_live:                           ; @shape_a_live
; %bb.0:
	MOV	H, A
	XRA	A
	CMP	B
	JZ	.LBB17_2
; %bb.1:
	MVI	L, 1
	JMP	.LBB17_3
.LBB17_2:
	MOV	L, A
.LBB17_3:
	MOV	A, L
	STA	.LLo61_0+1
	MOV	A, H
	CALL	op1
.LLo61_0:
	ADI	0
	RET
                                        ; -- End function
	.section	.text.shape_a_live_loop,"ax",@progbits
	.globl	shape_a_live_loop               ; -- Begin function shape_a_live_loop
shape_a_live_loop:                      ; @shape_a_live_loop
; %bb.0:
	MOV	L, A
	MOV	A, B
	STA	.LLo61_1+1
	MOV	A, B
	ORA	A
	MOV	A, L
	RZ
.LBB18_1:                               ; =>This Inner Loop Header: Depth=1
	CALL	op1
.LLo61_1:
	MVI	L, 0
	DCR	L
	MOV	B, A
	MOV	A, L
	STA	.LLo61_1+1
	MOV	A, B
	JNZ	.LBB18_1
; %bb.2:
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	MVI	A, 1
	MVI	B, 0
	CALL	use2
	MVI	A, 0x22
	MVI	B, 0
	CALL	use2
	MVI	A, 0x55
	CALL	op1
	STA	.LLo61_2+1
	MVI	A, 0x66
	CALL	op1
	MOV	B, A
.LLo61_2:
	MVI	A, 0
	INR	A
	CALL	use2
	MVI	A, 0x77
	CALL	op1
	CALL	op1
	CALL	op1
	CALL	op1
	CALL	op1
	CALL	sink
	LXI	H, 0
	RET
                                        ; -- End function
	.addrsig
	.addrsig_sym __mulqi3
	.addrsig_sym __v6clang_mulqihi3
	.addrsig_sym __mulhi3
	.addrsig_sym __v6clang_udivmod16_body
	.addrsig_sym __udivhi3
	.addrsig_sym __umodhi3
	.addrsig_sym __udivmodhi4
	.addrsig_sym __divmodhi4
	.addrsig_sym __v6clang_neg_hl_body
	.addrsig_sym __v6clang_neg_de_body
	.addrsig_sym __divhi3
	.addrsig_sym __modhi3
	.addrsig_sym __ashlhi3
	.addrsig_sym __lshrhi3
	.addrsig_sym __ashrhi3
