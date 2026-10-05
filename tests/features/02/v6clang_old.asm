	.text
	.globl	countdown                       ; -- Begin function countdown
countdown:                              ; @countdown
; %bb.0:
	ORA	A
	JZ	.LBB0_2
.LBB0_1:                                ; =>This Inner Loop Header: Depth=1
	STA	output_port
	DCR	A
	ORA	A
	JNZ	.LBB0_1
.LBB0_2:
	RET
                                        ; -- End function
	.globl	count_down                      ; -- Begin function count_down
count_down:                             ; @count_down
; %bb.0:
	MVI	A, 0
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	MVI	A, 5
	STA	output_port
	MVI	A, 4
	STA	output_port
	MVI	A, 3
	STA	output_port
	MVI	A, 2
	STA	output_port
	MVI	A, 1
	STA	output_port
	LXI	HL, 0
	RET
                                        ; -- End function
	.addrsig
	.addrsig_sym output_port
