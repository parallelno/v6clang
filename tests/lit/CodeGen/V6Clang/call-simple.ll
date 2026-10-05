; RUN: llc -march=v6clang < %s | FileCheck %s

; Test simple function call: caller calls callee and returns result.
; CHECK-LABEL: caller:
; CHECK:       JMP callee
declare i8 @callee()
define i8 @caller() {
  %r = call i8 @callee()
  ret i8 %r
}

; Test calling a function with one i8 argument.
; CHECK-LABEL: call_with_arg:
; CHECK:       MVI A, 5
; CHECK:       JMP func_i8
declare i8 @func_i8(i8)
define i8 @call_with_arg() {
  %r = call i8 @func_i8(i8 5)
  ret i8 %r
}

; Test calling a function with two i8 arguments.
; CHECK-LABEL: call_two_args:
; CHECK:       JMP func_two_i8
declare i8 @func_two_i8(i8, i8)
define i8 @call_two_args(i8 %a, i8 %b) {
  %r = call i8 @func_two_i8(i8 %a, i8 %b)
  ret i8 %r
}
