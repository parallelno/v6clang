	.text
	.section	.text.dec_loop,"ax",@progbits
	.globl	dec_loop                        ; -- Begin function dec_loop
dec_loop:                               ; @dec_loop
; %bb.0:
	ORA	A
	JZ	.LBB15_3
; %bb.1:
	MOV	L, A
	XRA	A
	MOV	D, A
	MOV	E, L
	MOV	A, L
	LXI	H, 0
.LBB15_2:                               ; =>This Inner Loop Header: Depth=1
	MOV	C, A
	DAD	D
	MOV	A, C
	DCX	D
	STA	g_sink
	DCR	A
	JNZ	.LBB15_2
; %bb.4:
	RET
.LBB15_3:
	LXI	H, 0
	RET
                                        ; -- End function
	.section	.text.mask_test,"ax",@progbits
	.globl	mask_test                       ; -- Begin function mask_test
mask_test:                              ; @mask_test
; %bb.0:
	ANI	0xf
	JNZ	.LBB16_2
; %bb.1:
	INR	A
	RET
.LBB16_2:
	XRA	A
	RET
                                        ; -- End function
	.section	.text.xor_test,"ax",@progbits
	.globl	xor_test                        ; -- Begin function xor_test
xor_test:                               ; @xor_test
; %bb.0:
	MOV	L, A
	MOV	A, B
	XRA	L
	MOV	L, A
	JZ	.LBB17_2
; %bb.1:
	MVI	H, 1
	JMP	.LBB17_3
.LBB17_2:
	MOV	H, A
.LBB17_3:
	MOV	A, L
	STA	g_sink
	MOV	A, H
	RET
                                        ; -- End function
	.section	.text.sub_test,"ax",@progbits
	.globl	sub_test                        ; -- Begin function sub_test
sub_test:                               ; @sub_test
; %bb.0:
	ADI	0xfb
	JZ	.LBB18_2
; %bb.1:
	MVI	L, 1
	JMP	.LBB18_3
.LBB18_2:
	MOV	L, A
.LBB18_3:
	STA	g_sink
	MOV	A, L
	RET
                                        ; -- End function
	.section	.text.dec_loop_used,"ax",@progbits
	.globl	dec_loop_used                   ; -- Begin function dec_loop_used
dec_loop_used:                          ; @dec_loop_used
; %bb.0:
	ORA	A
	JZ	.LBB19_3
; %bb.1:
	MOV	L, A
	XRA	A
	MOV	D, A
	MOV	E, L
	MOV	A, L
	LXI	H, 0
.LBB19_2:                               ; =>This Inner Loop Header: Depth=1
	MOV	C, A
	DAD	D
	MOV	A, C
	DCX	D
	STA	g_sink
	DCR	A
	JNZ	.LBB19_2
; %bb.4:
	RET
.LBB19_3:
	LXI	H, 0
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LDA	g_n
	ORA	A
	JZ	.LBB20_3
; %bb.1:
	MOV	L, A
	XRA	A
	MOV	D, A
	MOV	E, L
	MOV	A, L
	LXI	H, 0
.LBB20_2:                               ; =>This Inner Loop Header: Depth=1
	MOV	C, A
	DAD	D
	MOV	A, C
	DCX	D
	STA	g_sink
	DCR	A
	JNZ	.LBB20_2
	JMP	.LBB20_4
.LBB20_3:
	LXI	H, 0
.LBB20_4:
	SHLD	g_out
	LXI	H, g_x
	MVI	A, 0xf
	ANA	M
	MVI	C, 0
	MOV	A, C
	JNZ	.LBB20_6
; %bb.5:
	INR	A
.LBB20_6:
	STA	g_outb
	LXI	D, g_y
	LDA	g_x
	XCHG
	XRA	M
	XCHG
	STA	g_sink
	MVI	A, 0
	JZ	.LBB20_8
; %bb.7:
	INR	A
.LBB20_8:
	STA	g_outb
	MVI	A, 0xfb
	ADD	M
	JZ	.LBB20_10
; %bb.9:
	MVI	C, 1
.LBB20_10:
	STA	g_sink
	MOV	A, C
	STA	g_outb
	LDA	g_n
	ORA	A
	JZ	.LBB20_13
; %bb.11:
	MOV	L, A
	XRA	A
	MOV	D, A
	MOV	E, L
	MOV	A, L
	LXI	H, 0
.LBB20_12:                              ; =>This Inner Loop Header: Depth=1
	MOV	C, A
	DAD	D
	MOV	A, C
	DCX	D
	STA	g_sink
	DCR	A
	JNZ	.LBB20_12
	JMP	.LBB20_14
.LBB20_13:
	LXI	H, 0
.LBB20_14:
	SHLD	g_out
	LXI	H, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_sink                          ; @g_sink
g_sink:
	DB	0                               ; 0x0

	.data
	.globl	g_n                             ; @g_n
g_n:
	DB	7                               ; 0x7

	.globl	g_x                             ; @g_x
g_x:
	DB	51                              ; 0x33

	.globl	g_y                             ; @g_y
g_y:
	DB	51                              ; 0x33

	.section	.bss,"aw",@nobits
	.globl	g_out                           ; @g_out
	.p2align	1, 0x0
g_out:
	DW	0                               ; 0x0

	.globl	g_outb                          ; @g_outb
g_outb:
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
	.addrsig_sym g_sink
	.addrsig_sym g_n
	.addrsig_sym g_x
	.addrsig_sym g_y
	.addrsig_sym g_out
	.addrsig_sym g_outb
