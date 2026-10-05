	.text
	.section	.text.xor16_to_i8,"ax",@progbits
	.globl	xor16_to_i8                     ; -- Begin function xor16_to_i8
xor16_to_i8:                            ; @xor16_to_i8
.Lfunc_begin0:
	;=== char xor16_to_i8(int a, int b) ===
	;  a = HL
	;  b = DE
; %bb.0:
	;DEBUG_VALUE: xor16_to_i8:a <- $hl
	;DEBUG_VALUE: xor16_to_i8:b <- $de
	;--- V6CLANG_XOR16 ---
	MOV	A, E
	XRA	L
	RET
.Lfunc_end0:
                                        ; -- End function
	.section	.text.or16_to_i8,"ax",@progbits
	.globl	or16_to_i8                      ; -- Begin function or16_to_i8
or16_to_i8:                             ; @or16_to_i8
.Lfunc_begin1:
	;=== char or16_to_i8(int a, int b) ===
	;  a = HL
	;  b = DE
; %bb.0:
	;DEBUG_VALUE: or16_to_i8:a <- $hl
	;DEBUG_VALUE: or16_to_i8:b <- $de
	;--- V6CLANG_OR16 ---
	MOV	A, E
	ORA	L
	RET
.Lfunc_end1:
                                        ; -- End function
	.section	.text.and16_to_i8,"ax",@progbits
	.globl	and16_to_i8                     ; -- Begin function and16_to_i8
and16_to_i8:                            ; @and16_to_i8
.Lfunc_begin2:
	;=== char and16_to_i8(int a, int b) ===
	;  a = HL
	;  b = DE
; %bb.0:
	;DEBUG_VALUE: and16_to_i8:a <- $hl
	;DEBUG_VALUE: and16_to_i8:b <- $de
	;--- V6CLANG_AND16 ---
	MOV	A, E
	ANA	L
	RET
.Lfunc_end2:
                                        ; -- End function
	.section	.text.xor_bytes,"ax",@progbits
	.globl	xor_bytes                       ; -- Begin function xor_bytes
xor_bytes:                              ; @xor_bytes
.Lfunc_begin3:
	;=== char xor_bytes(int a) ===
	;  a = HL
; %bb.0:
	;DEBUG_VALUE: xor_bytes:a <- $hl
	;--- V6CLANG_SRL16_BYTE ---
	;--- V6CLANG_XOR16 ---
	MOV	A, H
	XRA	L
	RET
.Lfunc_end3:
                                        ; -- End function
	.section	.text.xor16_cmp_zero,"ax",@progbits
	.globl	xor16_cmp_zero                  ; -- Begin function xor16_cmp_zero
xor16_cmp_zero:                         ; @xor16_cmp_zero
.Lfunc_begin4:
	;=== char xor16_cmp_zero(int a, int b) ===
	;  a = HL
	;  b = DE
; %bb.0:
	;DEBUG_VALUE: xor16_cmp_zero:a <- $hl
	;DEBUG_VALUE: xor16_cmp_zero:b <- $de
	;--- V6CLANG_XOR16 ---
	MOV	A, E
	XRA	L
	;--- V6CLANG_CMP8_ZERO ---
	JZ	.LBB19_2
; %bb.1:
	;DEBUG_VALUE: xor16_cmp_zero:b <- $de
	;DEBUG_VALUE: xor16_cmp_zero:a <- $hl
	XRA	A
	RET
.LBB19_2:
	;DEBUG_VALUE: xor16_cmp_zero:b <- $de
	;DEBUG_VALUE: xor16_cmp_zero:a <- $hl
	INR	A
	RET
.Lfunc_end4:
                                        ; -- End function
	.section	.text.and16_cmp_zero,"ax",@progbits
	.globl	and16_cmp_zero                  ; -- Begin function and16_cmp_zero
and16_cmp_zero:                         ; @and16_cmp_zero
.Lfunc_begin5:
	;=== char and16_cmp_zero(int a, int b) ===
	;  a = HL
	;  b = DE
; %bb.0:
	;DEBUG_VALUE: and16_cmp_zero:a <- $hl
	;DEBUG_VALUE: and16_cmp_zero:b <- $de
	;--- V6CLANG_AND16 ---
	MOV	A, L
	ANA	E
	;--- V6CLANG_CMP8_ZERO ---
	JZ	.LBB20_2
; %bb.1:
	;DEBUG_VALUE: and16_cmp_zero:b <- $de
	;DEBUG_VALUE: and16_cmp_zero:a <- $hl
	XRA	A
	RET
.LBB20_2:
	;DEBUG_VALUE: and16_cmp_zero:b <- $de
	;DEBUG_VALUE: and16_cmp_zero:a <- $hl
	INR	A
	RET
.Lfunc_end5:
                                        ; -- End function
	.section	.text.or16_cmp_zero,"ax",@progbits
	.globl	or16_cmp_zero                   ; -- Begin function or16_cmp_zero
or16_cmp_zero:                          ; @or16_cmp_zero
.Lfunc_begin6:
	;=== char or16_cmp_zero(int a, int b) ===
	;  a = HL
	;  b = DE
; %bb.0:
	;DEBUG_VALUE: or16_cmp_zero:a <- $hl
	;DEBUG_VALUE: or16_cmp_zero:b <- $de
	;--- V6CLANG_OR16 ---
	MOV	A, E
	ORA	L
	;--- V6CLANG_CMP8_ZERO ---
	JZ	.LBB21_2
; %bb.1:
	;DEBUG_VALUE: or16_cmp_zero:b <- $de
	;DEBUG_VALUE: or16_cmp_zero:a <- $hl
	XRA	A
	RET
.LBB21_2:
	;DEBUG_VALUE: or16_cmp_zero:b <- $de
	;DEBUG_VALUE: or16_cmp_zero:a <- $hl
	INR	A
	RET
.Lfunc_end6:
                                        ; -- End function
	.section	.text.xor16_full,"ax",@progbits
	.globl	xor16_full                      ; -- Begin function xor16_full
xor16_full:                             ; @xor16_full
.Lfunc_begin7:
	;=== int xor16_full(int a, int b) ===
	;  a = HL
	;  b = DE
; %bb.0:
	;DEBUG_VALUE: xor16_full:a <- $hl
	;DEBUG_VALUE: xor16_full:b <- $de
	;--- V6CLANG_XOR16 ---
	MOV	A, E
	XRA	L
	MOV	L, A
	MOV	A, D
	XRA	H
	MOV	H, A
	RET
.Lfunc_end7:
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
.Lfunc_begin8:
	;=== int main(void) ===
; %bb.0:
	LXI	H, 0x1234
	LXI	D, 0x5678
	CALL	xor16_to_i8
	STA	__v6clang_a.main
	;DEBUG_VALUE: main:r1 <- undef
	LXI	H, 0xa5a5
	LXI	D, 0x5a5a
	CALL	or16_to_i8
	STA	__v6clang_a.main+1
	;DEBUG_VALUE: main:r2 <- undef
	LXI	H, 0xf0f0
	LXI	D, 0xf0f
	CALL	and16_to_i8
	STA	__v6clang_a.main+2
	;DEBUG_VALUE: main:r3 <- undef
	LXI	H, 0x1234
	CALL	xor_bytes
	STA	__v6clang_a.main+3
	;DEBUG_VALUE: main:r4 <- undef
	LXI	D, 0x1234
	CALL	xor16_cmp_zero
	STA	__v6clang_a.main+4
	;DEBUG_VALUE: main:r5 <- undef
	LXI	H, 0xff
	LXI	D, 0xff00
	CALL	and16_cmp_zero
	STA	__v6clang_a.main+5
	;DEBUG_VALUE: main:r6 <- undef
	LXI	H, 1
	LXI	D, 0
	CALL	or16_cmp_zero
	STA	__v6clang_a.main+6
	;DEBUG_VALUE: main:r7 <- undef
	LXI	H, 0x1234
	LXI	D, 0x5678
	CALL	xor16_full
	;--- V6CLANG_STORE16_G ---
	PUSH	H
	;DEBUG_VALUE: main:r8 <- undef
	LDA	__v6clang_a.main
	LDA	__v6clang_a.main+1
	LDA	__v6clang_a.main+2
	LDA	__v6clang_a.main+3
	LDA	__v6clang_a.main+4
	LDA	__v6clang_a.main+5
	LDA	__v6clang_a.main+6
	;--- V6CLANG_LOAD16_G ---
	POP	H
	LXI	H, 0
	RET
.Lfunc_end8:
                                        ; -- End function
	.local	__v6clang_a.main                    ; @__v6clang_a.main
	.comm	__v6clang_a.main,9,1
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
