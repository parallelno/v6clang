	.text
	.section	.text.fillscreen,"ax",@progbits
	.globl	fillscreen                      ; -- Begin function fillscreen
fillscreen:                             ; @fillscreen
; %bb.0:
	LXI	H, 0x7802
	XRA	A
	LXI	D, 0xf800
.LBB15_1:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB15_2 Depth 2
	STA	.LLo61_0+1
	MVI	C, 0x40
.LBB15_2:                               ;   Parent Loop BB15_1 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	LDAX	D
	ANI	4
	JZ	.LBB15_6
; %bb.3:                                ;   in Loop: Header=BB15_2 Depth=2
	MVI	A, 0x4f
	JMP	.LBB15_7
.LBB15_6:                               ;   in Loop: Header=BB15_2 Depth=2
	XRA	A
.LBB15_7:                               ;   in Loop: Header=BB15_2 Depth=2
	MOV	M, A
	INX	H
	INX	D
	DCR	C
	JNZ	.LBB15_2
; %bb.5:                                ;   in Loop: Header=BB15_1 Depth=1
	LXI	B, 0xf
	DAD	B
.LLo61_0:
	MVI	A, 0
	INR	A
	CPI	0x19
	JNZ	.LBB15_1
; %bb.4:
	RET
                                        ; -- End function
	.section	.text.fillscreen_nonzero,"ax",@progbits
	.globl	fillscreen_nonzero              ; -- Begin function fillscreen_nonzero
fillscreen_nonzero:                     ; @fillscreen_nonzero
; %bb.0:
	LXI	H, 0x7802
	XRA	A
	LXI	D, 0xf800
.LBB16_1:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB16_2 Depth 2
	STA	.LLo61_1+1
	MVI	C, 0x40
.LBB16_2:                               ;   Parent Loop BB16_1 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	LDAX	D
	ANI	4
	JZ	.LBB16_6
; %bb.3:                                ;   in Loop: Header=BB16_2 Depth=2
	MVI	A, 0xfe
	JMP	.LBB16_7
.LBB16_6:                               ;   in Loop: Header=BB16_2 Depth=2
	MVI	A, 1
.LBB16_7:                               ;   in Loop: Header=BB16_2 Depth=2
	MOV	M, A
	INX	H
	INX	D
	DCR	C
	JNZ	.LBB16_2
; %bb.5:                                ;   in Loop: Header=BB16_1 Depth=1
	LXI	B, 0xf
	DAD	B
.LLo61_1:
	MVI	A, 0
	INR	A
	CPI	0x19
	JNZ	.LBB16_1
; %bb.4:
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	H, 0x7802
	XRA	A
	LXI	D, 0xf800
.LBB17_1:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB17_2 Depth 2
	STA	.LLo61_2+1
	MVI	C, 0x40
.LBB17_2:                               ;   Parent Loop BB17_1 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	LDAX	D
	ANI	4
	JZ	.LBB17_5
; %bb.3:                                ;   in Loop: Header=BB17_2 Depth=2
	MVI	A, 0x4f
	JMP	.LBB17_6
.LBB17_5:                               ;   in Loop: Header=BB17_2 Depth=2
	XRA	A
.LBB17_6:                               ;   in Loop: Header=BB17_2 Depth=2
	MOV	M, A
	INX	H
	INX	D
	DCR	C
	JNZ	.LBB17_2
; %bb.4:                                ;   in Loop: Header=BB17_1 Depth=1
	LXI	B, 0xf
	DAD	B
.LLo61_2:
	MVI	A, 0
	INR	A
	CPI	0x19
	JNZ	.LBB17_1
; %bb.7:
	LXI	H, 0x7802
	XRA	A
	LXI	D, 0xf800
.LBB17_8:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB17_9 Depth 2
	STA	.LLo61_2+1
	MVI	C, 0x40
.LBB17_9:                               ;   Parent Loop BB17_8 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	LDAX	D
	ANI	4
	JZ	.LBB17_11
; %bb.10:                               ;   in Loop: Header=BB17_9 Depth=2
	MVI	A, 0xfe
	JMP	.LBB17_12
.LBB17_11:                              ;   in Loop: Header=BB17_9 Depth=2
	MVI	A, 1
.LBB17_12:                              ;   in Loop: Header=BB17_9 Depth=2
	MOV	M, A
	INX	H
	INX	D
	DCR	C
	JNZ	.LBB17_9
; %bb.14:                               ;   in Loop: Header=BB17_8 Depth=1
	LXI	B, 0xf
	DAD	B
	LDA	.LLo61_2+1
	INR	A
	CPI	0x19
	JNZ	.LBB17_8
; %bb.13:
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
