	.text
	.globl	xor_bytes                       ; -- Begin function xor_bytes
xor_bytes:                              ; @xor_bytes
; %bb.0:
	LXI	HL, __v6clang_ss.xor_bytes+2
	MOV	M, C
	LXI	HL, __v6clang_ss.xor_bytes+1
	MOV	M, E
	CALL	op
	STA	__v6clang_ss.xor_bytes
	LDA	__v6clang_ss.xor_bytes+1
	CALL	op
	STA	__v6clang_ss.xor_bytes+1
	LDA	__v6clang_ss.xor_bytes+2
	CALL	op
	STA	__v6clang_ss.xor_bytes+2
	LXI	HL, 0
	DAD	SP
	XCHG
	LDAX	DE
	CALL	op
	STA	__v6clang_ss.xor_bytes+3
	LXI	HL, 0
	DAD	SP
	XCHG
	LDAX	DE
	CALL	op
	STA	__v6clang_ss.xor_bytes+4
	LDA	__v6clang_ss.xor_bytes
	CALL	use1
	LDA	__v6clang_ss.xor_bytes+1
	LXI	HL, __v6clang_ss.xor_bytes+2
	XRA	M
	LXI	HL, __v6clang_ss.xor_bytes+3
	XRA	M
	LXI	HL, __v6clang_ss.xor_bytes+4
	XRA	M
	LXI	HL, __v6clang_ss.xor_bytes
	XRA	M
	RET
                                        ; -- End function
	.globl	and_bytes                       ; -- Begin function and_bytes
and_bytes:                              ; @and_bytes
; %bb.0:
	LXI	HL, __v6clang_ss.and_bytes+1
	MOV	M, C
	LXI	HL, __v6clang_ss.and_bytes+2
	MOV	M, E
	CALL	op
	STA	__v6clang_ss.and_bytes
	LDA	__v6clang_ss.and_bytes+2
	CALL	op
	STA	__v6clang_ss.and_bytes+2
	LDA	__v6clang_ss.and_bytes+1
	CALL	op
	STA	__v6clang_ss.and_bytes+1
	LDA	__v6clang_ss.and_bytes
	CALL	use1
	LDA	__v6clang_ss.and_bytes+2
	LXI	HL, __v6clang_ss.and_bytes+1
	ANA	M
	LXI	HL, __v6clang_ss.and_bytes
	ANA	M
	RET
                                        ; -- End function
	.globl	or_bytes                        ; -- Begin function or_bytes
or_bytes:                               ; @or_bytes
; %bb.0:
	LXI	HL, __v6clang_ss.or_bytes+1
	MOV	M, C
	LXI	HL, __v6clang_ss.or_bytes+2
	MOV	M, E
	CALL	op
	STA	__v6clang_ss.or_bytes
	LDA	__v6clang_ss.or_bytes+2
	CALL	op
	STA	__v6clang_ss.or_bytes+2
	LDA	__v6clang_ss.or_bytes+1
	CALL	op
	STA	__v6clang_ss.or_bytes+1
	LDA	__v6clang_ss.or_bytes
	CALL	use1
	LDA	__v6clang_ss.or_bytes+2
	LXI	HL, __v6clang_ss.or_bytes+1
	ORA	M
	LXI	HL, __v6clang_ss.or_bytes
	ORA	M
	RET
                                        ; -- End function
	.globl	add_bytes                       ; -- Begin function add_bytes
add_bytes:                              ; @add_bytes
; %bb.0:
	LXI	HL, __v6clang_ss.add_bytes+1
	MOV	M, C
	LXI	HL, __v6clang_ss.add_bytes+2
	MOV	M, E
	CALL	op
	STA	__v6clang_ss.add_bytes
	LDA	__v6clang_ss.add_bytes+2
	CALL	op
	STA	__v6clang_ss.add_bytes+2
	LDA	__v6clang_ss.add_bytes+1
	CALL	op
	STA	__v6clang_ss.add_bytes+1
	LDA	__v6clang_ss.add_bytes
	CALL	use1
	LXI	HL, __v6clang_ss.add_bytes
	MOV	L, M
	LDA	__v6clang_ss.add_bytes+2
	ADD	L
	LXI	HL, __v6clang_ss.add_bytes+1
	ADD	M
	RET
                                        ; -- End function
	.globl	xor_with_passthrough            ; -- Begin function xor_with_passthrough
xor_with_passthrough:                   ; @xor_with_passthrough
; %bb.0:
	LXI	HL, __v6clang_ss.xor_with_passthrough+2
	MOV	M, C
	LXI	HL, __v6clang_ss.xor_with_passthrough+1
	MOV	M, E
	CALL	op
	STA	__v6clang_ss.xor_with_passthrough
	LDA	__v6clang_ss.xor_with_passthrough+1
	CALL	op
	STA	__v6clang_ss.xor_with_passthrough+1
	LDA	__v6clang_ss.xor_with_passthrough+2
	CALL	op
	STA	__v6clang_ss.xor_with_passthrough+2
	LXI	HL, 0
	DAD	SP
	XCHG
	LDAX	DE
	CALL	op
	STA	__v6clang_ss.xor_with_passthrough+3
	LDA	__v6clang_ss.xor_with_passthrough
	LXI	HL, __v6clang_ss.xor_with_passthrough+1
	MOV	E, M
	CALL	use2
	LDA	__v6clang_ss.xor_with_passthrough+2
	LXI	HL, __v6clang_ss.xor_with_passthrough+3
	XRA	M
	LXI	HL, __v6clang_ss.xor_with_passthrough
	XRA	M
	LXI	HL, __v6clang_ss.xor_with_passthrough+1
	XRA	M
	RET
                                        ; -- End function
	.globl	inc_via_ptr                     ; -- Begin function inc_via_ptr
inc_via_ptr:                            ; @inc_via_ptr
; %bb.0:
	INR	M
	RET
                                        ; -- End function
	.globl	dec_via_ptr                     ; -- Begin function dec_via_ptr
dec_via_ptr:                            ; @dec_via_ptr
; %bb.0:
	DCR	M
	RET
                                        ; -- End function
	.globl	set_via_ptr                     ; -- Begin function set_via_ptr
set_via_ptr:                            ; @set_via_ptr
; %bb.0:
	MVI	M, 0x42
	RET
                                        ; -- End function
	.globl	inc_volatile                    ; -- Begin function inc_volatile
inc_volatile:                           ; @inc_volatile
; %bb.0:
	INR	M
	RET
                                        ; -- End function
	.globl	dec_volatile                    ; -- Begin function dec_volatile
dec_volatile:                           ; @dec_volatile
; %bb.0:
	DCR	M
	RET
                                        ; -- End function
	.globl	set_volatile                    ; -- Begin function set_volatile
set_volatile:                           ; @set_volatile
; %bb.0:
	MVI	M, 0x55
	RET
                                        ; -- End function
	.globl	inc_indexed                     ; -- Begin function inc_indexed
inc_indexed:                            ; @inc_indexed
; %bb.0:
	MVI	A, 0
	MOV	D, A
	DAD	DE
	INR	M
	RET
                                        ; -- End function
	.globl	set_indexed                     ; -- Begin function set_indexed
set_indexed:                            ; @set_indexed
; %bb.0:
	MVI	A, 0
	MOV	D, A
	DAD	DE
	MVI	M, 0x77
	RET
                                        ; -- End function
	.globl	init_buf                        ; -- Begin function init_buf
init_buf:                               ; @init_buf
; %bb.0:
	MOV	D, H
	MOV	E, L
	LXI	HL, 0x100
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	INX	DE
	INX	DE
	XCHG
	MVI	M, 0xff
	XCHG
	RET
                                        ; -- End function
	.globl	inc_via_ptr_and_read            ; -- Begin function inc_via_ptr_and_read
inc_via_ptr_and_read:                   ; @inc_via_ptr_and_read
; %bb.0:
	MOV	A, M
	INR	A
	MOV	M, A
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	MVI	A, 0x11
	CALL	op
	STA	__v6clang_ss.main
	MVI	A, 0x22
	CALL	op
	MVI	A, 0x33
	CALL	op
	MVI	A, 0x44
	CALL	op
	MVI	A, 0x55
	CALL	op
	LDA	__v6clang_ss.main
	CALL	use1
	MVI	A, 0xf0
	CALL	op
	STA	__v6clang_ss.main
	MVI	A, 0xf
	CALL	op
	MVI	A, 0xaa
	CALL	op
	LDA	__v6clang_ss.main
	CALL	use1
	MVI	A, 1
	CALL	op
	STA	__v6clang_ss.main
	MVI	A, 2
	CALL	op
	MVI	A, 4
	CALL	op
	LDA	__v6clang_ss.main
	CALL	use1
	MVI	A, 0x10
	CALL	op
	STA	__v6clang_ss.main
	MVI	A, 0x20
	CALL	op
	MVI	A, 0x30
	CALL	op
	LDA	__v6clang_ss.main
	CALL	use1
	MVI	A, 0xa1
	CALL	op
	STA	__v6clang_ss.main
	MVI	A, 0xb2
	CALL	op
	STA	__v6clang_ss.main+1
	MVI	A, 0xc3
	CALL	op
	MVI	A, 0xd4
	CALL	op
	LDA	__v6clang_ss.main
	LXI	HL, __v6clang_ss.main+1
	MOV	E, M
	CALL	use2
	LXI	HL, counter
	INR	M
	LDA	counter
	MOV	L, A
	DCR	A
	STA	counter
	MVI	A, 0xff
	STA	slot+2
	MVI	A, 0x55
	STA	flag
	MOV	A, L
	STA	counter
	LXI	HL, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	counter                         ; @counter
counter:
	DB	0                               ; 0x0

	.globl	flag                            ; @flag
flag:
	DB	0                               ; 0x0

	.globl	slot                            ; @slot
slot:
	DB	0                               ; 0x0

	.local	__v6clang_ss.xor_bytes              ; @__v6clang_ss.xor_bytes
	.comm	__v6clang_ss.xor_bytes,5,1
	.local	__v6clang_ss.and_bytes              ; @__v6clang_ss.and_bytes
	.comm	__v6clang_ss.and_bytes,3,1
	.local	__v6clang_ss.or_bytes               ; @__v6clang_ss.or_bytes
	.comm	__v6clang_ss.or_bytes,3,1
	.local	__v6clang_ss.add_bytes              ; @__v6clang_ss.add_bytes
	.comm	__v6clang_ss.add_bytes,3,1
	.local	__v6clang_ss.xor_with_passthrough   ; @__v6clang_ss.xor_with_passthrough
	.comm	__v6clang_ss.xor_with_passthrough,4,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,2,1
	.addrsig
	.addrsig_sym counter
	.addrsig_sym flag
