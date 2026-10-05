	.text
	.globl	a_spill_r8_reload               ; -- Begin function a_spill_r8_reload
a_spill_r8_reload:                      ; @a_spill_r8_reload
	;=== char a_spill_r8_reload(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = E
; %bb.0:
	;--- V6CLANG_SPILL8 ---
	LXI	HL, __v6clang_ss.a_spill_r8_reload
	MOV	M, E
	CALL	op1
	STA	.LLo61_0+1
	;--- V6CLANG_RELOAD8 ---
	LDA	__v6clang_ss.a_spill_r8_reload
	CALL	op2
.LLo61_0:
	MVI	L, 0
	ADD	L
	RET
                                        ; -- End function
	.globl	k2_i8                           ; -- Begin function k2_i8
k2_i8:                                  ; @k2_i8
	;=== char k2_i8(char arg0, char arg1, char arg2) ===
	;  arg0 = A
	;  arg1 = E
	;  arg2 = C
; %bb.0:
	;--- V6CLANG_SPILL8 ---
	LXI	HL, __v6clang_ss.k2_i8
	MOV	M, C
	;--- V6CLANG_SPILL8 ---
	LXI	HL, __v6clang_ss.k2_i8+2
	MOV	M, E
	CALL	op1
	STA	.LLo61_1+1
	;--- V6CLANG_RELOAD8 ---
	LDA	__v6clang_ss.k2_i8+2
	CALL	op2
	MOV	H, A
.LLo61_1:
	MVI	A, 0
	ADD	A
	MOV	L, A
	MOV	A, H
	ADD	L
	STA	.LLo61_1+1
	;--- V6CLANG_RELOAD8 ---
	LDA	__v6clang_ss.k2_i8
	CALL	op2
	MOV	L, A
	LDA	.LLo61_1+1
	ADD	L
	RET
                                        ; -- End function
	.globl	multi_src_i8                    ; -- Begin function multi_src_i8
multi_src_i8:                           ; @multi_src_i8
	;=== char multi_src_i8(char arg0, char arg1, char arg2) ===
	;  arg0 = A
	;  arg1 = E
	;  arg2 = C
; %bb.0:
	;--- V6CLANG_SPILL8 ---
	LXI	HL, __v6clang_ss.multi_src_i8
	MOV	M, E
	MOV	L, A
	MOV	A, C
	ORA	A
	;--- V6CLANG_BRCOND ---
	JZ	.LBB2_2
; %bb.1:
	MOV	A, L
	CALL	op1
	JMP	.LBB2_3
.LBB2_2:
	MOV	A, L
	CALL	op2
.LBB2_3:
	STA	.LLo61_2+1
	;--- V6CLANG_RELOAD8 ---
	LDA	__v6clang_ss.multi_src_i8
	CALL	op2
.LLo61_2:
	MVI	L, 0
	ADD	L
	RET
                                        ; -- End function
	.globl	mixed_widths                    ; -- Begin function mixed_widths
mixed_widths:                           ; @mixed_widths
	;=== void mixed_widths(int arg0, char arg1) ===
	;  arg0 = HL
	;  arg1 = E
; %bb.0:
	;--- V6CLANG_SPILL8 ---
	PUSH	HL
	LXI	HL, __v6clang_ss.mixed_widths
	MOV	M, E
	POP	HL
	SHLD	.LLo61_3+1
	MOV	A, L
	CALL	op1
	MVI	L, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	H, L
	MOV	L, A
.LLo61_3:
	LXI	DE, 0
	;--- V6CLANG_ADD16 ---
	DAD	DE
	SHLD	.LLo61_4+1
	;--- V6CLANG_RELOAD8 ---
	LDA	__v6clang_ss.mixed_widths
	CALL	op2
	STA	.LLo61_5+1
	LHLD	.LLo61_3+1
	MOV	A, L
	CALL	op2
	MVI	L, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	H, L
	MOV	L, A
.LLo61_4:
	LXI	DE, 0
	;--- V6CLANG_ADD16 ---
	DAD	DE
	SHLD	.LLo61_3+1
	;--- V6CLANG_RELOAD8 ---
	LDA	__v6clang_ss.mixed_widths
	CALL	op1
	LHLD	.LLo61_3+1
	SHLD	g_u16
.LLo61_5:
	MVI	L, 0
	ADD	L
	STA	g_u8
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(void) ===
; %bb.0:
	MVI	A, 0x11
	CALL	op1
	STA	.LLo61_9+1
	MVI	A, 0x22
	CALL	op2
	STA	.LLo61_7+1
	MVI	A, 0x33
	CALL	op1
	STA	.LLo61_8+1
	MVI	A, 0x44
	CALL	op2
	MOV	H, A
	LDA	.LLo61_7+1
.LLo61_9:
	MVI	L, 0
	ADD	L
	STA	.LLo61_7+1
	MOV	A, L
	ADD	A
	MOV	L, A
	MOV	A, H
	ADD	L
	STA	.LLo61_9+1
	MVI	A, 0x55
	CALL	op2
	MOV	L, A
	LDA	.LLo61_9+1
	ADD	L
	MOV	E, A
	LDA	.LLo61_7+1
	CALL	use2
	MVI	A, 0x66
	CALL	op1
	STA	.LLo61_7+1
	MVI	A, 0x77
	CALL	op2
.LLo61_7:
	MVI	L, 0
	ADD	L
	MOV	E, L
	CALL	use2
	MVI	A, 0xcd
	CALL	op1
	MVI	L, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	H, L
	MOV	L, A
	SHLD	.LLo61_6+1
	MVI	A, 0xef
	CALL	op2
	STA	.LLo61_7+1
	MVI	A, 0xcd
	CALL	op2
	MVI	L, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	H, L
	MOV	L, A
.LLo61_6:
	LXI	DE, 0
	;--- V6CLANG_ADD16 ---
	DAD	DE
	LXI	DE, 0xabcd
	;--- V6CLANG_ADD16 ---
	DAD	DE
	SHLD	.LLo61_6+1
	MVI	A, 0xef
	CALL	op1
	LHLD	.LLo61_6+1
	SHLD	g_u16
	LXI	HL, .LLo61_7+1
	MOV	L, M
	ADD	L
	STA	g_u8
	LXI	HL, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_u16                           ; @g_u16
g_u16:
	DW	0                               ; 0x0

	.globl	g_u8                            ; @g_u8
g_u8:
	DB	0                               ; 0x0

	.local	__v6clang_ss.a_spill_r8_reload      ; @__v6clang_ss.a_spill_r8_reload
	.comm	__v6clang_ss.a_spill_r8_reload,2,1
	.local	__v6clang_ss.k2_i8                  ; @__v6clang_ss.k2_i8
	.comm	__v6clang_ss.k2_i8,3,1
	.local	__v6clang_ss.multi_src_i8           ; @__v6clang_ss.multi_src_i8
	.comm	__v6clang_ss.multi_src_i8,2,1
	.local	__v6clang_ss.mixed_widths           ; @__v6clang_ss.mixed_widths
	.comm	__v6clang_ss.mixed_widths,6,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,4,1
	.addrsig
