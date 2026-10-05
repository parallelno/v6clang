// RUN: clang -target i8080-unknown-v6clang -O1 -S -emit-llvm %s -o - | FileCheck %s
//
// Verify i8 return values are not sign-extended (8080 has 8-bit registers).

char return_char(void) {
  return 42;
}
// CHECK: define {{.*}} @return_char()
// CHECK: ret i8 42

int return_int(void) {
  return 100;
}
// CHECK: define {{.*}} @return_int()
// CHECK: ret i16 100
