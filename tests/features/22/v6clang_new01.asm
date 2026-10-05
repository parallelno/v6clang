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
	.globl	nested_add                      ; -- Begin function nested_add
nested_add:                             ; @nested_add
; %bb.0:
	MOV	D, H
	MOV	E, L
	CALL	get_val
	MOV	B, H
	MOV	C, L
	CALL	get_val
	DAD	BC
	MOV	B, H
	MOV	C, L
	XCHG
	DAD	BC
	CALL	use_val
	MOV	H, B
	MOV	L, C
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	CALL	get_val
	MOV	D, H
	MOV	E, L
	CALL	get_val
	DAD	DE
	XCHG
	LXI	HL, 5
	DAD	DE
	CALL	use_val
	XCHG
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	sink_val                        ; @sink_val
sink_val:
	DW	0                               ; 0x0

	.addrsig
	.addrsig_sym sink_val
