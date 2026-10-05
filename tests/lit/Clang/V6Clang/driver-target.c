// RUN: clang -target i8080-unknown-v6clang -### %s 2>&1 | FileCheck %s
//
// Verify that the clang driver accepts the i8080-unknown-v6clang target.

// CHECK: "-triple" "i8080-unknown-v6clang"
// CHECK: "-ffreestanding"

void dummy(void) {}
