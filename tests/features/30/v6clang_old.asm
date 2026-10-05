	.text
	.globl	copy_pair                       ; -- Begin function copy_pair
copy_pair:                              ; @copy_pair
; %bb.0:
	XCHG
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	MOV	M, E
	INX	HL
	MOV	M, D
	RET
                                        ; -- End function
	.globl	load16_via_ptr                  ; -- Begin function load16_via_ptr
load16_via_ptr:                         ; @load16_via_ptr
; %bb.0:
	MOV	A, M
	INX	HL
	MOV	H, M
	MOV	L, A
	RET
                                        ; -- End function
	.globl	load16_global                   ; -- Begin function load16_global
load16_global:                          ; @load16_global
; %bb.0:
	LHLD	g_val
	RET
                                        ; -- End function
	.globl	sum_array                       ; -- Begin function sum_array
sum_array:                              ; @sum_array
; %bb.0:
	MOV	A, E
	ORA	A
	JZ	.LBB3_3
; %bb.1:
	MVI	C, 0
	MOV	D, C
	MOV	E, A
.LBB3_2:                                ; =>This Inner Loop Header: Depth=1
	MOV	A, M
	ADD	C
	INX	HL
	DCX	DE
	MOV	B, A
	MOV	C, A
	MOV	A, D
	ORA	E
	JNZ	.LBB3_2
; %bb.4:
	MOV	A, B
	RET
.LBB3_3:
	MOV	B, A
	MOV	A, B
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	MVI	A, 0xa
	CALL	use8
	MVI	A, 0x14
	CALL	use8
	LXI	HL, 0x1234
	CALL	use16
	LXI	HL, 0xabcd
	SHLD	g_val
	CALL	use16
	MVI	A, 0x64
	CALL	use8
	LXI	HL, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_val                           ; @g_val
g_val:
	DW	0                               ; 0x0

	.addrsig
