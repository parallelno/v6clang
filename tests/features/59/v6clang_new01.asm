	.text
	.section	.text.test_de_b,"ax",@progbits
	.globl	test_de_b                       ; -- Begin function test_de_b
test_de_b:                              ; @test_de_b
; %bb.0:
	XCHG
	MOV	M, B
	XCHG
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
	MOV	M, B
	XCHG
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
	MOV	M, B
	XCHG
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
	MOV	M, B
	XCHG
	;APP
	OUT	0xde
	;NO_APP
	RET
                                        ; -- End function
	.section	.text.test_de_d,"ax",@progbits
	.globl	test_de_d                       ; -- Begin function test_de_d
test_de_d:                              ; @test_de_d
; %bb.0:
	XCHG
	MOV	M, B
	XCHG
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	RET
                                        ; -- End function
	.section	.text.test_de_e,"ax",@progbits
	.globl	test_de_e                       ; -- Begin function test_de_e
test_de_e:                              ; @test_de_e
; %bb.0:
	XCHG
	MOV	M, B
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
	XCHG
	SHLD	.LLo61_0+1
	XCHG
	SHLD	.LLo61_1+1
	LXI	H, 2
	DAD	SP
	MOV	E, M
	MOV	D, A
	MOV	A, E
	STAX	B
	MOV	A, D
	;APP
	OUT	0xde
	;NO_APP
.LLo61_1:
	LXI	H, 0
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
	LHLD	g_hl
	LDA	g_a
	MOV	E, A
	LDA	g_v
	STA	g_buf
	MOV	A, E
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	LHLD	g_hl
	LDA	g_a
	MOV	E, A
	LDA	g_v
	STA	g_buf
	MOV	A, E
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	LHLD	g_hl
	LDA	g_a
	MOV	L, A
	LDA	g_v
	STA	g_buf
	MOV	A, L
	;APP
	OUT	0xde
	;NO_APP
	LHLD	g_hl
	LDA	g_a
	MOV	L, A
	LDA	g_v
	STA	g_buf
	MOV	A, L
	;APP
	OUT	0xde
	;NO_APP
	LHLD	g_hl
	LDA	g_a
	MOV	E, A
	LDA	g_v
	STA	g_buf
	MOV	A, E
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	LHLD	g_hl
	LDA	g_a
	MOV	E, A
	LDA	g_v
	STA	g_buf
	MOV	A, E
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	LHLD	g_hl
	XCHG
	LHLD	g_de
	XCHG
	LDA	g_a
	MOV	C, A
	LDA	g_v
	STA	g_buf
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
	LXI	H, 0
	RET
                                        ; -- End function
	.data
	.globl	g_a                             ; @g_a
g_a:
	DB	18                              ; 0x12

	.globl	g_v                             ; @g_v
g_v:
	DB	119                             ; 0x77

	.section	.bss,"aw",@nobits
	.globl	g_buf                           ; @g_buf
g_buf:

	.data
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
	.addrsig_sym g_v
	.addrsig_sym g_hl
	.addrsig_sym g_de
