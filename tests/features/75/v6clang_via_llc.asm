	.text
	.globl	lxi_lo_used                     ; -- Begin function lxi_lo_used
lxi_lo_used:                            ; @lxi_lo_used
; %bb.0:
	LXI	D, 0xb4ff
	MOV	A, L
	XRA	E
	MOV	L, A
	MOV	A, H
	XRA	D
	MOV	H, A
	SHLD	g_sink16
	MOV	A, E
	RET
                                        ; -- End function
	.globl	lxi_hi_used                     ; -- Begin function lxi_hi_used
lxi_hi_used:                            ; @lxi_hi_used
; %bb.0:
	LXI	D, 0xb4ff
	MOV	A, L
	XRA	E
	MOV	L, A
	MOV	A, H
	XRA	D
	MOV	H, A
	SHLD	g_sink16
	MOV	A, D
	RET
                                        ; -- End function
	.globl	lxi_lo_to_b                     ; -- Begin function lxi_lo_to_b
lxi_lo_to_b:                            ; @lxi_lo_to_b
; %bb.0:
	LXI	D, 0x9a37
	MOV	A, L
	XRA	E
	MOV	L, A
	MOV	A, H
	XRA	D
	MOV	H, A
	SHLD	g_sink16
	LXI	H, 0x37
	RET
                                        ; -- End function
	.globl	lxi_lo_zero                     ; -- Begin function lxi_lo_zero
lxi_lo_zero:                            ; @lxi_lo_zero
; %bb.0:
	LXI	D, 0xb400
	MOV	A, L
	XRA	E
	MOV	L, A
	MOV	A, H
	XRA	D
	MOV	H, A
	SHLD	g_sink16
	XRA	A
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	H, 0xa6cb
	SHLD	g_sink16
	MVI	A, 0xff
	STA	g_sink8
	LXI	H, 0xe287
	SHLD	g_sink16
	MVI	A, 0xb4
	STA	g_sink8
	LXI	H, 0x8b
	SHLD	g_sink16
	LXI	H, 0x37
	SHLD	g_sink16
	LXI	H, 0x6af0
	SHLD	g_sink16
	XRA	A
	STA	g_sink8
	LXI	H, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_sink16                        ; @g_sink16
	.p2align	1, 0x0
g_sink16:
	DW	0                               ; 0x0

	.globl	g_sink8                         ; @g_sink8
g_sink8:
	DB	0                               ; 0x0

