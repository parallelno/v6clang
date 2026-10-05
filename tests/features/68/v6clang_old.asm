	.text
	.section	.text.shl_u16_3,"ax",@progbits
	.globl	shl_u16_3                       ; -- Begin function shl_u16_3
shl_u16_3:                              ; @shl_u16_3
; %bb.0:
	DAD	H
	DAD	H
	DAD	H
	RET
                                        ; -- End function
	.section	.text.shl_u16_9,"ax",@progbits
	.globl	shl_u16_9                       ; -- Begin function shl_u16_9
shl_u16_9:                              ; @shl_u16_9
; %bb.0:
	MOV	A, L
	ADD	A
	MVI	L, 0
	MOV	H, A
	RET
                                        ; -- End function
	.section	.text.shl_u16_13,"ax",@progbits
	.globl	shl_u16_13                      ; -- Begin function shl_u16_13
shl_u16_13:                             ; @shl_u16_13
; %bb.0:
	MOV	A, L
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	MVI	L, 0
	MOV	H, A
	RET
                                        ; -- End function
	.section	.text.shl_u16_15,"ax",@progbits
	.globl	shl_u16_15                      ; -- Begin function shl_u16_15
shl_u16_15:                             ; @shl_u16_15
; %bb.0:
	MOV	A, L
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	MVI	L, 0
	MOV	H, A
	RET
                                        ; -- End function
	.section	.text.shr_u16_1,"ax",@progbits
	.globl	shr_u16_1                       ; -- Begin function shr_u16_1
shr_u16_1:                              ; @shr_u16_1
; %bb.0:
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	RET
                                        ; -- End function
	.section	.text.shr_u16_2,"ax",@progbits
	.globl	shr_u16_2                       ; -- Begin function shr_u16_2
shr_u16_2:                              ; @shr_u16_2
; %bb.0:
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	RET
                                        ; -- End function
	.section	.text.shr_u16_7,"ax",@progbits
	.globl	shr_u16_7                       ; -- Begin function shr_u16_7
shr_u16_7:                              ; @shr_u16_7
; %bb.0:
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	RET
                                        ; -- End function
	.section	.text.shr_u16_9,"ax",@progbits
	.globl	shr_u16_9                       ; -- Begin function shr_u16_9
shr_u16_9:                              ; @shr_u16_9
; %bb.0:
	MOV	L, H
	MVI	H, 0
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	RET
                                        ; -- End function
	.section	.text.shr_u16_15,"ax",@progbits
	.globl	shr_u16_15                      ; -- Begin function shr_u16_15
shr_u16_15:                             ; @shr_u16_15
; %bb.0:
	MOV	L, H
	MVI	H, 0
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	RET
                                        ; -- End function
	.section	.text.sar_i16_7,"ax",@progbits
	.globl	sar_i16_7                       ; -- Begin function sar_i16_7
sar_i16_7:                              ; @sar_i16_7
; %bb.0:
	MOV	A, H
	RLC
	MOV	A, H
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	RLC
	MOV	A, H
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	RLC
	MOV	A, H
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	RLC
	MOV	A, H
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	RLC
	MOV	A, H
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	RLC
	MOV	A, H
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	RLC
	MOV	A, H
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	RET
                                        ; -- End function
	.section	.text.sar_i16_9,"ax",@progbits
	.globl	sar_i16_9                       ; -- Begin function sar_i16_9
sar_i16_9:                              ; @sar_i16_9
; %bb.0:
	MOV	A, H
	MOV	L, H
	RLC
	SBB	A
	MOV	H, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	RET
                                        ; -- End function
	.section	.text.sar_i16_15,"ax",@progbits
	.globl	sar_i16_15                      ; -- Begin function sar_i16_15
sar_i16_15:                             ; @sar_i16_15
; %bb.0:
	MOV	A, H
	MOV	L, H
	RLC
	SBB	A
	MOV	H, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LHLD	g_u
	DAD	H
	DAD	H
	DAD	H
	SHLD	g_out_u
	LHLD	g_u
	MOV	A, L
	ADD	A
	MVI	L, 0
	MOV	D, A
	MOV	E, L
	XCHG
	SHLD	g_out_u
	LHLD	g_u
	XCHG
	MOV	A, E
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	MOV	D, A
	MOV	E, L
	XCHG
	SHLD	g_out_u
	LHLD	g_u
	XCHG
	MOV	A, E
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	MOV	H, A
	SHLD	g_out_u
	LHLD	g_u
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	SHLD	g_out_u
	LHLD	g_u
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	SHLD	g_out_u
	LHLD	g_u
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	SHLD	g_out_u
	LHLD	g_u
	MOV	L, H
	MVI	H, 0
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	SHLD	g_out_u
	LHLD	g_u
	MOV	L, H
	MVI	H, 0
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	MOV	A, L
	ORA	A
	RAR
	MOV	L, A
	SHLD	g_out_u
	LHLD	g_s
	MOV	A, H
	RLC
	MOV	A, H
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	RLC
	MOV	A, H
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	RLC
	MOV	A, H
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	RLC
	MOV	A, H
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	RLC
	MOV	A, H
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	RLC
	MOV	A, H
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	RLC
	MOV	A, H
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	SHLD	g_out_s
	LHLD	g_s
	MOV	A, H
	MOV	L, H
	RLC
	SBB	A
	MOV	H, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	SHLD	g_out_s
	LHLD	g_s
	MOV	A, H
	MOV	L, H
	RLC
	SBB	A
	MOV	H, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	SHLD	g_out_s
	LXI	H, 0
	RET
                                        ; -- End function
	.data
	.globl	g_u                             ; @g_u
	.p2align	1, 0x0
g_u:
	DW	37428                           ; 0x9234

	.globl	g_s                             ; @g_s
	.p2align	1, 0x0
g_s:
	DW	37428                           ; 0x9234

	.section	.bss,"aw",@nobits
	.globl	g_out_u                         ; @g_out_u
	.p2align	1, 0x0
g_out_u:
	DW	0                               ; 0x0

	.globl	g_out_s                         ; @g_out_s
	.p2align	1, 0x0
g_out_s:
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
	.addrsig_sym g_u
	.addrsig_sym g_s
	.addrsig_sym g_out_u
	.addrsig_sym g_out_s
