	.text
	.section	.text.test_de_b,"ax",@progbits
	.globl	test_de_b                       ; -- Begin function test_de_b
test_de_b:                              ; @test_de_b
; %bb.0:
	XCHG
	MOV	B, M
	XCHG
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	RET
                                        ; -- End function
	.section	.text.test_de_c,"ax",@progbits
	.globl	test_de_c                       ; -- Begin function test_de_c
test_de_c:                              ; @test_de_c
; %bb.0:
	XCHG
	MOV	C, M
	XCHG
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	RET
                                        ; -- End function
	.section	.text.test_de_h,"ax",@progbits
	.globl	test_de_h                       ; -- Begin function test_de_h
test_de_h:                              ; @test_de_h
; %bb.0:
	XCHG
	MOV	D, M
	XCHG
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	RET
                                        ; -- End function
	.section	.text.test_de_l,"ax",@progbits
	.globl	test_de_l                       ; -- Begin function test_de_l
test_de_l:                              ; @test_de_l
; %bb.0:
	XCHG
	MOV	E, M
	XCHG
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	RET
                                        ; -- End function
	.section	.text.test_bc_b,"ax",@progbits
	.globl	test_bc_b                       ; -- Begin function test_bc_b
test_bc_b:                              ; @test_bc_b
; %bb.0:
	MOV	C, A
	LDAX	B
	MOV	B, A
	MOV	A, C
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LDA	g_buf
	MOV	B, A
	LHLD	g_hl
	LDA	g_a
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	LDA	g_buf
	MOV	C, A
	LHLD	g_hl
	LDA	g_a
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	LHLD	g_hl
	LDA	g_buf
	MOV	H, A
	LDA	g_a
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	LHLD	g_hl
	LDA	g_buf
	MOV	L, A
	LDA	g_a
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	LDA	g_buf
	MOV	B, A
	LHLD	g_hl
	XCHG
	LHLD	g_de
	XCHG
	LDA	g_a
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	LXI	H, 0
	RET
                                        ; -- End function
	.data
	.globl	g_a                             ; @g_a
g_a:
	DB	18                              ; 0x12

	.globl	g_buf                           ; @g_buf
g_buf:
	DB	119

	.globl	g_hl                            ; @g_hl
g_hl:
	DW	4660                            ; 0x1234

	.globl	g_de                            ; @g_de
g_de:
	DW	22136                           ; 0x5678

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
	.addrsig_sym g_a
	.addrsig_sym g_hl
	.addrsig_sym g_de
