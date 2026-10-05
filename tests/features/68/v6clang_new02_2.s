	.text
	.section	.text.shl_u16_3,"ax",@progbits
	.globl	shl_u16_3                       ; -- Begin function shl_u16_3
shl_u16_3:                              ; @shl_u16_3
.Lfunc_begin0:
	;=== int shl_u16_3(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: shl_u16_3:x <- $hl
	;--- V6CLANG_SHL16_DAD ---
	DAD	H
	DAD	H
	DAD	H
	RET
.Lfunc_end0:
                                        ; -- End function
	.section	.text.shl_u16_9,"ax",@progbits
	.globl	shl_u16_9                       ; -- Begin function shl_u16_9
shl_u16_9:                              ; @shl_u16_9
.Lfunc_begin1:
	;=== int shl_u16_9(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: shl_u16_9:x <- $hl
	;--- V6CLANG_SHL16_RAM_HI ---
	MOV	A, L
	ADD	A
	MVI	L, 0
	MOV	H, A
	RET
.Lfunc_end1:
                                        ; -- End function
	.section	.text.shl_u16_13,"ax",@progbits
	.globl	shl_u16_13                      ; -- Begin function shl_u16_13
shl_u16_13:                             ; @shl_u16_13
.Lfunc_begin2:
	;=== int shl_u16_13(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: shl_u16_13:x <- $hl
	;--- V6CLANG_SHL16_RAM_HI ---
	MOV	A, L
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	MVI	L, 0
	MOV	H, A
	RET
.Lfunc_end2:
                                        ; -- End function
	.section	.text.shl_u16_15,"ax",@progbits
	.globl	shl_u16_15                      ; -- Begin function shl_u16_15
shl_u16_15:                             ; @shl_u16_15
.Lfunc_begin3:
	;=== int shl_u16_15(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: shl_u16_15:x <- $hl
	;--- V6CLANG_SHL16_RAM_HI ---
	MOV	A, L
	RRC
	ANI	0x80
	MVI	L, 0
	MOV	H, A
	RET
.Lfunc_end3:
                                        ; -- End function
	.section	.text.shr_u16_1,"ax",@progbits
	.globl	shr_u16_1                       ; -- Begin function shr_u16_1
shr_u16_1:                              ; @shr_u16_1
.Lfunc_begin4:
	;=== int shr_u16_1(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: shr_u16_1:x <- $hl
	;--- V6CLANG_SRL16_RAR ---
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	RET
.Lfunc_end4:
                                        ; -- End function
	.section	.text.shr_u16_2,"ax",@progbits
	.globl	shr_u16_2                       ; -- Begin function shr_u16_2
shr_u16_2:                              ; @shr_u16_2
.Lfunc_begin5:
	;=== int shr_u16_2(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: shr_u16_2:x <- $hl
	;--- V6CLANG_SRL16_RAR ---
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	RET
.Lfunc_end5:
                                        ; -- End function
	.section	.text.shr_u16_7,"ax",@progbits
	.globl	shr_u16_7                       ; -- Begin function shr_u16_7
shr_u16_7:                              ; @shr_u16_7
.Lfunc_begin6:
	;=== int shr_u16_7(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: shr_u16_7:x <- $hl
	;--- V6CLANG_SRL16_24BIT ---
	XRA	A
	DAD	H
	ADC	A
	MOV	L, H
	MOV	H, A
	RET
.Lfunc_end6:
                                        ; -- End function
	.section	.text.shr_u16_9,"ax",@progbits
	.globl	shr_u16_9                       ; -- Begin function shr_u16_9
shr_u16_9:                              ; @shr_u16_9
.Lfunc_begin7:
	;=== int shr_u16_9(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: shr_u16_9:x <- $hl
	;--- V6CLANG_SRL16_RAM_LO ---
	MOV	A, H
	RRC
	ANI	0x7f
	MOV	L, A
	MVI	H, 0
	RET
.Lfunc_end7:
                                        ; -- End function
	.section	.text.shr_u16_15,"ax",@progbits
	.globl	shr_u16_15                      ; -- Begin function shr_u16_15
shr_u16_15:                             ; @shr_u16_15
.Lfunc_begin8:
	;=== int shr_u16_15(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: shr_u16_15:x <- $hl
	;--- V6CLANG_SRL16_RAM_LO ---
	MOV	A, H
	RLC
	ANI	1
	MOV	L, A
	MVI	H, 0
	RET
.Lfunc_end8:
                                        ; -- End function
	.section	.text.sar_i16_7,"ax",@progbits
	.globl	sar_i16_7                       ; -- Begin function sar_i16_7
sar_i16_7:                              ; @sar_i16_7
.Lfunc_begin9:
	;=== int sar_i16_7(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: sar_i16_7:x <- $hl
	;--- V6CLANG_SRA16_24BIT ---
	MOV	A, H
	RLC
	SBB	A
	DAD	H
	ADC	A
	MOV	L, H
	MOV	H, A
	RET
.Lfunc_end9:
                                        ; -- End function
	.section	.text.sar_i16_9,"ax",@progbits
	.globl	sar_i16_9                       ; -- Begin function sar_i16_9
sar_i16_9:                              ; @sar_i16_9
.Lfunc_begin10:
	;=== int sar_i16_9(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: sar_i16_9:x <- $hl
	;--- V6CLANG_SRA16_RAM_LO ---
	MOV	A, H
	MOV	L, H
	RLC
	SBB	A
	MOV	H, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	RET
.Lfunc_end10:
                                        ; -- End function
	.section	.text.sar_i16_15,"ax",@progbits
	.globl	sar_i16_15                      ; -- Begin function sar_i16_15
sar_i16_15:                             ; @sar_i16_15
.Lfunc_begin11:
	;=== int sar_i16_15(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: sar_i16_15:x <- $hl
	;--- V6CLANG_SRA16_RAM_LO ---
	MOV	A, H
	RLC
	SBB	A
	MOV	H, A
	MOV	L, A
	RET
.Lfunc_end11:
                                        ; -- End function
	.section	.text.consume_pair_u16,"ax",@progbits
	.globl	consume_pair_u16                ; -- Begin function consume_pair_u16
consume_pair_u16:                       ; @consume_pair_u16
.Lfunc_begin12:
	;=== void consume_pair_u16(int a, int b) ===
	;  a = HL
	;  b = DE
; %bb.0:
	;DEBUG_VALUE: consume_pair_u16:a <- $hl
	;DEBUG_VALUE: consume_pair_u16:b <- $de
	;--- V6CLANG_XOR16 ---
	MOV	A, E
	XRA	L
	MOV	L, A
	MOV	A, D
	XRA	H
	MOV	H, A
	;--- V6CLANG_STORE16_G ---
	SHLD	g_out_u
	RET
.Lfunc_end12:
                                        ; -- End function
	.section	.text.shl_u16_3_de,"ax",@progbits
	.globl	shl_u16_3_de                    ; -- Begin function shl_u16_3_de
shl_u16_3_de:                           ; @shl_u16_3_de
.Lfunc_begin13:
	;=== void shl_u16_3_de(int keep, int x) ===
	;  keep = HL
	;  x = DE
; %bb.0:
	;DEBUG_VALUE: shl_u16_3_de:keep <- $hl
	;DEBUG_VALUE: shl_u16_3_de:x <- $de
	;--- V6CLANG_SHL16_DAD ---
	XCHG
	DAD	H
	DAD	H
	DAD	H
	XCHG
	JMP	consume_pair_u16
.Lfunc_end13:
                                        ; -- End function
	.section	.text.shr_u16_7_de,"ax",@progbits
	.globl	shr_u16_7_de                    ; -- Begin function shr_u16_7_de
shr_u16_7_de:                           ; @shr_u16_7_de
.Lfunc_begin14:
	;=== void shr_u16_7_de(int keep, int x) ===
	;  keep = HL
	;  x = DE
; %bb.0:
	;DEBUG_VALUE: shr_u16_7_de:keep <- $hl
	;DEBUG_VALUE: shr_u16_7_de:x <- $de
	;--- V6CLANG_SRL16_24BIT ---
	XCHG
	XRA	A
	DAD	H
	ADC	A
	MOV	L, H
	MOV	H, A
	XCHG
	JMP	consume_pair_u16
.Lfunc_end14:
                                        ; -- End function
	.section	.text.shr_u16_9_trunc,"ax",@progbits
	.globl	shr_u16_9_trunc                 ; -- Begin function shr_u16_9_trunc
shr_u16_9_trunc:                        ; @shr_u16_9_trunc
.Lfunc_begin15:
	;=== char shr_u16_9_trunc(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: shr_u16_9_trunc:x <- $hl
	;--- V6CLANG_SRL16_RAM_LO ---
	MOV	A, H
	RRC
	ANI	0x7f
	RET
.Lfunc_end15:
                                        ; -- End function
	.section	.text.shr_u16_15_trunc,"ax",@progbits
	.globl	shr_u16_15_trunc                ; -- Begin function shr_u16_15_trunc
shr_u16_15_trunc:                       ; @shr_u16_15_trunc
.Lfunc_begin16:
	;=== char shr_u16_15_trunc(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: shr_u16_15_trunc:x <- $hl
	;--- V6CLANG_SRL16_RAM_LO ---
	MOV	A, H
	RLC
	ANI	1
	RET
.Lfunc_end16:
                                        ; -- End function
	.section	.text.sar_i16_9_trunc,"ax",@progbits
	.globl	sar_i16_9_trunc                 ; -- Begin function sar_i16_9_trunc
sar_i16_9_trunc:                        ; @sar_i16_9_trunc
.Lfunc_begin17:
	;=== char sar_i16_9_trunc(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: sar_i16_9_trunc:x <- $hl
	;--- V6CLANG_SRA16_RAM_LO ---
	MOV	A, H
	RLC
	MOV	A, H
	RAR
	RET
.Lfunc_end17:
                                        ; -- End function
	.section	.text.sar_i16_15_trunc,"ax",@progbits
	.globl	sar_i16_15_trunc                ; -- Begin function sar_i16_15_trunc
sar_i16_15_trunc:                       ; @sar_i16_15_trunc
.Lfunc_begin18:
	;=== char sar_i16_15_trunc(int x) ===
	;  x = HL
; %bb.0:
	;DEBUG_VALUE: sar_i16_15_trunc:x <- $hl
	;--- V6CLANG_SRA16_RAM_LO ---
	MOV	A, H
	RLC
	SBB	A
	RET
.Lfunc_end18:
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
.Lfunc_begin19:
	;=== int main(void) ===
; %bb.0:
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_u
	;DEBUG_VALUE: shl_u16_3:x <- $hl
	;--- V6CLANG_SHL16_DAD ---
	DAD	H
	DAD	H
	DAD	H
	;--- V6CLANG_STORE16_G ---
	SHLD	g_out_u
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_u
	;DEBUG_VALUE: shl_u16_9:x <- $hl
	;--- V6CLANG_SHL16_RAM_HI ---
	MOV	A, L
	ADD	A
	MVI	L, 0
	MOV	H, A
	;--- V6CLANG_STORE16_G ---
	SHLD	g_out_u
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_u
	;DEBUG_VALUE: shl_u16_13:x <- $hl
	;--- V6CLANG_SHL16_RAM_HI ---
	MOV	A, L
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	ADD	A
	MVI	L, 0
	MOV	H, A
	;--- V6CLANG_STORE16_G ---
	SHLD	g_out_u
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_u
	;DEBUG_VALUE: shl_u16_15:x <- $hl
	;--- V6CLANG_SHL16_RAM_HI ---
	MOV	A, L
	RRC
	ANI	0x80
	MVI	L, 0
	MOV	H, A
	;--- V6CLANG_STORE16_G ---
	SHLD	g_out_u
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_u
	;DEBUG_VALUE: shr_u16_1:x <- $hl
	;--- V6CLANG_SRL16_RAR ---
	MOV	A, H
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	;--- V6CLANG_STORE16_G ---
	SHLD	g_out_u
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_u
	;DEBUG_VALUE: shr_u16_2:x <- $hl
	;--- V6CLANG_SRL16_RAR ---
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	MOV	A, H
	ORA	A
	RAR
	MOV	H, A
	MOV	A, L
	RAR
	MOV	L, A
	;--- V6CLANG_STORE16_G ---
	SHLD	g_out_u
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_u
	;DEBUG_VALUE: shr_u16_7:x <- $hl
	;--- V6CLANG_SRL16_24BIT ---
	XRA	A
	DAD	H
	ADC	A
	MOV	L, H
	MOV	H, A
	;--- V6CLANG_STORE16_G ---
	SHLD	g_out_u
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_u
	;DEBUG_VALUE: shr_u16_9:x <- $hl
	;--- V6CLANG_SRL16_RAM_LO ---
	MOV	A, H
	RRC
	ANI	0x7f
	MOV	L, A
	MVI	H, 0
	;--- V6CLANG_STORE16_G ---
	SHLD	g_out_u
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_u
	;DEBUG_VALUE: shr_u16_15:x <- $hl
	;--- V6CLANG_SRL16_RAM_LO ---
	MOV	A, H
	RLC
	ANI	1
	MOV	L, A
	MVI	H, 0
	;--- V6CLANG_STORE16_G ---
	SHLD	g_out_u
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_s
	;DEBUG_VALUE: sar_i16_7:x <- $hl
	;--- V6CLANG_SRA16_24BIT ---
	MOV	A, H
	RLC
	SBB	A
	DAD	H
	ADC	A
	MOV	L, H
	MOV	H, A
	;--- V6CLANG_STORE16_G ---
	SHLD	g_out_s
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_s
	;DEBUG_VALUE: sar_i16_9:x <- $hl
	;--- V6CLANG_SRA16_RAM_LO ---
	MOV	A, H
	MOV	L, H
	RLC
	SBB	A
	MOV	H, A
	MOV	A, L
	RLC
	MOV	A, L
	RAR
	MOV	L, A
	;--- V6CLANG_STORE16_G ---
	SHLD	g_out_s
	;--- V6CLANG_LOAD16_G ---
	LHLD	g_s
	;DEBUG_VALUE: sar_i16_15:x <- $hl
	;--- V6CLANG_SRA16_RAM_LO ---
	MOV	A, H
	RLC
	SBB	A
	MOV	H, A
	MOV	L, A
	;--- V6CLANG_STORE16_G ---
	SHLD	g_out_s
	LXI	H, 0
	RET
.Lfunc_end19:
                                        ; -- End function
	.data
	.globl	g_u                             ; @g_u
	.p2align	1, 0x0
g_u:
	DW	37428                           ; 0x9234

	.globl	g_s                             ; @g_s
	.p2align	1, 0x0
g_s:
	DW	37428                           ; 0x9234

	.section	.bss,"aw",@nobits
	.globl	g_out_u                         ; @g_out_u
	.p2align	1, 0x0
g_out_u:
	DW	0                               ; 0x0

	.globl	g_out_s                         ; @g_out_s
	.p2align	1, 0x0
g_out_s:
	DW	0                               ; 0x0

	.addrsig
	.addrsig_sym __mulqi3
	.addrsig_sym __v6clang_mulqihi3
	.addrsig_sym __mulhi3
	.addrsig_sym __v6clang_udivmod16_body
	.addrsig_sym __udivhi3
	.addrsig_sym __umodhi3
	.addrsig_sym __udivmodhi4
	.addrsig_sym __divmodhi4
	.addrsig_sym __v6clang_neg_hl_body
	.addrsig_sym __v6clang_neg_de_body
	.addrsig_sym __divhi3
	.addrsig_sym __modhi3
	.addrsig_sym __ashlhi3
	.addrsig_sym __lshrhi3
	.addrsig_sym __ashrhi3
	.addrsig_sym g_u
	.addrsig_sym g_s
	.addrsig_sym g_out_u
	.addrsig_sym g_out_s
