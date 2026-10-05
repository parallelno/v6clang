	.text
	.section	.text.xor16_cmp_zero,"ax",@progbits
	.globl	xor16_cmp_zero                  ; -- Begin function xor16_cmp_zero
xor16_cmp_zero:                         ; @xor16_cmp_zero
; %bb.0:
	MOV	A, E
	XRA	L
	JZ	.LBB15_2
; %bb.1:
	XRA	A
	RET
.LBB15_2:
	INR	A
	RET
                                        ; -- End function
	.section	.text.and16_cmp_zero,"ax",@progbits
	.globl	and16_cmp_zero                  ; -- Begin function and16_cmp_zero
and16_cmp_zero:                         ; @and16_cmp_zero
; %bb.0:
	MOV	A, L
	ANA	E
	JZ	.LBB16_2
; %bb.1:
	XRA	A
	RET
.LBB16_2:
	INR	A
	RET
                                        ; -- End function
	.section	.text.or16_cmp_zero,"ax",@progbits
	.globl	or16_cmp_zero                   ; -- Begin function or16_cmp_zero
or16_cmp_zero:                          ; @or16_cmp_zero
; %bb.0:
	MOV	A, E
	ORA	L
	JZ	.LBB17_2
; %bb.1:
	XRA	A
	RET
.LBB17_2:
	INR	A
	RET
                                        ; -- End function
	.section	.text.xor16_to_i8,"ax",@progbits
	.globl	xor16_to_i8                     ; -- Begin function xor16_to_i8
xor16_to_i8:                            ; @xor16_to_i8
; %bb.0:
	MOV	A, E
	XRA	L
	RET
                                        ; -- End function
	.section	.text.xor16_full,"ax",@progbits
	.globl	xor16_full                      ; -- Begin function xor16_full
xor16_full:                             ; @xor16_full
; %bb.0:
	MOV	A, E
	XRA	L
	MOV	L, A
	MOV	A, D
	XRA	H
	MOV	H, A
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	H, 0x1234
	LXI	D, 0x1234
	CALL	xor16_cmp_zero
	STA	__v6clang_a.main
	LXI	H, 0xff
	LXI	D, 0xff00
	CALL	and16_cmp_zero
	STA	__v6clang_a.main+1
	LXI	H, 1
	LXI	D, 0
	CALL	or16_cmp_zero
	STA	__v6clang_a.main+2
	LXI	H, 0x1234
	LXI	D, 0x5678
	CALL	xor16_to_i8
	STA	__v6clang_a.main+3
	LXI	D, 0x5678
	CALL	xor16_full
	SHLD	__v6clang_a.main+4
	LXI	H, 0
	RET
                                        ; -- End function
	.local	__v6clang_a.main                    ; @__v6clang_a.main
	.comm	__v6clang_a.main,6,1
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
