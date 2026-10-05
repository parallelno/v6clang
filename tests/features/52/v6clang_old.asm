	.text
	.section	.text.mul_u8,"ax",@progbits
	.globl	mul_u8                          ; -- Begin function mul_u8
mul_u8:                                 ; @mul_u8
; %bb.0:
	MOV	H, A
	MOV	L, B
	MOV	D, A
	MOV	E, A
	CALL	__mulhi3
	MOV	A, L
	RET
                                        ; -- End function
	.section	.text.mul_u16,"ax",@progbits
	.globl	mul_u16                         ; -- Begin function mul_u16
mul_u16:                                ; @mul_u16
; %bb.0:
	MOV	B, H
	MOV	C, L
	XCHG
	MOV	D, B
	MOV	E, C
	JMP	__mulhi3
                                        ; -- End function
	.section	.text.div_u16,"ax",@progbits
	.globl	div_u16                         ; -- Begin function div_u16
div_u16:                                ; @div_u16
; %bb.0:
	JMP	__udivhi3
                                        ; -- End function
	.section	.text.mod_u16,"ax",@progbits
	.globl	mod_u16                         ; -- Begin function mod_u16
mod_u16:                                ; @mod_u16
; %bb.0:
	JMP	__umodhi3
                                        ; -- End function
	.section	.text.shl_u16,"ax",@progbits
	.globl	shl_u16                         ; -- Begin function shl_u16
shl_u16:                                ; @shl_u16
; %bb.0:
	MVI	E, 0
	MOV	D, E
	MOV	E, A
	JMP	__ashlhi3
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LDA	g_u8a
	MOV	D, A
	MOV	E, A
	LDA	g_u8b
	MOV	H, A
	MOV	L, A
	CALL	__mulhi3
	MOV	A, L
	STA	g_u8r
	XCHG
	LHLD	g_u16a
	XCHG
	LHLD	g_u16b
	CALL	__mulhi3
	SHLD	g_u16r
	LHLD	g_u16a
	XCHG
	LHLD	g_u16b
	XCHG
	CALL	__udivhi3
	SHLD	g_u16r
	LHLD	g_u16a
	XCHG
	LHLD	g_u16b
	XCHG
	CALL	__umodhi3
	SHLD	g_u16r
	MVI	E, 0
	LHLD	g_u16a
	LDA	g_u8a
	MOV	D, E
	MOV	E, A
	CALL	__ashlhi3
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
	.addrsig_sym g_u8a
	.addrsig_sym g_u8b
	.addrsig_sym g_u8r
	.addrsig_sym g_u16a
	.addrsig_sym g_u16b
	.addrsig_sym g_u16r
