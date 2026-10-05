	.text
	.section	.text.leaf,"ax",@progbits
	.globl	leaf                            ; -- Begin function leaf
leaf:                                   ; @leaf
; %bb.0:
	INX	H
	SHLD	word_sink
	RET
                                        ; -- End function
	.section	.text.middle,"ax",@progbits
	.globl	middle                          ; -- Begin function middle
middle:                                 ; @middle
; %bb.0:
	MOV	A, L
	INX	H
	INX	H
	CALL	leaf
	STA	byte_sink
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	MVI	A, 0x5a
	STA	byte_sink
	LXI	H, 3
	CALL	middle
	LXI	H, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	word_sink                       ; @word_sink
word_sink:
	DW	0                               ; 0x0

	.globl	byte_sink                       ; @byte_sink
byte_sink:
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
	.addrsig_sym word_sink
	.addrsig_sym byte_sink
