	.text
	.globl	add_m                           ; -- Begin function add_m
add_m:                                  ; @add_m
; %bb.0:
	MOV	L, A
	LDAX	DE
	ADD	L
	RET
                                        ; -- End function
	.globl	sub_m                           ; -- Begin function sub_m
sub_m:                                  ; @sub_m
; %bb.0:
	PUSH	HL
	MOV	H, D
	MOV	L, E
	MOV	L, M
	POP	HL
	SUB	L
	RET
                                        ; -- End function
	.globl	and_m                           ; -- Begin function and_m
and_m:                                  ; @and_m
; %bb.0:
	MOV	L, A
	LDAX	DE
	ANA	L
	RET
                                        ; -- End function
	.globl	or_m                            ; -- Begin function or_m
or_m:                                   ; @or_m
; %bb.0:
	MOV	L, A
	LDAX	DE
	ORA	L
	RET
                                        ; -- End function
	.globl	xor_m                           ; -- Begin function xor_m
xor_m:                                  ; @xor_m
; %bb.0:
	MOV	L, A
	LDAX	DE
	XRA	L
	RET
                                        ; -- End function
	.globl	cmp_m                           ; -- Begin function cmp_m
cmp_m:                                  ; @cmp_m
; %bb.0:
	MOV	H, A
	LDAX	DE
	MVI	L, 0
	CMP	H
	MOV	A, L
	JNZ	.LBB5_2
; %bb.1:
	INR	A
.LBB5_2:
	MOV	H, L
	MOV	L, A
	RET
                                        ; -- End function
	.globl	store_imm                       ; -- Begin function store_imm
store_imm:                              ; @store_imm
; %bb.0:
	MVI	A, 0x42
	MOV	M, A
	RET
                                        ; -- End function
	.globl	inc_m                           ; -- Begin function inc_m
inc_m:                                  ; @inc_m
; %bb.0:
	MOV	A, M
	INR	A
	MOV	M, A
	RET
                                        ; -- End function
	.globl	dec_m                           ; -- Begin function dec_m
dec_m:                                  ; @dec_m
; %bb.0:
	MOV	A, M
	DCR	A
	MOV	M, A
	RET
                                        ; -- End function
	.globl	sum_bytes                       ; -- Begin function sum_bytes
sum_bytes:                              ; @sum_bytes
; %bb.0:
	MOV	A, E
	ORA	A
	JZ	.LBB9_1
; %bb.3:
	MVI	C, 0
	MOV	D, C
	MOV	E, A
.LBB9_4:                                ; =>This Inner Loop Header: Depth=1
	MOV	A, M
	ADD	C
	INX	HL
	DCX	DE
	MOV	B, A
	MOV	C, A
	MOV	A, D
	ORA	E
	JNZ	.LBB9_4
; %bb.2:
	MOV	A, B
	RET
.LBB9_1:
	MOV	B, A
	MOV	A, B
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LDA	main.buf.1
	MOV	L, A
	INR	A
	STA	main.buf.1
	LDA	main.buf.2
	DCR	A
	STA	main.buf.2
	MOV	H, A
	MOV	A, L
	ADD	H
	ADI	0x47
	MOV	L, A
	MVI	A, 0
	MOV	H, A
	RET
                                        ; -- End function
	.data
main.buf.1:                             ; @main.buf.1
	DB	2                               ; 0x2

main.buf.2:                             ; @main.buf.2
	DB	3                               ; 0x3

	.addrsig
