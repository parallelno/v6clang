	.text
	.section	.text.test_hl,"ax",@progbits
	.globl	test_hl                         ; -- Begin function test_hl
test_hl:                                ; @test_hl
; %bb.0:
	MVI	M, 0x42
	RET
                                        ; -- End function
	.section	.text.test_bc_a_dead,"ax",@progbits
	.globl	test_bc_a_dead                  ; -- Begin function test_bc_a_dead
test_bc_a_dead:                         ; @test_bc_a_dead
; %bb.0:
	PUSH	H
	MOV	L, C
	MOV	H, B
	MVI	M, 0x42
	POP	H
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	RET
                                        ; -- End function
	.section	.text.test_de_a_dead,"ax",@progbits
	.globl	test_de_a_dead                  ; -- Begin function test_de_a_dead
test_de_a_dead:                         ; @test_de_a_dead
; %bb.0:
	XCHG
	MVI	M, 0x42
	XCHG
	;APP
	OUT	0xde
	;NO_APP
	RET
                                        ; -- End function
	.section	.text.test_de_a_live,"ax",@progbits
	.globl	test_de_a_live                  ; -- Begin function test_de_a_live
test_de_a_live:                         ; @test_de_a_live
; %bb.0:
	XCHG
	MVI	M, 0x42
	XCHG
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	RET
                                        ; -- End function
	.section	.text.test_bc_hl_dead,"ax",@progbits
	.globl	test_bc_hl_dead                 ; -- Begin function test_bc_hl_dead
test_bc_hl_dead:                        ; @test_bc_hl_dead
; %bb.0:
	;APP
	OUT	0xde
	;NO_APP
	MOV	L, C
	MOV	H, B
	MVI	M, 0x42
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	RET
                                        ; -- End function
	.section	.text.test_bc_de_dead,"ax",@progbits
	.globl	test_bc_de_dead                 ; -- Begin function test_bc_de_dead
test_bc_de_dead:                        ; @test_bc_de_dead
; %bb.0:
	;APP
	OUT	0xde
	;NO_APP
	PUSH	H
	MOV	L, C
	MOV	H, B
	MVI	M, 0x42
	POP	H
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	RET
                                        ; -- End function
	.section	.text.test_bc_all_live,"ax",@progbits
	.globl	test_bc_all_live                ; -- Begin function test_bc_all_live
test_bc_all_live:                       ; @test_bc_all_live
; %bb.0:
	PUSH	H
	MOV	L, C
	MOV	H, B
	MVI	M, 0x42
	POP	H
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
	MVI	A, 0x42
	STA	g_buf
	LHLD	g_hl
	XCHG
	LHLD	g_de
	XCHG
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	STA	g_buf
	LHLD	g_hl
	;APP
	OUT	0xde
	;NO_APP
	STA	g_buf
	LHLD	g_hl
	LDA	g_a
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
	;APP
	OUT	0xde
	;NO_APP
	MVI	A, 0x42
	STA	g_buf
	MOV	A, C
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
	;APP
	OUT	0xde
	;NO_APP
	MVI	A, 0x42
	STA	g_buf
	MOV	A, C
	;APP
	OUT	0xde
	;NO_APP
	;APP
	OUT	0xde
	;NO_APP
	MVI	A, 0x42
	STA	g_buf
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
	LXI	H, 0
	RET
                                        ; -- End function
	.data
	.globl	g_a                             ; @g_a
g_a:
	DB	18                              ; 0x12

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
	.addrsig_sym g_hl
	.addrsig_sym g_de
