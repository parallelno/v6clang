// RUN: clang -target i8080-unknown-v6clang -S %s -o - | FileCheck %s
//
// Verify that Clang can compile a simple C function down to V6CLANG assembly.

int add(int a, int b) {
  return a + b;
}
// CHECK: add:
// CHECK: RET
