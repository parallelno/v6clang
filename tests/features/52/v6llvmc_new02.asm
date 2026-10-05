	.text
	.section	.text.mul_u8,"ax",@progbits
	.globl	mul_u8                          ; -- Begin function mul_u8
mul_u8:                                 ; @mul_u8
	;=== char mul_u8(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = B
; %bb.0:
	MOV	L, A
	MOV	A, B
	MOV	B, L
	JMP	__mulqi3
                                        ; -- End function
	.section	.text.mul_u16,"ax",@progbits
	.globl	mul_u16                         ; -- Begin function mul_u16
mul_u16:                                ; @mul_u16
	;=== int mul_u16(int arg0, int arg1) ===
	;  arg0 = HL
	;  arg1 = DE
; %bb.0:
	JMP	__mulhi3
                                        ; -- End function
	.section	.text.div_u16,"ax",@progbits
	.globl	div_u16                         ; -- Begin function div_u16
div_u16:                                ; @div_u16
	;=== int div_u16(int arg0, int arg1) ===
	;  arg0 = HL
	;  arg1 = DE
; %bb.0:
	JMP	__udivhi3
                                        ; -- End function
	.section	.text.mod_u16,"ax",@progbits
	.globl	mod_u16                         ; -- Begin function mod_u16
mod_u16:                                ; @mod_u16
	;=== int mod_u16(int arg0, int arg1) ===
	;  arg0 = HL
	;  arg1 = DE
; %bb.0:
	JMP	__umodhi3
                                        ; -- End function
	.section	.text.shl_u16,"ax",@progbits
	.globl	shl_u16                         ; -- Begin function shl_u16
shl_u16:                                ; @shl_u16
	;=== int shl_u16(int arg0, char arg1) ===
	;  arg0 = HL
	;  arg1 = A
; %bb.0:
	MVI	E, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	D, E
	MOV	E, A
	JMP	__ashlhi3
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(void) ===
; %bb.0:
	LDA	g_u8a
	MOV	B, A
	LDA	g_u8b
	CALL	__mulqi3
	STA	g_u8r
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_u16a
	XCHG
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_u16b
	CALL	__mulhi3
	;--- V6CLANG_STORE16_G ---
	SHLD	g_u16r
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_u16a
	;--- V6CLANG_LOAD16_G ---
	XCHG
	LHLD	g_u16b
	XCHG
	CALL	__udivhi3
	;--- V6CLANG_STORE16_G ---
	SHLD	g_u16r
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_u16a
	;--- V6CLANG_LOAD16_G ---
	XCHG
	LHLD	g_u16b
	XCHG
	CALL	__umodhi3
	;--- V6CLANG_STORE16_G ---
	SHLD	g_u16r
	MVI	E, 0
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_u16a
	LDA	g_u8a
	;--- V6CLANG_BUILD_PAIR ---
	MOV	D, E
	MOV	E, A
	CALL	__ashlhi3
	;--- V6CLANG_STORE16_G ---
	SHLD	g_u16r
	LXI	H, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_u8a                           ; @g_u8a
g_u8a:
	DB	0                               ; 0x0

	.globl	g_u8b                           ; @g_u8b
g_u8b:
	DB	0                               ; 0x0

	.globl	g_u8r                           ; @g_u8r
g_u8r:
	DB	0                               ; 0x0

	.globl	g_u16a                          ; @g_u16a
g_u16a:
	DW	0                               ; 0x0

	.globl	g_u16b                          ; @g_u16b
g_u16b:
	DW	0                               ; 0x0

	.globl	g_u16r                          ; @g_u16r
g_u16r:
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
	.addrsig_sym g_u8a
	.addrsig_sym g_u8b
	.addrsig_sym g_u8r
	.addrsig_sym g_u16a
	.addrsig_sym g_u16b
	.addrsig_sym g_u16r
