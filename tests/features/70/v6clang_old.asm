	.text
	.section	.text.lookup_zext,"ax",@progbits
	.globl	lookup_zext                     ; -- Begin function lookup_zext
lookup_zext:                            ; @lookup_zext
; %bb.0:
	MVI	L, 0
	MOV	H, L
	MOV	L, A
	LXI	D, sin_lut
	DAD	D
	MOV	A, M
	RET
                                        ; -- End function
	.section	.text.zext_add,"ax",@progbits
	.globl	zext_add                        ; -- Begin function zext_add
zext_add:                               ; @zext_add
; %bb.0:
	MVI	E, 0
	MOV	D, E
	MOV	E, A
	DAD	D
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LDA	sin_lut+42
	STA	__v6clang_a.main
	LXI	H, 0x6e
	PUSH	H
	LDA	__v6clang_a.main
	POP	H
	LXI	H, 0
	RET
                                        ; -- End function
	.local	__v6clang_a.main                    ; @__v6clang_a.main
	.comm	__v6clang_a.main,3,1
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
	.addrsig_sym __v6clang_a.main
