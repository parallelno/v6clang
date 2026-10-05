	.text
	.section	.text.const_zero,"ax",@progbits
	.globl	const_zero                      ; -- Begin function const_zero
const_zero:                             ; @const_zero
; %bb.0:
	XRA	A
	RET
                                        ; -- End function
	.section	.text.clear_sink_twice,"ax",@progbits
	.globl	clear_sink_twice                ; -- Begin function clear_sink_twice
clear_sink_twice:                       ; @clear_sink_twice
; %bb.0:
	XRA	A
	STA	g_sink
	STA	g_sink
	RET
                                        ; -- End function
	.section	.text.neg_or_seven,"ax",@progbits
	.globl	neg_or_seven                    ; -- Begin function neg_or_seven
neg_or_seven:                           ; @neg_or_seven
; %bb.0:
	CMP	B
	JP	.LBB2_2
; %bb.1:
	XRA	A
	RET
.LBB2_2:
	MVI	A, 7
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	XRA	A
	STA	g_out
	STA	g_sink
	STA	g_sink
	LXI	H, g_b
	LDA	g_a
	CMP	M
	JP	.LBB3_2
; %bb.1:
	XRA	A
	JMP	.LBB3_3
.LBB3_2:
	MVI	A, 7
.LBB3_3:
	STA	g_out
	LXI	H, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_sink                          ; @g_sink
g_sink:
	DB	0                               ; 0x0

	.data
	.globl	g_a                             ; @g_a
g_a:
	DB	253                             ; 0xfd

	.globl	g_b                             ; @g_b
g_b:
	DB	4                               ; 0x4

	.section	.bss,"aw",@nobits
	.globl	g_out                           ; @g_out
g_out:
	DB	0                               ; 0x0

	.addrsig
	.addrsig_sym g_sink
	.addrsig_sym g_a
	.addrsig_sym g_b
	.addrsig_sym g_out
