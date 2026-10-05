	.text
	.section	.text.rotl1,"ax",@progbits
	.globl	rotl1                           ; -- Begin function rotl1
rotl1:                                  ; @rotl1
; %bb.0:
	MOV	E, A
	MVI	A, 0
	MOV	H, A
	MOV	L, E
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
	MOV	A, E
	ADD	A
	ORA	L
	RET
                                        ; -- End function
	.section	.text.rotr1,"ax",@progbits
	.globl	rotr1                           ; -- Begin function rotr1
rotr1:                                  ; @rotr1
; %bb.0:
	MOV	E, A
	MVI	A, 0
	MOV	H, A
	MOV	L, E
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, E
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ORA	L
	RET
                                        ; -- End function
	.section	.text.rotl3,"ax",@progbits
	.globl	rotl3                           ; -- Begin function rotl3
rotl3:                                  ; @rotl3
; %bb.0:
	MOV	E, A
	MVI	A, 0
	MOV	H, A
	MOV	L, E
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
	MOV	A, E
	ADD	A
	ADD	A
	ADD	A
	ORA	L
	RET
                                        ; -- End function
	.section	.text.rotr3,"ax",@progbits
	.globl	rotr3                           ; -- Begin function rotr3
rotr3:                                  ; @rotr3
; %bb.0:
	MOV	E, A
	MVI	A, 0
	MOV	H, A
	MOV	L, E
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
	MOV	A, E
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ORA	L
	RET
                                        ; -- End function
	.section	.text.rotl7,"ax",@progbits
	.globl	rotl7                           ; -- Begin function rotl7
rotl7:                                  ; @rotl7
; %bb.0:
	MOV	E, A
	MVI	A, 0
	MOV	H, A
	MOV	L, E
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, E
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ORA	L
	RET
                                        ; -- End function
	.section	.text.rotl4,"ax",@progbits
	.globl	rotl4                           ; -- Begin function rotl4
rotl4:                                  ; @rotl4
; %bb.0:
	MOV	E, A
	MVI	A, 0
	MOV	H, A
	MOV	L, E
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
	MOV	A, E
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ORA	L
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	MVI	L, 0
	LDA	g_in
	MOV	D, L
	MOV	E, A
	MOV	H, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, H
	ADD	A
	ORA	E
	STA	g_out
	LDA	g_in
	MOV	D, L
	MOV	E, A
	MOV	H, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, H
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ORA	E
	STA	g_out
	LDA	g_in
	MOV	D, L
	MOV	E, A
	MOV	H, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, H
	ADD	A
	ADD	A
	ADD	A
	ORA	E
	STA	g_out
	LDA	g_in
	MOV	D, L
	MOV	E, A
	MOV	H, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, H
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ORA	E
	STA	g_out
	LDA	g_in
	MOV	D, L
	MOV	E, A
	MOV	H, A
	MOV	A, D
	ORA	A
	RAR
	MOV	D, A
	MOV	A, E
	RAR
	MOV	E, A
	MOV	A, H
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ORA	E
	STA	g_out
	LDA	g_in
	MOV	H, L
	MOV	L, A
	MOV	E, A
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
	MOV	A, E
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ORA	L
	STA	g_out
	LXI	H, 0
	RET
                                        ; -- End function
	.data
	.globl	g_in                            ; @g_in
g_in:
	DB	90                              ; 0x5a

	.section	.bss,"aw",@nobits
	.globl	g_out                           ; @g_out
g_out:
	DB	0                               ; 0x0

	.addrsig
	.addrsig_sym g_in
	.addrsig_sym g_out
