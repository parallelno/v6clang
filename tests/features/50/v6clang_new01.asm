	.text
	.section	.text.sum4_global,"ax",@progbits
	.globl	sum4_global                     ; -- Begin function sum4_global
sum4_global:                            ; @sum4_global
	;=== char sum4_global(void) ===
; %bb.0:
	LXI	H, g_s
	LDA	g_s+1
	;--- V6CLANG_ADD_M_P ---
	ADD	M
	LXI	H, g_s+2
	;--- V6CLANG_ADD_M_P ---
	ADD	M
	INX	H
	;--- V6CLANG_ADD_M_P ---
	ADD	M
	RET
                                        ; -- End function
	.section	.text.write4_globals,"ax",@progbits
	.globl	write4_globals                  ; -- Begin function write4_globals
write4_globals:                         ; @write4_globals
	;=== void write4_globals(char arg0) ===
	;  arg0 = A
; %bb.0:
	STA	g_a
	MOV	L, A
	INR	A
	STA	g_b
	MOV	A, L
	ADI	2
	STA	g_c
	MOV	A, L
	ADI	3
	STA	g_d
	RET
                                        ; -- End function
	.section	.text.sum4_array,"ax",@progbits
	.globl	sum4_array                      ; -- Begin function sum4_array
sum4_array:                             ; @sum4_array
	;=== char sum4_array(void* arg0) ===
	;  arg0 = HL
; %bb.0:
	MOV	D, H
	MOV	E, L
	;--- V6CLANG_INX16 ---
	INX	D
	INX	D
	INX	D
	;--- V6CLANG_LOAD8_P ---
	LDAX	D
	;--- V6CLANG_ADD_M_P ---
	ADD	M
	MOV	D, H
	MOV	E, L
	;--- V6CLANG_INX16 ---
	INX	D
	INX	D
	;--- V6CLANG_ADD_M_P ---
	XCHG
	ADD	M
	XCHG
	;--- V6CLANG_INX16 ---
	INX	H
	;--- V6CLANG_ADD_M_P ---
	ADD	M
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(int arg0, void* arg1) ===
	;  arg0 = HL
	;  arg1 = DE
; %bb.0:
	LXI	H, g_s
	LDA	g_s+1
	;--- V6CLANG_ADD_M_P ---
	ADD	M
	LXI	H, g_s+2
	;--- V6CLANG_ADD_M_P ---
	ADD	M
	INX	H
	;--- V6CLANG_ADD_M_P ---
	ADD	M
	MOV	E, A
	ADI	0xa
	STA	g_a
	MOV	A, E
	ADI	0xb
	STA	g_b
	MOV	A, E
	ADI	0xc
	STA	g_c
	LXI	H, 0x403
	SHLD	g_arr+2
	LXI	H, 0x201
	SHLD	g_arr
	MOV	A, E
	ADI	0xd
	STA	g_d
	LXI	H, g_b
	LDA	g_a
	;--- V6CLANG_ADD_M_P ---
	ADD	M
	LXI	H, g_c
	;--- V6CLANG_ADD_M_P ---
	ADD	M
	LXI	H, g_d
	;--- V6CLANG_ADD_M_P ---
	ADD	M
	CALL	ext_sink
	MVI	L, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	H, L
	MOV	L, A
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_s                             ; @g_s
g_s:

	.globl	g_a                             ; @g_a
g_a:
	DB	0                               ; 0x0

	.globl	g_b                             ; @g_b
g_b:
	DB	0                               ; 0x0

	.globl	g_c                             ; @g_c
g_c:
	DB	0                               ; 0x0

	.globl	g_d                             ; @g_d
g_d:
	DB	0                               ; 0x0

	.globl	g_arr                           ; @g_arr
g_arr:

	.addrsig
	.addrsig_sym g_a
	.addrsig_sym g_b
	.addrsig_sym g_c
	.addrsig_sym g_d
