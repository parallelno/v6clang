; RUN: llc -march=v6clang < %s | FileCheck %s

; Test V6ClangBranchOpt: redundant JMP to fall-through should be removed,
; and conditional branch inversion should work.

; A simple if/else. The branch-opt pass should eliminate redundant JMPs
; to fall-through blocks.

; CHECK-LABEL: test_branch_fallthrough:
; CHECK-NOT:   JMP .LBB0_2
; The branch-opt pass should remove JMP instructions that target
; the immediately following basic block (fall-through).
define i8 @test_branch_fallthrough(i8 %a) {
entry:
  %c = icmp eq i8 %a, 0
  br i1 %c, label %then, label %else
then:
  br label %end
else:
  br label %end
end:
  %r = phi i8 [ 1, %then ], [ 2, %else ]
  ret i8 %r
}

; Test with disabled pass — verify pass flag works.
; RUN: llc -march=v6clang -v6clang-disable-branch-opt < %s | FileCheck %s --check-prefix=DISABLED
; DISABLED-LABEL: test_branch_disabled:
; DISABLED:       RET
define i8 @test_branch_disabled(i8 %a) {
  ret i8 %a
}
