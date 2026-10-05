	.text
	.section	.text.__mulqi3,"ax",@progbits
__mulqi3:                               ; -- Begin function __mulqi3
                                        ; @__mulqi3
; %bb.0:
	;APP
	MOV	E, B
	MVI	D, 0
	LXI	H, 0
	MVI	B, 8
.Ltmp0:
	DAD	H
	RLC

	JNC	.Ltmp1
	DAD	D
.Ltmp1:
	DCR	B
	JNZ	.Ltmp0
	MOV	A, L
	RET


	;NO_APP
                                        ; -- End function
	.section	.text.__v6clang_mulqihi3,"ax",@progbits
__v6clang_mulqihi3:                         ; -- Begin function __v6clang_mulqihi3
                                        ; @__v6clang_mulqihi3
; %bb.0:
	;APP
	MOV	E, B
	MVI	D, 0
	LXI	H, 0
	MVI	B, 8
.Ltmp2:
	DAD	H
	RLC

	JNC	.Ltmp3
	DAD	D
.Ltmp3:
	DCR	B
	JNZ	.Ltmp2
	RET


	;NO_APP
                                        ; -- End function
	.section	.text.__mulhi3,"ax",@progbits
__mulhi3:                               ; -- Begin function __mulhi3
                                        ; @__mulhi3
; %bb.0:
	;APP
	XCHG

	MOV	A, H
	MOV	C, L
	LXI	H, 0
	MVI	B, 8
.Ltmp4:
	DAD	H
	RLC

	JNC	.Ltmp5
	DAD	D
.Ltmp5:
	DCR	B
	JNZ	.Ltmp4
	MOV	A, C
	MVI	B, 8
.Ltmp6:
	DAD	H
	RLC

	JNC	.Ltmp7
	DAD	D
.Ltmp7:
	DCR	B
	JNZ	.Ltmp6
	RET


	;NO_APP
                                        ; -- End function
	.section	.text.__v6clang_udivmod16_body,"ax",@progbits
__v6clang_udivmod16_body:                   ; -- Begin function __v6clang_udivmod16_body
                                        ; @__v6clang_udivmod16_body
; %bb.0:
	;APP
	MOV	A, D
	ORA	E
	JNZ	.Ltmp8
	LXI	H, 0xffff
	LXI	B, 0
	RET

.Ltmp8:
	LXI	B, 0
	MVI	A, 0x10
	PUSH	PSW
.Ltmp9:
	DAD	H
	MOV	A, C
	RAL

	MOV	C, A
	MOV	A, B
	RAL

	MOV	B, A
	MOV	A, C
	SUB	E
	MOV	A, B
	SBB	D
	JC	.Ltmp10
	MOV	A, C
	SUB	E
	MOV	C, A
	MOV	A, B
	SBB	D
	MOV	B, A
	INX	H
.Ltmp10:
	POP	PSW
	DCR	A
	PUSH	PSW
	JNZ	.Ltmp9
	POP	PSW
	RET


	;NO_APP
                                        ; -- End function
	.section	.text.__udivhi3,"ax",@progbits
__udivhi3:                              ; -- Begin function __udivhi3
                                        ; @__udivhi3
; %bb.0:
	;APP
	CALL	__v6clang_udivmod16_body
	RET


	;NO_APP
                                        ; -- End function
	.section	.text.__umodhi3,"ax",@progbits
__umodhi3:                              ; -- Begin function __umodhi3
                                        ; @__umodhi3
; %bb.0:
	;APP
	CALL	__v6clang_udivmod16_body
	MOV	H, B
	MOV	L, C
	RET


	;NO_APP
                                        ; -- End function
	.section	.text.__udivmodhi4,"ax",@progbits
__udivmodhi4:                           ; -- Begin function __udivmodhi4
                                        ; @__udivmodhi4
; %bb.0:
	;APP
	PUSH	B
	CALL	__v6clang_udivmod16_body
	XTHL

	MOV	M, C
	INX	H
	MOV	M, B
	POP	H
	RET


	;NO_APP
                                        ; -- End function
	.section	.text.__divmodhi4,"ax",@progbits
__divmodhi4:                            ; -- Begin function __divmodhi4
                                        ; @__divmodhi4
; %bb.0:
	;APP
	PUSH	B
	MOV	A, H
	PUSH	PSW
	MOV	A, H
	XRA	D
	PUSH	PSW
	MOV	A, H
	ORA	A
	JP	.Ltmp11
	CALL	__v6clang_neg_hl_body
.Ltmp11:
	MOV	A, D
	ORA	A
	JP	.Ltmp12
	CALL	__v6clang_neg_de_body
.Ltmp12:
	CALL	__v6clang_udivmod16_body
	POP	PSW
	ORA	A
	JP	.Ltmp13
	CALL	__v6clang_neg_hl_body
.Ltmp13:
	POP	PSW
	ORA	A
	JP	.Ltmp14
	MOV	A, C
	CMA

	MOV	C, A
	MOV	A, B
	CMA

	MOV	B, A
	INX	B
.Ltmp14:
	XTHL

	MOV	M, C
	INX	H
	MOV	M, B
	POP	H
	RET


	;NO_APP
                                        ; -- End function
	.section	.text.__v6clang_neg_hl_body,"ax",@progbits
__v6clang_neg_hl_body:                      ; -- Begin function __v6clang_neg_hl_body
                                        ; @__v6clang_neg_hl_body
; %bb.0:
	;APP
	MOV	A, L
	CMA

	MOV	L, A
	MOV	A, H
	CMA

	MOV	H, A
	INX	H
	RET


	;NO_APP
                                        ; -- End function
	.section	.text.__v6clang_neg_de_body,"ax",@progbits
__v6clang_neg_de_body:                      ; -- Begin function __v6clang_neg_de_body
                                        ; @__v6clang_neg_de_body
; %bb.0:
	;APP
	MOV	A, E
	CMA

	MOV	E, A
	MOV	A, D
	CMA

	MOV	D, A
	INX	D
	RET


	;NO_APP
                                        ; -- End function
	.section	.text.__divhi3,"ax",@progbits
__divhi3:                               ; -- Begin function __divhi3
                                        ; @__divhi3
; %bb.0:
	;APP
	MOV	A, H
	XRA	D
	PUSH	PSW
	MOV	A, H
	ORA	A
	JP	.Ltmp15
	CALL	__v6clang_neg_hl_body
.Ltmp15:
	MOV	A, D
	ORA	A
	JP	.Ltmp16
	CALL	__v6clang_neg_de_body
.Ltmp16:
	CALL	__v6clang_udivmod16_body
	POP	PSW
	ORA	A
	JP	.Ltmp17
	CALL	__v6clang_neg_hl_body
.Ltmp17:
	RET


	;NO_APP
                                        ; -- End function
	.section	.text.__modhi3,"ax",@progbits
__modhi3:                               ; -- Begin function __modhi3
                                        ; @__modhi3
; %bb.0:
	;APP
	MOV	A, H
	PUSH	PSW
	ORA	A
	JP	.Ltmp18
	CALL	__v6clang_neg_hl_body
.Ltmp18:
	MOV	A, D
	ORA	A
	JP	.Ltmp19
	CALL	__v6clang_neg_de_body
.Ltmp19:
	CALL	__v6clang_udivmod16_body
	MOV	H, B
	MOV	L, C
	POP	PSW
	ORA	A
	JP	.Ltmp20
	CALL	__v6clang_neg_hl_body
.Ltmp20:
	RET


	;NO_APP
                                        ; -- End function
	.section	.text.__ashlhi3,"ax",@progbits
__ashlhi3:                              ; -- Begin function __ashlhi3
                                        ; @__ashlhi3
; %bb.0:
	;APP
	MOV	A, E
	ANI	0xf
	JZ	.Ltmp21
	CPI	0x10
	JNC	.Ltmp22
	MOV	E, A
.Ltmp23:
	DAD	H
	DCR	E
	JNZ	.Ltmp23
.Ltmp21:
	RET

.Ltmp22:
	LXI	H, 0
	RET


	;NO_APP
                                        ; -- End function
	.section	.text.__lshrhi3,"ax",@progbits
__lshrhi3:                              ; -- Begin function __lshrhi3
                                        ; @__lshrhi3
; %bb.0:
	;APP
	MOV	A, E
	ANI	0xf
	JZ	.Ltmp24
	CPI	0x10
	JNC	.Ltmp25
	MOV	E, A
.Ltmp26:
	ORA	A
	MOV	A, H
	RAR

	MOV	H, A
	MOV	A, L
	RAR

	MOV	L, A
	DCR	E
	JNZ	.Ltmp26
.Ltmp24:
	RET

.Ltmp25:
	LXI	H, 0
	RET


	;NO_APP
                                        ; -- End function
	.section	.text.__ashrhi3,"ax",@progbits
__ashrhi3:                              ; -- Begin function __ashrhi3
                                        ; @__ashrhi3
; %bb.0:
	;APP
	MOV	A, E
	ANI	0xf
	JZ	.Ltmp27
	CPI	0x10
	JNC	.Ltmp28
	MOV	E, A
.Ltmp29:
	MOV	A, H
	RAL

	MOV	A, H
	RAR

	MOV	H, A
	MOV	A, L
	RAR

	MOV	L, A
	DCR	E
	JNZ	.Ltmp29
.Ltmp27:
	RET

.Ltmp28:
	MOV	A, H
	RAL

	SBB	A
	MOV	H, A
	MOV	L, A
	RET


	;NO_APP
                                        ; -- End function
	.section	.text.bug3_de_de,"ax",@progbits
	.globl	bug3_de_de                      ; -- Begin function bug3_de_de
bug3_de_de:                             ; @bug3_de_de
; %bb.0:
	XCHG
	MOV	E, M
	INX	H
	MOV	D, M
	DAD	D
	RET
                                        ; -- End function
	.section	.text.case2_hl_reused,"ax",@progbits
	.globl	case2_hl_reused                 ; -- Begin function case2_hl_reused
case2_hl_reused:                        ; @case2_hl_reused
; %bb.0:
	MOV	A, M
	INX	H
	MOV	H, M
	MOV	L, A
	DAD	H
	RET
                                        ; -- End function
	.section	.text.case5_bc_with_hl_live,"ax",@progbits
	.globl	case5_bc_with_hl_live           ; -- Begin function case5_bc_with_hl_live
case5_bc_with_hl_live:                  ; @case5_bc_with_hl_live
; %bb.0:
	MOV	A, M
	INX	H
	MOV	H, M
	MOV	L, A
	DAD	D
	RET
                                        ; -- End function
	.section	.text.case16_a_live,"ax",@progbits
	.globl	case16_a_live                   ; -- Begin function case16_a_live
case16_a_live:                          ; @case16_a_live
; %bb.0:
	INX	H
	XRA	M
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	H, 0x2234
	PUSH	H
	POP	H
	MOV	A, L
	STA	g_byte
	LDA	g_byte
	OUT	0xde
	LXI	H, 0xacf0
	PUSH	H
	POP	H
	MOV	A, L
	OUT	0xde
	LXI	H, 0x1235
	PUSH	H
	POP	H
	MOV	A, L
	OUT	0xde
	MVI	A, 0x14
	STA	g_byte
	LDA	g_byte
	OUT	0xde
	LXI	H, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_r                             ; @g_r
g_r:
	DW	0                               ; 0x0

	.globl	g_byte                          ; @g_byte
g_byte:
	DB	0                               ; 0x0

	.globl	g_a                             ; @g_a
g_a:
	DW	0                               ; 0x0

	.globl	g_b                             ; @g_b
g_b:
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
	.addrsig_sym g_r
	.addrsig_sym g_byte
