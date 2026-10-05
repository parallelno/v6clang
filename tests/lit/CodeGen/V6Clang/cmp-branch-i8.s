	.text
	.text
	.globl	branch_eq                       ; -- Begin function branch_eq
branch_eq:                              ; @branch_eq
; %bb.0:                                ; %entry
	CMP	E
	JNZ	.LBB0_2
	JMP	.LBB0_1
.LBB0_1:                                ; %then
	MVI	A, 1
	RET
.LBB0_2:                                ; %else
	MVI	A, 0
	RET
                                        ; -- End function
	.globl	branch_ult                      ; -- Begin function branch_ult
branch_ult:                             ; @branch_ult
; %bb.0:                                ; %entry
	CMP	E
	JNC	.LBB1_2
	JMP	.LBB1_1
.LBB1_1:                                ; %then
	MVI	A, 1
	RET
.LBB1_2:                                ; %else
	MVI	A, 0
	RET
                                        ; -- End function
	.globl	branch_slt                      ; -- Begin function branch_slt
branch_slt:                             ; @branch_slt
; %bb.0:                                ; %entry
	CMP	E
	JP	.LBB2_2
	JMP	.LBB2_1
.LBB2_1:                                ; %then
	MVI	A, 1
	RET
.LBB2_2:                                ; %else
	MVI	A, 0
	RET
                                        ; -- End function
	.globl	branch_eq_imm                   ; -- Begin function branch_eq_imm
branch_eq_imm:                          ; @branch_eq_imm
; %bb.0:                                ; %entry
	CPI	0x2a
	JNZ	.LBB3_2
	JMP	.LBB3_1
.LBB3_1:                                ; %then
	MVI	A, 1
	RET
.LBB3_2:                                ; %else
	MVI	A, 0
	RET
                                        ; -- End function
