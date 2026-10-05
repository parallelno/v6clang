	.text
	.section	.text.case1_val_hl,"ax",@progbits
	.globl	case1_val_hl                    ; -- Begin function case1_val_hl
case1_val_hl:                           ; @case1_val_hl
; %bb.0:
	SHLD	g_a
	RET
                                        ; -- End function
	.section	.text.case2a_val_de_hl_dead,"ax",@progbits
	.globl	case2a_val_de_hl_dead           ; -- Begin function case2a_val_de_hl_dead
case2a_val_de_hl_dead:                  ; @case2a_val_de_hl_dead
; %bb.0:
	XCHG
	SHLD	g_a
	RET
                                        ; -- End function
	.section	.text.case2b_val_de_hl_live,"ax",@progbits
	.globl	case2b_val_de_hl_live           ; -- Begin function case2b_val_de_hl_live
case2b_val_de_hl_live:                  ; @case2b_val_de_hl_live
; %bb.0:
	XCHG
	SHLD	g_a
	XCHG
	RET
                                        ; -- End function
	.section	.text.case3a_val_bc_hl_dead,"ax",@progbits
	.globl	case3a_val_bc_hl_dead           ; -- Begin function case3a_val_bc_hl_dead
case3a_val_bc_hl_dead:                  ; @case3a_val_bc_hl_dead
; %bb.0:
	MOV	H, B
	MOV	L, C
	SHLD	g_a
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	H, 0x1234
	CALL	case1_val_hl
	LHLD	g_a
	MOV	A, L
	OUT	0xde
	LXI	D, 0x55aa
	CALL	case2a_val_de_hl_dead
	LHLD	g_a
	MOV	A, L
	OUT	0xde
	LXI	H, 0x9988
	LXI	D, 0x6677
	CALL	case2b_val_de_hl_live
	LHLD	g_a
	MOV	A, L
	OUT	0xde
	MVI	A, 0x88
	OUT	0xde
	LXI	B, 0xabcd
	CALL	case3a_val_bc_hl_dead
	LHLD	g_a
	MOV	A, L
	OUT	0xde
	LXI	H, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_a                             ; @g_a
g_a:
	DW	0                               ; 0x0

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
