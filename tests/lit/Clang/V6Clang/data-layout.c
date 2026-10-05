// RUN: clang -target i8080-unknown-v6clang -S -emit-llvm %s -o - | FileCheck %s
//
// Verify the data layout string matches design §2.2.

// CHECK: target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
// CHECK: target triple = "i8080-unknown-v6clang"

void dummy(void) {}
