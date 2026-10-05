	.text
	.globl	neg16                           ; -- Begin function neg16
neg16:                                  ; @neg16
	;=== int neg16(int x) ===
	;  x = HL
; %bb.0:
	;--- V6CLANG_NEG16 ---
	XRA	A
	SUB	L
	MOV	L, A
	SBB	A
	SUB	H
	MOV	H, A
	RET
                                        ; -- End function
	.globl	neg8_a                          ; -- Begin function neg8_a
neg8_a:                                 ; @neg8_a
	;=== char neg8_a(char x) ===
	;  x = A
; %bb.0:
	;--- V6CLANG_NEG8 ---
	CMA
	INR	A
	RET
                                        ; -- End function
	.globl	neg8_non_a                      ; -- Begin function neg8_non_a
neg8_non_a:                             ; @neg8_non_a
	;=== char neg8_non_a(char lead, char x) ===
	;  lead = A
	;  x = B
; %bb.0:
	XRA	A
	SUB	B
	RET
                                        ; -- End function
	.globl	neg8_mem                        ; -- Begin function neg8_mem
neg8_mem:                               ; @neg8_mem
	;=== char neg8_mem(void) ===
; %bb.0:
	LXI	H, g8
	XRA	A
	;--- V6CLANG_SUB_M_P ---
	SUB	M
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g8                              ; @g8
g8:
	DB	0                               ; 0x0
