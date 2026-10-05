	.text
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(void) ===
; %bb.0:
	LXI	H, 0x1111
	LXI	D, 0x1141
	;--- V6CLANG_STORE16_P ---
	MOV	M, E
	INX	H
	MOV	M, D
	LXI	H, 0x2222
	LXI	D, 0x2252
	;--- V6CLANG_STORE16_P ---
	MOV	M, E
	INX	H
	MOV	M, D
	LXI	B, 0x3333
	;APP
	CALL	custom_cc

	;NO_APP
	MOV	A, C
	OUT	0xde
	;--- V6CLANG_SRL16 ---
	MOV	L, B
	MVI	H, 0
	MOV	A, L
	OUT	0xde
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
