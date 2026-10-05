	.text
	.section	.text.rotl_u16_1,"ax",@progbits
	.globl	rotl_u16_1                      ; -- Begin function rotl_u16_1
rotl_u16_1:                             ; @rotl_u16_1
; %bb.0:
	DAD	H
	MOV	A, L
	ACI	0
	MOV	L, A
	RET
                                        ; -- End function
	.section	.text.crc16_step,"ax",@progbits
	.globl	crc16_step                      ; -- Begin function crc16_step
crc16_step:                             ; @crc16_step
; %bb.0:
	MVI	E, 0
	MOV	D, A
	MOV	A, E
	XRA	L
	MOV	E, A
	MOV	A, D
	XRA	H
	MOV	D, A
	MOV	H, D
	MOV	L, E
	DAD	D
	LXI	B, 0x1021
	MVI	A, 0xff
	SUB	E
	MVI	A, 0xff
	SBB	D
	JM	.LBB1_2
; %bb.1:
	MOV	A, L
	XRA	C
	MOV	L, A
	MOV	A, H
	XRA	B
	MOV	H, A
.LBB1_2:
	LXI	D, 0x1021
	MOV	A, L
	ADD	L
	MOV	C, A
	MOV	A, H
	ADC	H
	MOV	B, A
	MVI	A, 0xff
	SUB	L
	MVI	A, 0xff
	SBB	H
	JM	.LBB1_4
; %bb.3:
	MOV	A, C
	XRA	E
	MOV	C, A
	MOV	A, B
	XRA	D
	MOV	B, A
.LBB1_4:
	MOV	H, B
	MOV	L, C
	DAD	B
	MVI	A, 0xff
	SUB	C
	MVI	A, 0xff
	SBB	B
	JM	.LBB1_6
; %bb.5:
	MOV	A, L
	XRA	E
	MOV	L, A
	MOV	A, H
	XRA	D
	MOV	H, A
.LBB1_6:
	MOV	A, L
	ADD	L
	MOV	C, A
	MOV	A, H
	ADC	H
	MOV	B, A
	MVI	A, 0xff
	SUB	L
	MVI	A, 0xff
	SBB	H
	JM	.LBB1_8
; %bb.7:
	MOV	A, C
	XRA	E
	MOV	C, A
	MOV	A, B
	XRA	D
	MOV	B, A
.LBB1_8:
	MOV	H, B
	MOV	L, C
	DAD	B
	MVI	A, 0xff
	SUB	C
	MVI	A, 0xff
	SBB	B
	JM	.LBB1_10
; %bb.9:
	MOV	A, L
	XRA	E
	MOV	L, A
	MOV	A, H
	XRA	D
	MOV	H, A
.LBB1_10:
	MOV	A, L
	ADD	L
	MOV	C, A
	MOV	A, H
	ADC	H
	MOV	B, A
	MVI	A, 0xff
	SUB	L
	MVI	A, 0xff
	SBB	H
	JM	.LBB1_12
; %bb.11:
	MOV	A, C
	XRA	E
	MOV	C, A
	MOV	A, B
	XRA	D
	MOV	B, A
.LBB1_12:
	MOV	A, C
	ADD	C
	MOV	E, A
	MOV	A, B
	ADC	B
	MOV	D, A
	MVI	A, 0xff
	SUB	C
	MVI	A, 0xff
	SBB	B
	JM	.LBB1_14
; %bb.13:
	LXI	H, 0x1021
	MOV	A, E
	XRA	L
	MOV	E, A
	MOV	A, D
	XRA	H
	MOV	D, A
.LBB1_14:
	MOV	H, D
	MOV	L, E
	DAD	D
	MVI	A, 0xff
	SUB	E
	MVI	A, 0xff
	SBB	D
	RM
.LBB1_15:
	LXI	D, 0x1021
	MOV	A, L
	XRA	E
	MOV	L, A
	MOV	A, H
	XRA	D
	MOV	H, A
; %bb.16:
	RET
                                        ; -- End function
	.section	.text.rotl_u16_2,"ax",@progbits
	.globl	rotl_u16_2                      ; -- Begin function rotl_u16_2
rotl_u16_2:                             ; @rotl_u16_2
; %bb.0:
	MOV	E, H
	MVI	D, 0
	MOV	A, E
	ORA	A
	RAR
	MOV	E, A
	MOV	A, E
	ORA	A
	RAR
	MOV	E, A
	MOV	A, E
	ORA	A
	RAR
	MOV	E, A
	MOV	A, E
	ORA	A
	RAR
	MOV	E, A
	MOV	A, E
	ORA	A
	RAR
	MOV	E, A
	MOV	A, E
	ORA	A
	RAR
	MOV	E, A
	DAD	H
	DAD	H
	MOV	A, L
	ORA	E
	MOV	L, A
	MOV	A, H
	ORA	D
	MOV	H, A
	RET
                                        ; -- End function
	.section	.text.fshl_u16_1,"ax",@progbits
	.globl	fshl_u16_1                      ; -- Begin function fshl_u16_1
fshl_u16_1:                             ; @fshl_u16_1
; %bb.0:
	DAD	H
	MOV	A, L
	ACI	0
	MOV	L, A
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LHLD	g_in
	DAD	H
	MOV	A, L
	ACI	0
	MOV	L, A
	SHLD	g_out
	LHLD	g_in
	MVI	E, 0
	LDA	g_byte
	MOV	D, A
	MOV	A, E
	XRA	L
	MOV	L, A
	MOV	A, D
	XRA	H
	MOV	H, A
	LXI	B, 0x1021
	MOV	A, L
	ADD	L
	MOV	E, A
	MOV	A, H
	ADC	H
	MOV	D, A
	MVI	A, 0xff
	SUB	L
	MVI	A, 0xff
	SBB	H
	JM	.LBB4_2
; %bb.1:
	MOV	A, E
	XRA	C
	MOV	E, A
	MOV	A, D
	XRA	B
	MOV	D, A
.LBB4_2:
	LXI	H, 0x1021
	MOV	A, E
	ADD	E
	MOV	C, A
	MOV	A, D
	ADC	D
	MOV	B, A
	MVI	A, 0xff
	SUB	E
	MVI	A, 0xff
	SBB	D
	JM	.LBB4_4
; %bb.3:
	MOV	A, C
	XRA	L
	MOV	C, A
	MOV	A, B
	XRA	H
	MOV	B, A
.LBB4_4:
	MOV	A, C
	ADD	C
	MOV	E, A
	MOV	A, B
	ADC	B
	MOV	D, A
	MVI	A, 0xff
	SUB	C
	MVI	A, 0xff
	SBB	B
	JM	.LBB4_6
; %bb.5:
	MOV	A, E
	XRA	L
	MOV	E, A
	MOV	A, D
	XRA	H
	MOV	D, A
.LBB4_6:
	MOV	A, E
	ADD	E
	MOV	C, A
	MOV	A, D
	ADC	D
	MOV	B, A
	MVI	A, 0xff
	SUB	E
	MVI	A, 0xff
	SBB	D
	JM	.LBB4_8
; %bb.7:
	MOV	A, C
	XRA	L
	MOV	C, A
	MOV	A, B
	XRA	H
	MOV	B, A
.LBB4_8:
	MOV	A, C
	ADD	C
	MOV	E, A
	MOV	A, B
	ADC	B
	MOV	D, A
	MVI	A, 0xff
	SUB	C
	MVI	A, 0xff
	SBB	B
	JM	.LBB4_10
; %bb.9:
	MOV	A, E
	XRA	L
	MOV	E, A
	MOV	A, D
	XRA	H
	MOV	D, A
.LBB4_10:
	MOV	A, E
	ADD	E
	MOV	C, A
	MOV	A, D
	ADC	D
	MOV	B, A
	MVI	A, 0xff
	SUB	E
	MVI	A, 0xff
	SBB	D
	JM	.LBB4_12
; %bb.11:
	MOV	A, C
	XRA	L
	MOV	C, A
	MOV	A, B
	XRA	H
	MOV	B, A
.LBB4_12:
	MOV	A, C
	ADD	C
	MOV	E, A
	MOV	A, B
	ADC	B
	MOV	D, A
	MVI	A, 0xff
	SUB	C
	MVI	A, 0xff
	SBB	B
	JM	.LBB4_13
; %bb.14:
	LXI	B, 0x1021
	MOV	A, E
	XRA	L
	MOV	E, A
	MOV	A, D
	XRA	H
	MOV	D, A
	JMP	.LBB4_15
.LBB4_13:
	LXI	B, 0x1021
.LBB4_15:
	MOV	H, D
	MOV	L, E
	DAD	D
	MVI	A, 0xff
	SUB	E
	MVI	A, 0xff
	SBB	D
	JM	.LBB4_17
; %bb.16:
	MOV	A, L
	XRA	C
	MOV	L, A
	MOV	A, H
	XRA	B
	MOV	H, A
.LBB4_17:
	SHLD	g_out
	LHLD	g_in
	MOV	E, H
	MVI	D, 0
	MOV	A, E
	ORA	A
	RAR
	MOV	E, A
	MOV	A, E
	ORA	A
	RAR
	MOV	E, A
	MOV	A, E
	ORA	A
	RAR
	MOV	E, A
	MOV	A, E
	ORA	A
	RAR
	MOV	E, A
	MOV	A, E
	ORA	A
	RAR
	MOV	E, A
	MOV	A, E
	ORA	A
	RAR
	MOV	E, A
	DAD	H
	DAD	H
	MOV	A, L
	ORA	E
	MOV	L, A
	MOV	A, H
	ORA	D
	MOV	H, A
	SHLD	g_out
	LHLD	g_in
	DAD	H
	MOV	A, L
	ACI	0
	MOV	L, A
	SHLD	g_out
	LXI	H, 0
	RET
                                        ; -- End function
	.data
	.globl	g_in                            ; @g_in
	.p2align	1, 0x0
g_in:
	DW	4660                            ; 0x1234

	.globl	g_byte                          ; @g_byte
g_byte:
	DB	90                              ; 0x5a

	.section	.bss,"aw",@nobits
	.globl	g_out                           ; @g_out
	.p2align	1, 0x0
g_out:
	DW	0                               ; 0x0

	.addrsig
	.addrsig_sym g_in
	.addrsig_sym g_byte
	.addrsig_sym g_out
