// RUN: clang -target i8080-unknown-v6clang -S -emit-llvm %s -o - | FileCheck %s
//
// Verify calling convention: function with multiple arguments.

int callee(int a, int b, int c) {
  return a + b + c;
}
// CHECK: define {{.*}} @callee(i16 {{.*}}, i16 {{.*}}, i16 {{.*}})

int caller(void) {
  return callee(1, 2, 3);
}
// CHECK: define {{.*}} @caller()
// CHECK: call {{.*}} @callee(i16 {{.*}}, i16 {{.*}}, i16 {{.*}})
