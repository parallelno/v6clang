	.text
	.section	.text.iter_xor_mix,"ax",@progbits
	.globl	iter_xor_mix                    ; -- Begin function iter_xor_mix
iter_xor_mix:                           ; @iter_xor_mix
; %bb.0:
	MVI	E, 0
	MOV	H, E
	MOV	L, A
	XRA	A
.LBB15_1:                               ; =>This Inner Loop Header: Depth=1
	MOV	C, A
	MOV	D, A
	MOV	A, C
	XRA	L
	MOV	C, A
	MOV	A, E
	XRA	H
	MOV	B, A
	DAD	B
	MOV	A, D
	INR	A
	CPI	0x40
	JNZ	.LBB15_1
; %bb.2:
	RET
                                        ; -- End function
	.section	.text.iter_xor_next,"ax",@progbits
	.globl	iter_xor_next                   ; -- Begin function iter_xor_next
iter_xor_next:                          ; @iter_xor_next
; %bb.0:
	MVI	E, 0
	MOV	H, E
	MOV	L, A
	MVI	A, 1
.LBB16_1:                               ; =>This Inner Loop Header: Depth=1
	MOV	C, A
	MOV	D, A
	MOV	A, C
	XRA	L
	MOV	C, A
	MOV	A, E
	XRA	H
	MOV	B, A
	DAD	B
	MOV	A, D
	INR	A
	CPI	0x41
	JNZ	.LBB16_1
; %bb.2:
	RET
                                        ; -- End function
	.section	.text.weighted_sum,"ax",@progbits
	.globl	weighted_sum                    ; -- Begin function weighted_sum
weighted_sum:                           ; @weighted_sum
; %bb.0:
	LXI	D, 0x40
	XCHG
	DAD	D
	SHLD	.LLo61_4+1
	XCHG
	LXI	D, 0
	LXI	B, 0
	PUSH	H
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_3+1
	POP	H
.LBB17_1:                               ; =>This Inner Loop Header: Depth=1
	XCHG
	SHLD	.LLo61_2+1
	XCHG
.LLo61_3:
	LXI	B, 0
	PUSH	H
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_0+1
	SHLD	.LLo61_1+1
	POP	H
	MOV	C, M
	XRA	A
	MOV	B, A
	MOV	A, C
	STA	.LLo61_5+1
	MOV	A, B
.LLo61_0:
	LXI	D, 0
.LLo61_1:
	LXI	D, 0
	XCHG
	DAD	B
	XCHG
	MOV	B, D
	MOV	C, E
.LLo61_2:
	LXI	D, 0
	MOV	A, E
	ADD	C
	MOV	C, A
	MOV	A, D
	ADC	B
	PUSH	H
	MOV	L, C
	MOV	H, A
	SHLD	.LLo61_3+1
	POP	H
	INX	D
	INX	H
.LLo61_4:
	LXI	B, 0
	MOV	A, L
	CMP	C
	JNZ	.LBB17_1
; %bb.3:                                ;   in Loop: Header=BB17_1 Depth=1
	MOV	A, H
	CMP	B
	JNZ	.LBB17_1
; %bb.2:
	XRA	A
.LLo61_5:
	MVI	L, 0
	MOV	H, A
	PUSH	H
	LHLD	.LLo61_0+1
	MOV	C, L
	MOV	B, H
	POP	H
	DAD	B
	DAD	D
	DCX	H
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	XRA	A
	LXI	H, __v6clang_a.main
.LBB18_1:                               ; =>This Inner Loop Header: Depth=1
	MOV	M, A
	INX	H
	INR	A
	CPI	0x40
	JNZ	.LBB18_1
; %bb.2:
	LXI	D, __v6clang_a.main
	LXI	H, 0
	LXI	B, 0
	PUSH	H
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_9+1
	POP	H
.LBB18_3:                               ; =>This Inner Loop Header: Depth=1
	SHLD	.LLo61_8+1
.LLo61_9:
	LXI	B, 0
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_6+1
	SHLD	.LLo61_7+1
	LDAX	D
	MOV	C, A
	XRA	A
	LXI	H, .LLo61_10+1
	MOV	M, C
	MOV	B, A
	LHLD	.LLo61_6+1
	DAD	B
	MOV	B, H
	MOV	C, L
.LLo61_8:
	LXI	H, 0
	PUSH	H
	DAD	B
	SHLD	.LLo61_9+1
	POP	H
	INX	H
	INX	D
	LXI	B, __v6clang_a.main+64
	MOV	A, E
	CMP	C
	JNZ	.LBB18_3
; %bb.5:                                ;   in Loop: Header=BB18_3 Depth=1
	MOV	A, D
	CMP	B
	JNZ	.LBB18_3
; %bb.4:
.LLo61_10:
	MVI	A, 0
	MOV	D, A
	MOV	E, A
.LLo61_7:
	LXI	B, 0
	XCHG
	DAD	B
	DAD	D
	LXI	D, 0x7c
	DAD	D
	LXI	D, 0xff
	MOV	A, L
	ANA	E
	MOV	L, A
	MOV	A, H
	ANA	D
	MOV	H, A
	RET
                                        ; -- End function
	.local	__v6clang_a.main                    ; @__v6clang_a.main
	.comm	__v6clang_a.main,64,1
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
