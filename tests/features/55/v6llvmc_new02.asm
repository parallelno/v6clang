	.text
	.section	.text.case1_dst_hl,"ax",@progbits
	.globl	case1_dst_hl                    ; -- Begin function case1_dst_hl
case1_dst_hl:                           ; @case1_dst_hl
; %bb.0:
	LHLD	g_a
	RET
                                        ; -- End function
	.section	.text.case2_dst_de,"ax",@progbits
	.globl	case2_dst_de                    ; -- Begin function case2_dst_de
case2_dst_de:                           ; @case2_dst_de
; %bb.0:
	XCHG
	LHLD	g_a
	DAD	D
	RET
                                        ; -- End function
	.section	.text.add3,"ax",@progbits
	.globl	add3                            ; -- Begin function add3
add3:                                   ; @add3
; %bb.0:
	DAD	D
	DAD	B
	RET
                                        ; -- End function
	.section	.text.case3_dst_bc,"ax",@progbits
	.globl	case3_dst_bc                    ; -- Begin function case3_dst_bc
case3_dst_bc:                           ; @case3_dst_bc
; %bb.0:
	LHLD	g_a
	XCHG
	LHLD	g_b
	XCHG
	LDA	g_c
	MOV	C, A
	LDA	g_c+1
	MOV	B, A
	JMP	add3
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	H, 0x1234
	SHLD	g_a
	LXI	H, 0x5678
	PUSH	H
	LXI	H, 1
	SHLD	g_c
	LHLD	g_a
	PUSH	H
	POP	H
	MOV	A, L
	OUT	0xde
	LXI	H, 0x100
	XCHG
	LHLD	g_a
	XCHG
	DAD	D
	PUSH	H
	POP	H
	MOV	A, L
	OUT	0xde
	LHLD	g_a
	XCHG
	POP	H
	XCHG
	LDA	g_c
	MOV	C, A
	LDA	g_c+1
	MOV	B, A
	CALL	add3
	PUSH	H
	POP	H
	MOV	A, L
	OUT	0xde
	LXI	H, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_a                             ; @g_a
g_a:
	DW	0                               ; 0x0

	.globl	g_b                             ; @g_b
g_b:
	DW	0                               ; 0x0

	.globl	g_c                             ; @g_c
g_c:
	DW	0                               ; 0x0

	.globl	g_r                             ; @g_r
g_r:
	DW	0                               ; 0x0

	.globl	g_byte                          ; @g_byte
g_byte:
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
	.addrsig_sym g_a
	.addrsig_sym g_b
	.addrsig_sym g_c
	.addrsig_sym g_r
