	.text
	.section	.text.load8_stack_arg,"ax",@progbits
	.globl	load8_stack_arg                 ; -- Begin function load8_stack_arg
load8_stack_arg:                        ; @load8_stack_arg
; %bb.0:
	LXI	H, 2
	DAD	SP
	MOV	A, M
	RET
                                        ; -- End function
	.section	.text.load16_stack_arg,"ax",@progbits
	.globl	load16_stack_arg                ; -- Begin function load16_stack_arg
load16_stack_arg:                       ; @load16_stack_arg
; %bb.0:
	DAD	D
	DAD	B
	XCHG
	LXI	H, 2
	DAD	SP
	MOV	C, M
	INX	H
	MOV	B, M
	XCHG
	DAD	B
	RET
                                        ; -- End function
	.section	.text.store8_local,"ax",@progbits
	.globl	store8_local                    ; -- Begin function store8_local
store8_local:                           ; @store8_local
; %bb.0:
	STA	__v6clang_a.store8_local
	LDA	__v6clang_a.store8_local
	RET
                                        ; -- End function
	.section	.text.store16_local,"ax",@progbits
	.globl	store16_local                   ; -- Begin function store16_local
store16_local:                          ; @store16_local
; %bb.0:
	PUSH	H
	POP	H
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	PUSH	PSW
	MVI	A, 8
	STA	g8
	LXI	H, 0
	DAD	SP
	LXI	D, 4
	MOV	M, E
	INX	H
	MOV	M, D
	LXI	H, 1
	LXI	D, 2
	LXI	B, 3
	CALL	load16_stack_arg
	PUSH	H
	LDA	g8
	CALL	store8_local
	STA	g8
	POP	H
	CALL	store16_local
	PUSH	H
	LDA	g8
	OUT	0xed
	POP	H
	MOV	A, L
	OUT	0xed
	HLT
	LXI	H, 0
	POP	PSW
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g8                              ; @g8
g8:
	DB	0                               ; 0x0

	.globl	g16                             ; @g16
g16:
	DW	0                               ; 0x0

	.local	__v6clang_a.store8_local            ; @__v6clang_a.store8_local
	.comm	__v6clang_a.store8_local,1,1
	.local	__v6clang_a.store16_local           ; @__v6clang_a.store16_local
	.comm	__v6clang_a.store16_local,2,1
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
	.addrsig_sym g8
	.addrsig_sym g16
	.addrsig_sym __v6clang_a.store8_local
	.addrsig_sym __v6clang_a.store16_local
