	.text
	.section	.text.xor16_to_i8,"ax",@progbits
	.globl	xor16_to_i8                     ; -- Begin function xor16_to_i8
xor16_to_i8:                            ; @xor16_to_i8
; %bb.0:
	MOV	A, E
	XRA	L
	RET
                                        ; -- End function
	.section	.text.or16_to_i8,"ax",@progbits
	.globl	or16_to_i8                      ; -- Begin function or16_to_i8
or16_to_i8:                             ; @or16_to_i8
; %bb.0:
	MOV	A, E
	ORA	L
	RET
                                        ; -- End function
	.section	.text.and16_to_i8,"ax",@progbits
	.globl	and16_to_i8                     ; -- Begin function and16_to_i8
and16_to_i8:                            ; @and16_to_i8
; %bb.0:
	MOV	A, E
	ANA	L
	RET
                                        ; -- End function
	.section	.text.xor_bytes,"ax",@progbits
	.globl	xor_bytes                       ; -- Begin function xor_bytes
xor_bytes:                              ; @xor_bytes
; %bb.0:
	MOV	A, H
	XRA	L
	RET
                                        ; -- End function
	.section	.text.xor16_cmp_zero,"ax",@progbits
	.globl	xor16_cmp_zero                  ; -- Begin function xor16_cmp_zero
xor16_cmp_zero:                         ; @xor16_cmp_zero
; %bb.0:
	MOV	A, E
	XRA	L
	MOV	L, A
	XRA	A
	CMP	L
	JZ	.LBB19_2
; %bb.1:
	XRA	A
	RET
.LBB19_2:
	INR	A
	RET
                                        ; -- End function
	.section	.text.and16_cmp_zero,"ax",@progbits
	.globl	and16_cmp_zero                  ; -- Begin function and16_cmp_zero
and16_cmp_zero:                         ; @and16_cmp_zero
; %bb.0:
	MOV	A, L
	ANA	E
	MOV	L, A
	XRA	A
	CMP	L
	JZ	.LBB20_2
; %bb.1:
	XRA	A
	RET
.LBB20_2:
	INR	A
	RET
                                        ; -- End function
	.section	.text.or16_cmp_zero,"ax",@progbits
	.globl	or16_cmp_zero                   ; -- Begin function or16_cmp_zero
or16_cmp_zero:                          ; @or16_cmp_zero
; %bb.0:
	MOV	A, E
	ORA	L
	MOV	L, A
	XRA	A
	CMP	L
	JZ	.LBB21_2
; %bb.1:
	XRA	A
	RET
.LBB21_2:
	INR	A
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
	LXI	D, 0x5678
	CALL	xor16_to_i8
	STA	__v6clang_a.main
	LXI	H, 0xa5a5
	LXI	D, 0x5a5a
	CALL	or16_to_i8
	STA	__v6clang_a.main+1
	LXI	H, 0xf0f0
	LXI	D, 0xf0f
	CALL	and16_to_i8
	STA	__v6clang_a.main+2
	LXI	H, 0x1234
	CALL	xor_bytes
	STA	__v6clang_a.main+3
	LXI	D, 0x1234
	CALL	xor16_cmp_zero
	STA	__v6clang_a.main+4
	LXI	H, 0xff
	LXI	D, 0xff00
	CALL	and16_cmp_zero
	STA	__v6clang_a.main+5
	LXI	H, 1
	LXI	D, 0
	CALL	or16_cmp_zero
	STA	__v6clang_a.main+6
	LXI	H, 0x1234
	LXI	D, 0x5678
	CALL	xor16_full
	PUSH	H
	LDA	__v6clang_a.main
	LDA	__v6clang_a.main+1
	LDA	__v6clang_a.main+2
	LDA	__v6clang_a.main+3
	LDA	__v6clang_a.main+4
	LDA	__v6clang_a.main+5
	LDA	__v6clang_a.main+6
	POP	H
	LXI	H, 0
	RET
                                        ; -- End function
	.local	__v6clang_a.main                    ; @__v6clang_a.main
	.comm	__v6clang_a.main,9,1
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
