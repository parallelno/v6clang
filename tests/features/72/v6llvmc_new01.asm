	.text
	.section	.text.and_lsb_branch,"ax",@progbits
	.globl	and_lsb_branch                  ; -- Begin function and_lsb_branch
and_lsb_branch:                         ; @and_lsb_branch
; %bb.0:
	MOV	A, L
	ANI	1
	RET
                                        ; -- End function
	.section	.text.and_nibble,"ax",@progbits
	.globl	and_nibble                      ; -- Begin function and_nibble
and_nibble:                             ; @and_nibble
; %bb.0:
	MOV	A, L
	ANI	0xf
	RET
                                        ; -- End function
	.section	.text.or_hi_bit,"ax",@progbits
	.globl	or_hi_bit                       ; -- Begin function or_hi_bit
or_hi_bit:                              ; @or_hi_bit
; %bb.0:
	MOV	A, L
	ORI	0x80
	RET
                                        ; -- End function
	.section	.text.xor_pattern,"ax",@progbits
	.globl	xor_pattern                     ; -- Begin function xor_pattern
xor_pattern:                            ; @xor_pattern
; %bb.0:
	MOV	A, L
	XRI	0x55
	RET
                                        ; -- End function
	.section	.text.and_wide,"ax",@progbits
	.globl	and_wide                        ; -- Begin function and_wide
and_wide:                               ; @and_wide
; %bb.0:
	LXI	D, 0xf0f
	MOV	A, L
	ANA	E
	MOV	L, A
	MOV	A, H
	ANA	D
	MOV	H, A
	RET
                                        ; -- End function
	.section	.text.lfsr_step,"ax",@progbits
	.globl	lfsr_step                       ; -- Begin function lfsr_step
lfsr_step:                              ; @lfsr_step
; %bb.0:
	XCHG
	LXI	H, 0
	MVI	C, 0x10
.LBB20_1:                               ; =>This Inner Loop Header: Depth=1
	XCHG
	SHLD	.LLo61_0+1
	XCHG
.LLo61_0:
	LXI	D, 0
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	XCHG
	SHLD	.LLo61_1+1
	SHLD	.LLo61_2+1
	LHLD	.LLo61_0+1
	XCHG
	MOV	A, E
	ANI	1
	JNZ	.LBB20_2
; %bb.3:                                ;   in Loop: Header=BB20_1 Depth=1
.LLo61_2:
	LXI	D, 0
	JMP	.LBB20_4
.LBB20_2:                               ;   in Loop: Header=BB20_1 Depth=1
	LXI	D, 0xb4
	SHLD	.LLo61_0+1
	MOV	L, C
.LLo61_1:
	LXI	B, 0
	MOV	A, C
	XRA	E
	MOV	E, A
	MOV	A, B
	XRA	D
	MOV	D, A
	MOV	C, L
	LHLD	.LLo61_0+1
.LBB20_4:                               ;   in Loop: Header=BB20_1 Depth=1
	MOV	A, E
	XRA	L
	MOV	L, A
	MOV	A, D
	XRA	H
	MOV	H, A
	DCR	C
	JNZ	.LBB20_1
; %bb.5:
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	H, 0x1235
	CALL	and_lsb_branch
	STA	__v6clang_a.main
	LXI	H, 0xabcd
	CALL	and_nibble
	STA	__v6clang_a.main+1
	LXI	H, 0x42
	CALL	or_hi_bit
	STA	__v6clang_a.main+2
	LXI	H, 0xaa
	CALL	xor_pattern
	STA	__v6clang_a.main+3
	LXI	H, 0xffff
	CALL	and_wide
	PUSH	H
	LXI	H, 0xace1
	CALL	lfsr_step
	SHLD	__v6clang_a.main+6
	LDA	__v6clang_a.main
	LDA	__v6clang_a.main+1
	LDA	__v6clang_a.main+2
	LDA	__v6clang_a.main+3
	POP	H
	LHLD	__v6clang_a.main+6
	LXI	H, 0
	RET
                                        ; -- End function
	.local	__v6clang_a.main                    ; @__v6clang_a.main
	.comm	__v6clang_a.main,8,1
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
