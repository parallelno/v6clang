	.text
	.section	.text.neg_i16_unary,"ax",@progbits
	.globl	neg_i16_unary                   ; -- Begin function neg_i16_unary
neg_i16_unary:                          ; @neg_i16_unary
.Lfunc_begin0:
	;=== int neg_i16_unary(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: neg_i16_unary:x <- $hl
	;--- V6CLANG_NEG16 ---
	XRA	A
	SUB	L
	MOV	L, A
	MVI	A, 0
	SBB	H
	MOV	H, A
	RET
.Lfunc_end0:
                                        ; -- End function
	.section	.text.neg_i16_mul_left,"ax",@progbits
	.globl	neg_i16_mul_left                ; -- Begin function neg_i16_mul_left
neg_i16_mul_left:                       ; @neg_i16_mul_left
.Lfunc_begin1:
	;=== int neg_i16_mul_left(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: neg_i16_mul_left:x <- $hl
	;--- V6CLANG_NEG16 ---
	XRA	A
	SUB	L
	MOV	L, A
	MVI	A, 0
	SBB	H
	MOV	H, A
	RET
.Lfunc_end1:
                                        ; -- End function
	.section	.text.neg_i16_mul_right,"ax",@progbits
	.globl	neg_i16_mul_right               ; -- Begin function neg_i16_mul_right
neg_i16_mul_right:                      ; @neg_i16_mul_right
.Lfunc_begin2:
	;=== int neg_i16_mul_right(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: neg_i16_mul_right:x <- $hl
	;--- V6CLANG_NEG16 ---
	XRA	A
	SUB	L
	MOV	L, A
	MVI	A, 0
	SBB	H
	MOV	H, A
	RET
.Lfunc_end2:
                                        ; -- End function
	.section	.text.neg_i8_unary,"ax",@progbits
	.globl	neg_i8_unary                    ; -- Begin function neg_i8_unary
neg_i8_unary:                           ; @neg_i8_unary
.Lfunc_begin3:
	;=== char neg_i8_unary(char x) ===
	;  x = A
; %bb.0:
	;DEBUG_VALUE: neg_i8_unary:x <- $a
	;--- V6CLANG_NEG8 ---
	CMA
	INR	A
	RET
.Lfunc_end3:
                                        ; -- End function
	.section	.text.neg_i16_global_unary,"ax",@progbits
	.globl	neg_i16_global_unary            ; -- Begin function neg_i16_global_unary
neg_i16_global_unary:                   ; @neg_i16_global_unary
.Lfunc_begin4:
	;=== int neg_i16_global_unary(void) ===
; %bb.0:
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_i16
	;--- V6CLANG_NEG16 ---
	XRA	A
	SUB	L
	MOV	L, A
	MVI	A, 0
	SBB	H
	MOV	H, A
	RET
.Lfunc_end4:
                                        ; -- End function
	.section	.text.neg_i8_global_unary,"ax",@progbits
	.globl	neg_i8_global_unary             ; -- Begin function neg_i8_global_unary
neg_i8_global_unary:                    ; @neg_i8_global_unary
.Lfunc_begin5:
	;=== char neg_i8_global_unary(void) ===
; %bb.0:
	LXI	H, g_i8
	XRA	A
	;--- V6CLANG_SUB_M_P ---
	SUB	M
	RET
.Lfunc_end5:
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
.Lfunc_begin6:
	;=== int main(int argc, void* argv) ===
	;  argc = HL
	;  argv = DE
; %bb.0:
	;DEBUG_VALUE: main:argc <- $hl
	;DEBUG_VALUE: main:argv <- $de
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_i16
	;DEBUG_VALUE: neg_i16_unary:x <- $hl
	;--- V6CLANG_NEG16 ---
	XRA	A
	SUB	L
	MOV	L, A
	MVI	A, 0
	SBB	H
	MOV	H, A
	;--- V6CLANG_STORE16_G ---
	SHLD	out_i16
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_i16
	;DEBUG_VALUE: neg_i16_mul_left:x <- $hl
	;--- V6CLANG_NEG16 ---
	XRA	A
	SUB	L
	MOV	L, A
	MVI	A, 0
	SBB	H
	MOV	H, A
	;--- V6CLANG_STORE16_G ---
	SHLD	out_i16
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_i16
	;DEBUG_VALUE: neg_i16_mul_right:x <- $hl
	;--- V6CLANG_NEG16 ---
	XRA	A
	SUB	L
	MOV	L, A
	MVI	A, 0
	SBB	H
	MOV	H, A
	;--- V6CLANG_STORE16_G ---
	SHLD	out_i16
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_i16
	;--- V6CLANG_NEG16 ---
	XRA	A
	SUB	L
	MOV	L, A
	MVI	A, 0
	SBB	H
	MOV	H, A
	;--- V6CLANG_STORE16_G ---
	SHLD	out_i16
	LXI	H, g_i8
	;DEBUG_VALUE: neg_i8_unary:x <- undef
	XRA	A
	;--- V6CLANG_SUB_M_P ---
	SUB	M
	STA	out_i8
	XRA	A
	;--- V6CLANG_SUB_M_P ---
	SUB	M
	STA	out_i8
	LXI	H, 0
	RET
.Lfunc_end6:
                                        ; -- End function
	.data
	.globl	g_i16                           ; @g_i16
	.p2align	1, 0x0
g_i16:
	DW	33059                           ; 0x8123

	.globl	g_i8                            ; @g_i8
g_i8:
	DB	147                             ; 0x93

	.section	.bss,"aw",@nobits
	.globl	out_i16                         ; @out_i16
	.p2align	1, 0x0
out_i16:
	DW	0                               ; 0x0

	.globl	out_i8                          ; @out_i8
out_i8:
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
	.addrsig_sym g_i16
	.addrsig_sym g_i8
	.addrsig_sym out_i16
	.addrsig_sym out_i8
