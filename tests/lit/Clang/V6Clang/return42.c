// RUN: clang -target i8080-unknown-v6clang -O1 -S -emit-llvm %s -o - | FileCheck %s
//
// Verify that a simple function returning a constant compiles to valid IR.

int return42(void) {
  return 42;
}
// CHECK: define {{.*}} @return42()
// CHECK: ret i16 42
