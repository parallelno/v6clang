	.text
	.section	.text.fold_add,"ax",@progbits
	.globl	fold_add                        ; -- Begin function fold_add
fold_add:                               ; @fold_add
; %bb.0:
	ADI	0xf
	RET
                                        ; -- End function
	.section	.text.fold_sub,"ax",@progbits
	.globl	fold_sub                        ; -- Begin function fold_sub
fold_sub:                               ; @fold_sub
; %bb.0:
	ADI	0xfb
	RET
                                        ; -- End function
	.section	.text.fold_and,"ax",@progbits
	.globl	fold_and                        ; -- Begin function fold_and
fold_and:                               ; @fold_and
; %bb.0:
	ANI	0xf0
	RET
                                        ; -- End function
	.section	.text.fold_or,"ax",@progbits
	.globl	fold_or                         ; -- Begin function fold_or
fold_or:                                ; @fold_or
; %bb.0:
	ORI	1
	RET
                                        ; -- End function
	.section	.text.fold_xor,"ax",@progbits
	.globl	fold_xor                        ; -- Begin function fold_xor
fold_xor:                               ; @fold_xor
; %bb.0:
	XRI	0x55
	RET
                                        ; -- End function
	.section	.text.fold_cmp,"ax",@progbits
	.globl	fold_cmp                        ; -- Begin function fold_cmp
fold_cmp:                               ; @fold_cmp
; %bb.0:
	CPI	0x42
	MVI	A, 0
	MOV	L, A
	JNZ	.LBB20_2
; %bb.1:
	INR	L
.LBB20_2:
	MOV	H, A
	RET
                                        ; -- End function
	.section	.text.fold_chain,"ax",@progbits
	.globl	fold_chain                      ; -- Begin function fold_chain
fold_chain:                             ; @fold_chain
; %bb.0:
	ADI	5
	ANI	0xf0
	XRI	0x10
	RET
                                        ; -- End function
	.section	.text.fold_spill,"ax",@progbits
	.globl	fold_spill                      ; -- Begin function fold_spill
fold_spill:                             ; @fold_spill
; %bb.0:
	PUSH	PSW
	MOV	A, H
	STA	.LLo61_0+1
	POP	PSW
	MOV	A, B
	XRA	H
	XRA	C
	XRA	D
	XRA	E
	XRA	L
.LLo61_0:
	XRI	0
	LXI	H, 2
	DAD	SP
	XRA	M
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	MVI	A, 0x1f
	STA	g_sink
	MVI	A, 0xb
	STA	g_sink
	MVI	A, 0xa0
	STA	g_sink
	MVI	A, 0xab
	STA	g_sink
	MVI	A, 0xff
	STA	g_sink
	MVI	A, 1
	STA	g_sink
	MVI	A, 0x10
	STA	g_sink
	MVI	A, 8
	STA	g_sink
	LXI	H, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_sink                          ; @g_sink
g_sink:
	DB	0                               ; 0x0

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
	.addrsig_sym g_sink
