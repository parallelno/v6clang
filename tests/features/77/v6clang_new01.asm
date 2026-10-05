	.text
	.section	.text.xor16_const,"ax",@progbits
	.globl	xor16_const                     ; -- Begin function xor16_const
xor16_const:                            ; @xor16_const
; %bb.0:
	MVI	A, 0x3c
	XRA	L
	MOV	L, A
	MVI	A, 0xb4
	XRA	H
	MOV	H, A
	RET
                                        ; -- End function
	.section	.text.xor16_hi_only,"ax",@progbits
	.globl	xor16_hi_only                   ; -- Begin function xor16_hi_only
xor16_hi_only:                          ; @xor16_hi_only
; %bb.0:
	MVI	A, 0xb4
	XRA	H
	MOV	H, A
	RET
                                        ; -- End function
	.section	.text.or16_lo_only,"ax",@progbits
	.globl	or16_lo_only                    ; -- Begin function or16_lo_only
or16_lo_only:                           ; @or16_lo_only
; %bb.0:
	MVI	A, 0x80
	ORA	L
	MOV	L, A
	RET
                                        ; -- End function
	.section	.text.and16_clear_lo,"ax",@progbits
	.globl	and16_clear_lo                  ; -- Begin function and16_clear_lo
and16_clear_lo:                         ; @and16_clear_lo
; %bb.0:
	MVI	L, 0
	RET
                                        ; -- End function
	.section	.text.and16_mask,"ax",@progbits
	.globl	and16_mask                      ; -- Begin function and16_mask
and16_mask:                             ; @and16_mask
; %bb.0:
	MVI	A, 0xf
	ANA	L
	MOV	L, A
	MVI	A, 0xf0
	ANA	H
	MOV	H, A
	RET
                                        ; -- End function
	.section	.text.or16_set_all,"ax",@progbits
	.globl	or16_set_all                    ; -- Begin function or16_set_all
or16_set_all:                           ; @or16_set_all
; %bb.0:
	LXI	H, 0xffff
	RET
                                        ; -- End function
	.section	.text.lfsr_run,"ax",@progbits
	.globl	lfsr_run                        ; -- Begin function lfsr_run
lfsr_run:                               ; @lfsr_run
; %bb.0:
	MOV	E, A
	XRA	A
	CMP	E
	RZ
.LBB21_2:                               ; =>This Inner Loop Header: Depth=1
	MOV	D, L
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, D
	ANI	1
	JZ	.LBB21_4
; %bb.3:                                ;   in Loop: Header=BB21_2 Depth=1
	MVI	A, 0xb4
	XRA	H
	MOV	H, A
.LBB21_4:                               ;   in Loop: Header=BB21_2 Depth=1
	DCR	E
	JNZ	.LBB21_2
; %bb.1:
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	H, 0x1234
	CALL	xor16_const
	PUSH	H
	LXI	H, 0x1234
	CALL	xor16_hi_only
	SHLD	__v6clang_a.main+2
	LXI	H, 0x1234
	CALL	or16_lo_only
	SHLD	__v6clang_a.main+4
	LXI	H, 0x1234
	CALL	and16_clear_lo
	SHLD	__v6clang_a.main+6
	LXI	H, 0x1234
	CALL	and16_mask
	SHLD	__v6clang_a.main+8
	LXI	H, 0xffff
	SHLD	__v6clang_a.main+10
	LXI	H, 0xace1
	MVI	A, 0x10
	CALL	lfsr_run
	SHLD	__v6clang_a.main+12
	POP	H
	LHLD	__v6clang_a.main+2
	LHLD	__v6clang_a.main+4
	LHLD	__v6clang_a.main+6
	LHLD	__v6clang_a.main+8
	LHLD	__v6clang_a.main+10
	LHLD	__v6clang_a.main+12
	LXI	H, 0
	RET
                                        ; -- End function
	.local	__v6clang_a.main                    ; @__v6clang_a.main
	.comm	__v6clang_a.main,14,1
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
