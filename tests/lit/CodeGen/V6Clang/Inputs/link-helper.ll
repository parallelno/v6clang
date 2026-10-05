; Helper file for link-cross-file.ll — defines helper() called from main.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

define i8 @helper(i8 %x) {
  %r = add i8 %x, 1
  ret i8 %r
}
