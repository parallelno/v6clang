	.text
	.section	.text.notify,"ax",@progbits
	.globl	notify                          ; -- Begin function notify
notify:                                 ; @notify
; %bb.0:
	LXI	H, observed
	INR	M
	RET
                                        ; -- End function
	.section	.text.cb_eq,"ax",@progbits
	.globl	cb_eq                           ; -- Begin function cb_eq
cb_eq:                                  ; @cb_eq
; %bb.0:
	ORA	A
	CZ	notify
; %bb.2:
	LDA	observed
	INR	A
	RET
                                        ; -- End function
	.section	.text.cb_ne,"ax",@progbits
	.globl	cb_ne                           ; -- Begin function cb_ne
cb_ne:                                  ; @cb_ne
; %bb.0:
	ORA	A
	CNZ	notify
; %bb.2:
	LDA	observed
	INR	A
	RET
                                        ; -- End function
	.section	.text.cb_ult,"ax",@progbits
	.globl	cb_ult                          ; -- Begin function cb_ult
cb_ult:                                 ; @cb_ult
; %bb.0:
	MVI	A, 0x63
	SUB	L
	MVI	A, 0
	SBB	H
	CNC	notify
; %bb.2:
	LDA	observed
	INR	A
	RET
                                        ; -- End function
	.section	.text.cb_uge,"ax",@progbits
	.globl	cb_uge                          ; -- Begin function cb_uge
cb_uge:                                 ; @cb_uge
; %bb.0:
	MVI	A, 0x63
	SUB	L
	MVI	A, 0
	SBB	H
	CC	notify
; %bb.2:
	LDA	observed
	INR	A
	RET
                                        ; -- End function
	.section	.text.cb_slt,"ax",@progbits
	.globl	cb_slt                          ; -- Begin function cb_slt
cb_slt:                                 ; @cb_slt
; %bb.0:
	MVI	A, 0xff
	SUB	L
	MVI	A, 0xff
	SBB	H
	CP	notify
; %bb.2:
	LDA	observed
	INR	A
	RET
                                        ; -- End function
	.section	.text.cb_sge,"ax",@progbits
	.globl	cb_sge                          ; -- Begin function cb_sge
cb_sge:                                 ; @cb_sge
; %bb.0:
	MVI	A, 0xff
	SUB	L
	MVI	A, 0xff
	SBB	H
	CM	notify
; %bb.2:
	LDA	observed
	INR	A
	RET
                                        ; -- End function
	.section	.text.produce,"ax",@progbits
	.globl	produce                         ; -- Begin function produce
produce:                                ; @produce
; %bb.0:
	LXI	H, observed
	MVI	A, 5
	ADD	M
	RET
                                        ; -- End function
	.section	.text.cb_value_used,"ax",@progbits
	.globl	cb_value_used                   ; -- Begin function cb_value_used
cb_value_used:                          ; @cb_value_used
; %bb.0:
	ORA	A
	JZ	.LBB8_2
; %bb.1:
	CALL	produce
	JMP	.LBB8_3
.LBB8_2:
	MVI	A, 7
.LBB8_3:
	LXI	H, observed
	ADD	M
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	MVI	E, 0
	XRA	A
	CALL	cb_eq
	MVI	A, 1
	CALL	cb_ne
	LXI	H, 0x32
	CALL	cb_ult
	LXI	H, 0xc8
	CALL	cb_uge
	LXI	H, 0xffff
	CALL	cb_slt
	LXI	H, 0
	CALL	cb_sge
	MVI	A, 5
	CALL	cb_value_used
	MOV	H, E
	MOV	L, A
	LDA	observed
	MOV	D, E
	MOV	E, A
	DAD	D
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	observed                        ; @observed
observed:
	DB	0                               ; 0x0

	.addrsig
