	.text
	.section	.text.repro,"ax",@progbits
	.globl	repro                           ; -- Begin function repro
repro:                                  ; @repro
; %bb.0:
	MVI	A, 7
	STA	__v6clang_a.repro
	LDA	__v6clang_a.repro
	MOV	D, A
	ORA	A
	JZ	.LBB15_3
; %bb.1:
	MVI	E, 0
	LXI	H, perm1
.LBB15_2:                               ; =>This Inner Loop Header: Depth=1
	MOV	M, E
	INR	E
	CMP	E
	INX	H
	JNZ	.LBB15_2
.LBB15_3:
	MVI	E, 0
	LXI	B, count-1
.LBB15_4:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB15_5 Depth 2
	CPI	1
	JZ	.LBB15_6
.LBB15_5:                               ;   Parent Loop BB15_4 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	MOV	H, E
	MOV	L, A
	DAD	B
	MOV	M, A
	DCR	A
	CPI	1
	JNZ	.LBB15_5
.LBB15_6:                               ;   in Loop: Header=BB15_4 Depth=1
	MOV	A, D
	CPI	1
	RZ
.LBB15_8:                               ;   in Loop: Header=BB15_4 Depth=1
	LXI	H, count+1
	DCR	M
	MVI	A, 2
	JMP	.LBB15_4
                                        ; -- End function
	.section	.text.walk16,"ax",@progbits
	.globl	walk16                          ; -- Begin function walk16
walk16:                                 ; @walk16
; %bb.0:
	STA	__v6clang_a.walk16
	LDA	__v6clang_a.walk16
	ORA	A
	JZ	.LBB16_5
; %bb.1:
	LXI	D, 0
	STA	.LLo61_1+1
	SHLD	.LLo61_0+1
.LBB16_2:                               ; =>This Inner Loop Header: Depth=1
	STA	.LLo61_2+1
	MOV	C, M
	INX	H
	MOV	B, M
	DCX	H
	XCHG
	DAD	B
	XCHG
.LLo61_2:
	MVI	A, 0
	INX	H
	INX	H
	DCR	A
	JNZ	.LBB16_2
; %bb.3:
.LLo61_0:
	LXI	B, 0
	LDA	.LLo61_1+1
.LBB16_4:                               ; =>This Inner Loop Header: Depth=1
	STA	.LLo61_1+1
	LDAX	B
	MOV	L, A
	INX	B
	LDAX	B
	MOV	H, A
	DCX	B
	MOV	A, L
	XRA	E
	MOV	E, A
	MOV	A, H
	XRA	D
	MOV	D, A
.LLo61_1:
	MVI	A, 0
	INX	B
	INX	B
	DCR	A
	JNZ	.LBB16_4
; %bb.6:
	XCHG
	RET
.LBB16_5:
	LXI	D, 0
	XCHG
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	MVI	A, 7
	STA	__v6clang_a.main+1
	LDA	__v6clang_a.main+1
	MOV	D, A
	ORA	A
	JZ	.LBB17_3
; %bb.1:
	MVI	E, 0
	LXI	H, perm1
.LBB17_2:                               ; =>This Inner Loop Header: Depth=1
	MOV	M, E
	INR	E
	CMP	E
	INX	H
	JNZ	.LBB17_2
.LBB17_3:
	MVI	E, 0
	LXI	B, count-1
.LBB17_4:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB17_5 Depth 2
	CPI	1
	JZ	.LBB17_6
.LBB17_5:                               ;   Parent Loop BB17_4 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	MOV	H, E
	MOV	L, A
	DAD	B
	MOV	M, A
	DCR	A
	CPI	1
	JNZ	.LBB17_5
.LBB17_6:                               ;   in Loop: Header=BB17_4 Depth=1
	MOV	A, D
	CPI	1
	JZ	.LBB17_8
; %bb.7:                                ;   in Loop: Header=BB17_4 Depth=1
	LXI	H, count+1
	DCR	M
	MVI	A, 2
	JMP	.LBB17_4
.LBB17_8:
	STA	__v6clang_a.main+2
	MVI	A, 4
	STA	__v6clang_a.main
	LDA	__v6clang_a.main
	ORA	A
	JZ	.LBB17_12
; %bb.9:
	MOV	L, A
.LBB17_10:                              ; =>This Inner Loop Header: Depth=1
	DCR	L
	JNZ	.LBB17_10
.LBB17_11:                              ; =>This Inner Loop Header: Depth=1
	DCR	A
	JNZ	.LBB17_11
.LBB17_12:
	LXI	H, 0
	SHLD	__v6clang_a.main+3
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	perm1                           ; @perm1
perm1:

	.globl	count                           ; @count
count:

	.local	__v6clang_a.repro                   ; @__v6clang_a.repro
	.comm	__v6clang_a.repro,1,1
	.local	__v6clang_a.walk16                  ; @__v6clang_a.walk16
	.comm	__v6clang_a.walk16,1,1
	.local	__v6clang_a.main                    ; @__v6clang_a.main
	.comm	__v6clang_a.main,5,1
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
	.addrsig_sym __v6clang_a.repro
	.addrsig_sym __v6clang_a.walk16
	.addrsig_sym __v6clang_a.main
