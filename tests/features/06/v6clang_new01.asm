	.text
	.globl	read_port                       ; -- Begin function read_port
read_port:                              ; @read_port
; %bb.0:
	LDA	0x100
	RET
                                        ; -- End function
	.globl	write_port                      ; -- Begin function write_port
write_port:                             ; @write_port
; %bb.0:
	STA	0x100
	RET
                                        ; -- End function
	.globl	copy_port                       ; -- Begin function copy_port
copy_port:                              ; @copy_port
; %bb.0:
	LDA	0x100
	STA	0x200
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	MVI	A, 0x2a
	STA	0x100
	LDA	0x100
	STA	0x200
	MVI	L, 0
	LDA	0x100
	MOV	H, L
	MOV	L, A
	RET
                                        ; -- End function
	.addrsig
