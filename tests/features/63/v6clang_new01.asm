	.text
	.section	.text.test_dead_hi,"ax",@progbits
	.globl	test_dead_hi                    ; -- Begin function test_dead_hi
test_dead_hi:                           ; @test_dead_hi
; %bb.0:
	CALL	get_val
	MOV	A, H
	JMP	use_byte
                                        ; -- End function
	.section	.text.test_chain_and_dead_hi,"ax",@progbits
	.globl	test_chain_and_dead_hi          ; -- Begin function test_chain_and_dead_hi
test_chain_and_dead_hi:                 ; @test_chain_and_dead_hi
; %bb.0:
	CALL	get_val
	MOV	A, L
	MOV	B, H
	JMP	draw_stub
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	CALL	get_val
	MOV	A, H
	CALL	use_byte
	CALL	get_val
	MOV	A, L
	MOV	B, H
	CALL	draw_stub
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
