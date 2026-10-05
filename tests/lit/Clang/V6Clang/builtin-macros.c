// RUN: clang -target i8080-unknown-v6clang -E -dM %s -o - | FileCheck %s
//
// Verify that the V6CLANG target defines the expected built-in macros.

// CHECK-DAG: #define __V6CLANG__
// CHECK-DAG: #define __I8080__
// CHECK-DAG: #define __CHAR_UNSIGNED__
