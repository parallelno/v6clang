	.text
	.globl	use_val                         ; -- Begin function use_val
use_val:                                ; @use_val
; %bb.0:
	SHLD	sink_val
	RET
                                        ; -- End function
	.globl	get_val                         ; -- Begin function get_val
get_val:                                ; @get_val
; %bb.0:
	LHLD	sink_val
	RET
                                        ; -- End function
	.globl	heavy_spill                     ; -- Begin function heavy_spill
heavy_spill:                            ; @heavy_spill
; %bb.0:
	MOV	B, D
	MOV	C, E
	SHLD	__v6clang_ss.heavy_spill+2
	INX	HL
	SHLD	__v6clang_ss.heavy_spill
	CALL	use_val
	LXI	HL, 2
	MOV	A, C
	ADD	L
	MOV	E, A
	MOV	A, B
	ADC	H
	MOV	D, A
	MOV	H, D
	MOV	L, E
	CALL	use_val
	LHLD	__v6clang_ss.heavy_spill+2
	DAD	BC
	CALL	use_val
	PUSH	HL
	LXI	HL, __v6clang_ss.heavy_spill
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	MOV	A, E
	ADD	C
	MOV	E, A
	MOV	A, D
	ADC	B
	MOV	D, A
	DAD	DE
	RET
                                        ; -- End function
	.globl	nested_calls                    ; -- Begin function nested_calls
nested_calls:                           ; @nested_calls
; %bb.0:
	MOV	D, H
	MOV	E, L
	CALL	get_val
	MOV	B, H
	MOV	C, L
	CALL	get_val
	MOV	A, L
	ADD	C
	MOV	C, A
	MOV	A, H
	ADC	B
	MOV	B, A
	MOV	A, C
	ADD	E
	MOV	L, A
	MOV	A, B
	ADC	D
	MOV	H, A
	CALL	use_val
	MOV	H, B
	MOV	L, C
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0xb
	CALL	use_val
	LXI	HL, 0x16
	CALL	use_val
	LXI	HL, 0x1e
	CALL	use_val
	LXI	HL, 0x3f
	CALL	use_val
	CALL	get_val
	MOV	D, H
	MOV	E, L
	CALL	get_val
	MOV	A, L
	ADD	E
	MOV	E, A
	MOV	A, H
	ADC	D
	MOV	D, A
	LXI	HL, 5
	DAD	DE
	CALL	use_val
	XCHG
	JMP	use_val
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	sink_val                        ; @sink_val
sink_val:
	DW	0                               ; 0x0

	.local	__v6clang_ss.heavy_spill            ; @__v6clang_ss.heavy_spill
	.comm	__v6clang_ss.heavy_spill,4,1
	.addrsig
	.addrsig_sym sink_val
